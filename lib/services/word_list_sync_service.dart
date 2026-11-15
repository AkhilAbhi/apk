import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import '../data/default_word_list.dart';
import '../models/category_keyword_model.dart';
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
  /// 3. Downloads `category_keywords` collection (grouped arrays) and saves to local SQLite.
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

      debugPrint('[STEP 4] Category keywords last_updated check: local=$localLastUpdated, server=$serverLastUpdated -> ${hasChanged ? "CHANGED" : "NOT CHANGED"}');

      if (hasChanged) {
        debugPrint('[STEP 4] Downloading category_keywords arrays from Firestore... saving to local SQLite...');
        final querySnap = await firestore
            .collection('category_keywords')
            .limit(100)
            .get()
            .timeout(const Duration(seconds: 6));

        final List<CategoryKeywords> remoteCategories = [];

        if (querySnap.docs.isNotEmpty) {
          for (final doc in querySnap.docs) {
            final data = doc.data();
            final category = (data['category'] ?? doc.id).toString().trim();
            final rawKeywords = data['keywords'];

            final List<String> cleanKeywords = [];
            if (rawKeywords is List) {
              for (final w in rawKeywords) {
                final str = w.toString().trim().toLowerCase();
                if (AppDatabase.isValidKeyword(str)) {
                  cleanKeywords.add(str);
                }
              }
            } else if (rawKeywords is String) {
              try {
                final dec = jsonDecode(rawKeywords);
                if (dec is List) {
                  for (final w in dec) {
                    final str = w.toString().trim().toLowerCase();
                    if (AppDatabase.isValidKeyword(str)) {
                      cleanKeywords.add(str);
                    }
                  }
                }
              } catch (_) {}
            }

            final updatedAt = (data['last_updated'] as num?)?.toInt() ??
                (data['updated_at'] as num?)?.toInt() ??
                serverLastUpdated;

            remoteCategories.add(CategoryKeywords(
              category: category,
              keywords: cleanKeywords.toSet().toList(),
              lastUpdated: updatedAt,
            ));
          }
        } else {
          // If Firestore collection is empty, initialize it with default categories!
          debugPrint('[STEP 4] Firestore category_keywords collection was empty. Seeding defaults...');
          remoteCategories.addAll(DefaultWordList.initialCategoryKeywords);
          await _seedFirestoreCategories(remoteCategories, serverVersion, DateTime.now().millisecondsSinceEpoch);
        }

        // Clean local and replace with fresh database categories
        await db.clearAndSeedCategoryKeywords(remoteCategories);
        await db.setLocalMeta(serverVersion, serverLastUpdated);

        final newCount = await db.getWordCount();
        debugPrint('[STEP 4] Downloaded ${remoteCategories.length} categories ($newCount unique keywords).');

        return WordListSyncResult(
          isSuccess: true,
          totalLocalWords: newCount,
          syncedFromRemote: newCount,
          source: 'Firestore & Local SQLite',
          message: 'Synced ${remoteCategories.length} categories ($newCount words) from database.',
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

  Future<void> _seedFirestoreCategories(List<CategoryKeywords> categories, int version, int now) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      for (final cat in categories) {
        final docRef = firestore.collection('category_keywords').doc(cat.category);
        batch.set(docRef, {
          'category': cat.category,
          'keywords': cat.keywords,
          'last_updated': now,
        });
      }
      final metaDoc = firestore.collection('wordlist_meta').doc('metadata');
      batch.set(metaDoc, {
        'version': version + 1,
        'last_updated': now,
      });
      await batch.commit();
      debugPrint('[FIRESTORE] Seeded ${categories.length} category_keywords arrays');
    } catch (e) {
      debugPrint('[FIRESTORE] Note on seeding: $e');
    }
  }

  /// Appends a new keyword into category_keywords in local SQLite and Firestore Array (FieldValue.arrayUnion)
  /// STRICT PRE-SAVE FILTER:
  /// - Blocks numbers (e.g., '1000', '500')
  /// - Blocks strings with length < 2
  /// - Enforces pure alphabetical English [a-z]+
  Future<bool> saveKeywordToCategory({
    required String category,
    required String keyword,
    String type = 'expense',
  }) async {
    final clean = keyword.trim().toLowerCase();
    if (!AppDatabase.isValidKeyword(clean)) {
      debugPrint('[PRE_SAVE_FILTER] Blocked numeric or invalid junk keyword: "$clean"');
      return false;
    }

    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Local SQLite: Append keyword to category array
      await AppDatabase.instance.addKeywordToCategory(
        category: category,
        keyword: clean,
        type: type,
      );

      // 2. Remote Firestore: Use FieldValue.arrayUnion to append without duplicate rows
      final firestore = FirebaseFirestore.instance;
      await firestore.collection('category_keywords').doc(category).set({
        'category': category,
        'keywords': FieldValue.arrayUnion([clean]),
        'last_updated': now,
      }, SetOptions(merge: true));

      // 3. Update metadata
      final metaDoc = await firestore.collection('wordlist_meta').doc('metadata').get();
      int curVersion = 1;
      if (metaDoc.exists) {
        curVersion = (metaDoc.data()?['version'] as num?)?.toInt() ?? 1;
      }
      final newVersion = curVersion + 1;

      await firestore.collection('wordlist_meta').doc('metadata').set({
        'version': newVersion,
        'last_updated': now,
      });

      debugPrint('[STEP 6] Appended "$clean" to category "$category" in SQLite & Firestore Array');
      return true;
    } catch (e) {
      debugPrint('[STEP 6] Remote sync note: $e');
      return true;
    }
  }

  /// Adapter for existing GeminiWordResult calls
  Future<bool> saveNewWordToDatabase(GeminiWordResult item) async {
    return await saveKeywordToCategory(
      category: item.category,
      keyword: item.word,
      type: item.type,
    );
  }

  /// One-time startup cleanup: Purges all numbers and non-alphabetical words from Firestore category_keywords
  /// and deletes legacy shared_word_list documents if present
  Future<void> purgeNonEnglishRemoteWords() async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Clean category_keywords arrays
      final querySnap = await firestore
          .collection('category_keywords')
          .get()
          .timeout(const Duration(seconds: 8));

      for (final doc in querySnap.docs) {
        final data = doc.data();
        final raw = data['keywords'];
        if (raw is List) {
          final original = raw.map((e) => e.toString().trim().toLowerCase()).toList();
          final filtered = original.where((w) => AppDatabase.isValidKeyword(w)).toSet().toList();
          if (filtered.length != original.length) {
            await doc.reference.update({
              'keywords': filtered,
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            });
            debugPrint('[CLEANUP] Cleaned category "${doc.id}": removed ${original.length - filtered.length} numeric/junk items');
          }
        }
      }

      // Cleanup legacy shared_word_list if accessible
      final legacySnap = await firestore
          .collection('shared_word_list')
          .limit(20)
          .get()
          .timeout(const Duration(seconds: 4));
      if (legacySnap.docs.isNotEmpty) {
        final batch = firestore.batch();
        for (final doc in legacySnap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        debugPrint('[CLEANUP] Purged legacy shared_word_list documents');
      }
    } catch (e) {
      debugPrint('[MIGRATION] Remote category cleanup error/offline: $e');
    }
  }
}
