import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import '../models/shared_word_model.dart';
import 'gemini_service.dart';

class WordListSyncResult {
  final bool isSuccess;
  final int totalLocalWords;
  final int syncedFromRemote;
  final String source;
  final String message;

  WordListSyncResult({
    required this.isSuccess,
    required this.totalLocalWords,
    required this.syncedFromRemote,
    required this.source,
    required this.message,
  });
}

class WordListSyncService {
  static final WordListSyncService instance = WordListSyncService._init();
  WordListSyncService._init();

  /// Performs Part 2 app startup sync:
  /// 1. Reads local last_updated from DB.
  /// 2. Compares with Firestore server metadata (version & last_updated).
  /// 3. If changed or first run, downloads words and saves to local SQLite.
  Future<WordListSyncResult> syncOnStartup({bool forceRemote = false}) async {
    final db = AppDatabase.instance;
    await db.purgeNonEnglishWords();
    await purgeNonEnglishRemoteWords();

    final int localCount = await db.getWordCount();
    final int localLastUpdated = await db.getLocalLastUpdated();

    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Fetch remote metadata from wordlist_meta/metadata
      final metaDoc = await firestore
          .collection('wordlist_meta')
          .doc('metadata')
          .get()
          .timeout(const Duration(seconds: 4));

      int serverLastUpdated = 0;
      int serverVersion = 1;

      if (metaDoc.exists) {
        final data = metaDoc.data();
        serverLastUpdated = (data?['last_updated'] as num?)?.toInt() ?? 0;
        serverVersion = (data?['version'] as num?)?.toInt() ?? 1;
      }

      final bool hasChanged = forceRemote || (serverLastUpdated > localLastUpdated) || (localCount == 0);

      debugPrint('[STEP 4] Database last_updated check: local=$localLastUpdated, server=$serverLastUpdated -> ${hasChanged ? "CHANGED" : "NOT CHANGED"}');

      if (hasChanged) {
        debugPrint('[STEP 4] Downloading updates... saving to local SQLite...');
        final querySnap = await firestore
            .collection('shared_word_list')
            .limit(500)
            .get()
            .timeout(const Duration(seconds: 6));

        final List<SharedWord> remoteWords = [];
        for (final doc in querySnap.docs) {
          final data = doc.data();
          final word = (data['word'] ?? doc.id).toString().toLowerCase();
          final category = (data['category'] ?? 'Other').toString();
          final type = (data['type'] ?? 'expense').toString().toLowerCase();
          final rawAliases = data['aliases'];
          List<String> aliases = [];
          if (rawAliases is List) {
            aliases = rawAliases.map((e) => e.toString()).toList();
          } else if (rawAliases is String) {
            try {
              final dec = jsonDecode(rawAliases);
              if (dec is List) aliases = dec.map((e) => e.toString()).toList();
            } catch (_) {
              aliases = [rawAliases];
            }
          }
          final updatedAt = (data['updated_at'] as num?)?.toInt() ??
              (data['updatedAt'] as num?)?.toInt() ??
              serverLastUpdated;

          remoteWords.add(SharedWord(
            word: word,
            category: category,
            type: type,
            aliases: aliases,
            updatedAt: updatedAt,
          ));
        }

        // Clean local and replace with fresh database words
        await db.clearAndSeedWords(remoteWords);
        await db.setLocalMeta(serverVersion, serverLastUpdated);

        final newCount = await db.getWordCount();
        debugPrint('[STEP 4] Downloaded ${remoteWords.length} words from database. Total local: $newCount.');

        return WordListSyncResult(
          isSuccess: true,
          totalLocalWords: newCount,
          syncedFromRemote: remoteWords.length,
          source: 'Firestore & Local SQLite',
          message: 'Synced ${remoteWords.length} words from database.',
        );
      } else {
        return WordListSyncResult(
          isSuccess: true,
          totalLocalWords: localCount,
          syncedFromRemote: 0,
          source: 'Local SQLite (Up to date)',
          message: 'Local word list is up to date ($localCount words).',
        );
      }
    } catch (e) {
      debugPrint('[STEP 4] Database check offline/error: $e. Using local SQLite.');
      return WordListSyncResult(
        isSuccess: false,
        totalLocalWords: localCount,
        syncedFromRemote: 0,
        source: 'Local SQLite',
        message: 'Using offline SQLite words: $e',
      );
    }
  }

  /// Saves a new word to the Firestore database with strict English regex guard
  /// and updates metadata (version & last_updated).
  Future<bool> saveNewWordToDatabase(GeminiWordResult item) async {
    final clean = item.word.trim().toLowerCase();
    if (!AppDatabase.englishWordRegex.hasMatch(clean)) {
      debugPrint('[GUARD] Blocked non-English word from Firestore: $clean');
      return false;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Save document to shared_word_list
      await firestore.collection('shared_word_list').doc(clean).set({
        'word': clean,
        'type': item.type,
        'category': item.category,
        'aliases': [clean],
        'updated_at': now,
      });

      // 2. Fetch current version and increment
      final metaDoc = await firestore.collection('wordlist_meta').doc('metadata').get();
      int curVersion = 1;
      if (metaDoc.exists) {
        curVersion = (metaDoc.data()?['version'] as num?)?.toInt() ?? 1;
      }
      final newVersion = curVersion + 1;

      // 3. Update metadata
      await firestore.collection('wordlist_meta').doc('metadata').set({
        'version': newVersion,
        'last_updated': now,
      });

      debugPrint('[STEP 6] Saved to database. last_updated changed to $now');
      return true;
    } catch (e) {
      debugPrint('[STEP 6] Error saving to database: $e');
      return false;
    }
  }

  /// One-time startup migration: Purges all non-English documents from Firestore shared_word_list
  Future<void> purgeNonEnglishRemoteWords() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final querySnap = await firestore
          .collection('shared_word_list')
          .get()
          .timeout(const Duration(seconds: 8));
      int deleted = 0;
      final batch = firestore.batch();
      for (final doc in querySnap.docs) {
        final word = doc.id.trim().toLowerCase();
        if (!AppDatabase.englishWordRegex.hasMatch(word)) {
          batch.delete(doc.reference);
          deleted++;
        }
      }
      if (deleted > 0) {
        await batch.commit();
        final now = DateTime.now().millisecondsSinceEpoch;
        final metaDoc = await firestore.collection('wordlist_meta').doc('metadata').get();
        final curVer = (metaDoc.data()?['version'] as num?)?.toInt() ?? 1;
        await firestore.collection('wordlist_meta').doc('metadata').set({
          'version': curVer + 1,
          'last_updated': now,
        });
        debugPrint('[MIGRATION] Purged $deleted non-English documents from Firestore shared_word_list');
      }
    } catch (e) {
      debugPrint('[MIGRATION] Remote purge error/offline: $e');
    }
  }
}
