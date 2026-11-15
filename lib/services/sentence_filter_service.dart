import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import 'amount_parser.dart';
import 'keyword_map_service.dart';

class FilteredSentence {
  final List<String> mlWords;
  final List<String> enWords;
  final double? amount;
  final List<String> removedMlWords;
  final List<String> removedEnWords;

  FilteredSentence({
    required this.mlWords,
    required this.enWords,
    required this.amount,
    required this.removedMlWords,
    required this.removedEnWords,
  });

  Map<String, dynamic> toJson() {
    return {
      'ml_words': mlWords,
      'en_words': enWords,
      'amount': amount != null ? (amount! % 1 == 0 ? amount!.toInt() : amount) : null,
    };
  }
}

class SentenceFilterService {
  static final SentenceFilterService instance = SentenceFilterService._init();
  SentenceFilterService._init();

  // Rescued words dynamically promoted by AI from ignore list
  static final Set<String> _rescuedIgnoreWords = {};

  // 1a) IGNORE words (English only) - never categorized, removed from matching unless rescued
  static const Set<String> defaultEnIgnore = {
    // Auxiliary & Articles
    'a', 'an', 'the', 'was', 'were', 'is', 'am', 'are', 'be', 'been',
    'have', 'has', 'had', 'do', 'did', 'does', 'to', 'of', 'in', 'on', 'at',
    'for', 'from', 'and', 'or', 'with', 'that', 'this', 'then', 'today', 'now',
    'by', 'as', 'into', 'onto', 'about',

    // Pronouns & Fillers
    'other', 'some', 'someone', 'somebody', 'one', 'person', 'any', 'anyone',
    'something', 'anything', 'everything', 'nothing',

    // English filler/adverb words and body/filler nouns
    'even', 'just', 'only', 'also', 'too', 'very', 'really', 'actually', 'basically',
    'hand', 'hands', 'pocket', 'pockets', 'time', 'day', 'days', 'thing', 'things',
    'way', 'ways', 'got', 'went', 'came', 'gone',

    // Currency words
    'rupee', 'rupees', 'rs', 'inr', 'buck', 'bucks',
  };

  // 100% English-only codebase: empty Malayalam set for backwards safety
  static const Set<String> defaultMlIgnore = {};

  // 1b) DIRECTION words (English only - NOT removed)
  static const Set<String> directionWords = {
    'i', 'me', 'my', 'you', 'your', 'we', 'us', 'he', 'him', 'she', 'her', 'they', 'them',
  };

  /// Filters small words, removes numbers, and separates amount.
  Future<FilteredSentence> filterSentence({
    required String malayalamText,
    required String englishText,
    double? overrideAmount,
  }) async {
    // 1. Extract Amount (respecting overrideAmount from original spoken text if provided)
    final amount = overrideAmount ?? AmountParser.parseAmount(
      englishText: englishText,
      malayalamText: malayalamText,
    );

    // 2. Fetch dynamic ignore words from local SQLite DB minus rescued words
    final dbIgnoreWords = await _getDynamicIgnoreWords();
    final allEnIgnore = {...defaultEnIgnore, ...dbIgnoreWords}..removeAll(_rescuedIgnoreWords);

    // 3. Clean Malayalam tokens (without storing Malayalam in DB)
    final cleanMl = _stripNumbersAndCurrency(malayalamText);
    final rawMlTokens = cleanMl.split(RegExp(r'[\s,।.\-]+'));
    final List<String> mlWords = [];
    final List<String> removedMl = [];

    for (final raw in rawMlTokens) {
      final token = raw.trim();
      if (token.isEmpty || token.length < 2) continue;
      if (RegExp(r'^\d+$').hasMatch(token)) continue;
      mlWords.add(token);
    }

    // 4. Clean and filter English words (strictly matching [a-z0-9_])
    final cleanEn = _stripNumbersAndCurrency(englishText);
    final rawEnTokens = cleanEn.split(RegExp(r'[\s,.\-]+'));
    final List<String> enWords = [];
    final List<String> removedEn = [];

    for (final raw in rawEnTokens) {
      final token = raw.trim().toLowerCase().replaceAll(RegExp(r'[^\w]'), '');
      if (token.isEmpty) continue;
      if (RegExp(r'^\d+$').hasMatch(token)) continue;

      if (allEnIgnore.contains(token)) {
        removedEn.add(token);
      } else {
        enWords.add(token);
      }
    }

    final filtered = FilteredSentence(
      mlWords: mlWords,
      enWords: enWords,
      amount: amount,
      removedMlWords: removedMl,
      removedEnWords: removedEn,
    );

    final removedStr = removedEn.join(', ');
    debugPrint('[FILTER] removed: $removedStr | kept: ${filtered.toJson()}');

    return filtered;
  }

  /// Rescues words identified by AI as critical keywords from the ignore list
  Future<void> rescueIgnoredWords({
    required List<String> words,
    required String intentKey,
    required String category,
  }) async {
    final validWords = words
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.isNotEmpty && AppDatabase.englishWordRegex.hasMatch(w))
        .toList();
    if (validWords.isEmpty) return;

    for (final w in validWords) {
      _rescuedIgnoreWords.add(w);
    }

    try {
      final db = await AppDatabase.instance.database;
      for (final w in validWords) {
        await db.delete(
          'shared_word_list',
          where: "word = ? AND (type = 'ignore' OR category = 'ignore')",
          whereArgs: [w],
        );
      }
    } catch (_) {}

    // Add to active keyword array
    await KeywordMapService.instance.learnKeywords(
      intentKey: intentKey,
      newEnKeywords: validWords,
    );

    // If Firestore is available, clean remote doc
    try {
      final firestore = FirebaseFirestore.instance;
      for (final w in validWords) {
        final doc = await firestore.collection('shared_word_list').doc(w).get();
        if (doc.exists && (doc.data()?['type'] == 'ignore' || doc.data()?['category'] == 'ignore')) {
          await firestore.collection('shared_word_list').doc(w).delete();
        }
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final metaDoc = await firestore.collection('wordlist_meta').doc('metadata').get();
      final curVer = (metaDoc.data()?['version'] as num?)?.toInt() ?? 1;
      await firestore.collection('wordlist_meta').doc('metadata').set({
        'version': curVer + 1,
        'last_updated': now,
      });
    } catch (_) {}

    debugPrint('[RECOVERED_FROM_IGNORE] Rescued $validWords from ignore list -> moved to $intentKey (DB & Cloud)');
  }

  String _stripNumbersAndCurrency(String text) {
    return text
        .replaceAll(RegExp(r'(?:rs\.?|inr|₹)\s*\d+(?:,\d{3})*(?:\.\d+)?', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\d+(?:,\d{3})*(?:\.\d+)?\s*(?:rupees?|rs|inr)?', caseSensitive: false), ' ');
  }

  Future<Set<String>> _getDynamicIgnoreWords() async {
    final set = <String>{};
    try {
      final db = await AppDatabase.instance.database;
      final res = await db.query(
        'shared_word_list',
        where: "type = 'ignore' OR category = 'ignore'",
      );
      for (final r in res) {
        final w = (r['word'] as String?)?.trim().toLowerCase();
        if (w != null && w.isNotEmpty && AppDatabase.englishWordRegex.hasMatch(w)) {
          set.add(w);
        }
      }
    } catch (_) {}
    return set;
  }

  /// Saves ignore words to local SQLite with English regex guard
  Future<void> addIgnoreWords(List<String> words) async {
    final db = AppDatabase.instance;
    for (final w in words) {
      final clean = w.trim().toLowerCase();
      if (clean.isEmpty || !AppDatabase.englishWordRegex.hasMatch(clean)) continue;
      await db.addLocalWordOnly(clean, category: 'ignore', type: 'ignore');
    }
  }
}
