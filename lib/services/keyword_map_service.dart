import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import 'sentence_filter_service.dart';

class WeightedMatchResult {
  final String key;
  final double score;
  final double margin;
  final int matchedWordsCount;
  final bool isConfident;
  final String? personName;
  final String? itemName;
  final String? category;
  final Map<String, double> allScores;

  WeightedMatchResult({
    required this.key,
    required this.score,
    required this.margin,
    required this.matchedWordsCount,
    required this.isConfident,
    this.personName,
    this.itemName,
    this.category,
    required this.allScores,
  });
}

class KeywordMapService {
  static final KeywordMapService instance = KeywordMapService._init();
  KeywordMapService._init();

  // Acceptance Thresholds:
  // Accept it offline only if score >= 0.55 and clear margin over 2nd highest key (>= 0.15)
  static const double minAcceptScore = 0.55;
  static const int minMatchedWords = 1;
  static const double minMargin = 0.15;

  // Strict English loan core keywords. A loan intent can ONLY trigger if at least one is present!
  static const Set<String> loanCoreKeywords = {
    "loan", "debt", "borrow", "borrowed", "lent", "lend", "repay", "repaid",
    "return", "returned", "back", "owe", "owed", "credit"
  };

  // Strict 100% English-only keyword map (6 keys) - generic verbs/pronouns removed from loans
  static final Map<String, Map<String, List<String>>> defaultMap = {
    "loan_taken": {
      "ml": [],
      "en": ["loan", "debt", "borrow", "borrowed", "owe", "owed"]
    },
    "loan_given": {
      "ml": [],
      "en": ["loan", "debt", "lent", "lend", "credit"]
    },
    "loan_repaid_to_me": {
      "ml": [],
      "en": ["repay", "repaid", "returned", "return", "refund", "back"]
    },
    "loan_repaid_by_me": {
      "ml": [],
      "en": ["repay", "repaid", "returned", "return", "cleared", "settled", "back"]
    },
    "income": {
      "ml": [],
      "en": ["salary", "income", "earned", "profit", "wage", "wages", "deposit", "credit", "credited", "gift", "reward", "received"]
    },
    "expense": {
      "ml": [],
      "en": ["bought", "spent", "expense", "buy", "purchase", "spend", "cost", "lost", "stolen", "petrol", "fee", "bill", "rent", "paid", "pay"]
    }
  };

  Map<String, Map<String, List<String>>>? _cachedMap;

  // Temporary in-memory overrides from immediate popup edits
  final Map<String, String> _temporaryOverrides = {};

  void applyTemporaryOverride({
    required String keyword,
    required String intent,
  }) {
    final clean = keyword.trim().toLowerCase();
    if (AppDatabase.englishWordRegex.hasMatch(clean)) {
      _temporaryOverrides[clean] = intent;
      debugPrint('[TEMP_OVERRIDE] Applied temporary in-memory override: $clean -> $intent');
    }
  }

  /// Loads keyword map from local SQLite / Firestore, or initializes default
  Future<Map<String, Map<String, List<String>>>> getKeywordMap() async {
    if (_cachedMap != null) return _cachedMap!;

    final map = <String, Map<String, List<String>>>{};
    try {
      final db = await AppDatabase.instance.database;
      final res = await db.query('keyword_intent_map');
      if (res.isNotEmpty) {
        for (final row in res) {
          final key = row['intent_key'] as String;
          final enList = (jsonDecode(row['en_keywords'] as String) as List)
              .map((e) => e.toString().trim().toLowerCase())
              .where((s) => AppDatabase.englishWordRegex.hasMatch(s))
              .toList();
          map[key] = {'ml': [], 'en': enList};
        }
      }
    } catch (_) {}

    if (map.isEmpty) {
      await _saveFullMapToDb(defaultMap);
      _cachedMap = defaultMap;
      return defaultMap;
    }

    _cachedMap = map;
    return map;
  }

  /// Calculates Word Weight = 1 / (number of keys whose arrays contain that word).
  Map<String, double> _calculateWordWeights(Map<String, Map<String, List<String>>> keywordMap) {
    final wordKeyCounts = <String, int>{};
    for (final entry in keywordMap.entries) {
      final words = entry.value['en'] ?? [];
      final uniqueInKey = words.map((w) => w.trim().toLowerCase()).toSet();
      for (final w in uniqueInKey) {
        wordKeyCounts[w] = (wordKeyCounts[w] ?? 0) + 1;
      }
    }

    final weights = <String, double>{};
    wordKeyCounts.forEach((word, wordCount) {
      weights[word] = 1.0 / wordCount;
    });
    return weights;
  }

  /// Evaluates weighted match on filtered English sentence words.
  /// Enforces STRICT LOAN GUARD: If no explicit loan keyword is found, blocks all loan keys!
  Future<WeightedMatchResult> matchSentence(
    FilteredSentence sentence, {
    String? englishTranslation,
  }) async {
    final keywordMap = await getKeywordMap();
    final enWeights = _calculateWordWeights(keywordMap);
    final allKnownEnWords = enWeights.keys.toSet();

    // Check if the translated sentence contains ANY explicit English loan core keyword
    final List<String> textWords = (englishTranslation ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    final allSentenceWords = {...sentence.enWords, ...textWords};

    final bool hasExplicitLoanKeyword = allSentenceWords.any((w) {
      final clean = _normalizeEnglish(w);
      return loanCoreKeywords.contains(clean) || loanCoreKeywords.contains(w.toLowerCase());
    });

    if (!hasExplicitLoanKeyword) {
      debugPrint('[LOAN_GUARD] No explicit English loan keyword found -> Blocking loan intents, checking via AI...');
    }

    final keyScores = <String, double>{};
    final keyMatchedWords = <String, int>{};

    for (final key in keywordMap.keys) {
      final isLoanKey = key.startsWith('loan_');

      // STRICT LOAN GUARD: Block loan intents if no explicit loan keyword is present
      if (isLoanKey && !hasExplicitLoanKeyword) {
        keyScores[key] = 0.0;
        keyMatchedWords[key] = 0;
        continue;
      }

      final enKeyKeywords = keywordMap[key]!['en']!.map((w) => w.toLowerCase()).toSet();

      double enMatchWeight = 0.0;
      double enTotalSentenceWeight = 0.0;
      int enMatches = 0;

      for (final enWord in sentence.enWords) {
        final cleanWord = _normalizeEnglish(enWord);

        // Check if temporary override applies
        if (_temporaryOverrides.containsKey(cleanWord)) {
          if (_temporaryOverrides[cleanWord] == key) {
            enMatchWeight += 2.0;
            enTotalSentenceWeight += 2.0;
            enMatches += 2;
            continue;
          }
        }

        final matchedAnywhere = allKnownEnWords.where((kw) => _normalizeEnglish(kw) == cleanWord);
        if (matchedAnywhere.isNotEmpty) {
          final wWeight = enWeights[matchedAnywhere.first] ?? 0.5;
          enTotalSentenceWeight += wWeight;

          final matchesKey = enKeyKeywords.any((kw) => _normalizeEnglish(kw) == cleanWord);
          if (matchesKey) {
            enMatchWeight += wWeight;
            enMatches++;
          }
        }
      }

      final enScore = enTotalSentenceWeight > 0 ? (enMatchWeight / enTotalSentenceWeight) : 0.0;
      keyScores[key] = double.parse(enScore.toStringAsFixed(2));
      keyMatchedWords[key] = enMatches;
    }

    final sortedKeys = keyScores.keys.toList()
      ..sort((a, b) => keyScores[b]!.compareTo(keyScores[a]!));

    final bestKey = sortedKeys.first;
    final bestScore = keyScores[bestKey]!;
    final secondBestScore = sortedKeys.length > 1 ? keyScores[sortedKeys[1]]! : 0.0;
    final margin = double.parse((bestScore - secondBestScore).toStringAsFixed(2));
    final matchedCount = keyMatchedWords[bestKey] ?? 0;

    final scoreLogs = sortedKeys.map((k) => '$k=${keyScores[k]}').join(', ');
    debugPrint('[SCORES] $scoreLogs');

    final bool isConfident = bestScore >= minAcceptScore &&
        matchedCount >= minMatchedWords &&
        margin >= minMargin;

    return WeightedMatchResult(
      key: bestKey,
      score: bestScore,
      margin: margin,
      matchedWordsCount: matchedCount,
      isConfident: isConfident,
      allScores: keyScores,
    );
  }

  /// Appends new meaningful English words into the key's array (strictly English only)
  Future<void> learnKeywords({
    required String intentKey,
    required List<String> newEnKeywords,
  }) async {
    final map = await getKeywordMap();
    if (!map.containsKey(intentKey)) return;

    final curEn = map[intentKey]!['en']!;
    final addedEn = <String>[];
    const genericNonLoanWords = {
      'gave', 'give', 'given', 'got', 'get', 'me', 'i', 'paid', 'pay',
      'take', 'taken', 'was', 'were', 'had', 'have', 'has'
    };

    for (final w in newEnKeywords) {
      final clean = w.trim().toLowerCase();
      if (clean.isNotEmpty &&
          AppDatabase.englishWordRegex.hasMatch(clean) &&
          !curEn.contains(clean) &&
          !SentenceFilterService.defaultEnIgnore.contains(clean)) {
        if (intentKey.startsWith('loan_') && genericNonLoanWords.contains(clean)) {
          continue;
        }
        curEn.add(clean);
        addedEn.add(clean);
      }
    }

    if (addedEn.isNotEmpty) {
      await _saveFullMapToDb(map);
      _cachedMap = map;

      try {
        final firestore = FirebaseFirestore.instance;
        final now = DateTime.now().millisecondsSinceEpoch;
        await firestore.collection('keyword_intent_map').doc(intentKey).set({
          'intent_key': intentKey,
          'ml_keywords': [],
          'en_keywords': curEn,
          'updated_at': now,
        });

        final meta = await firestore.collection('wordlist_meta').doc('metadata').get();
        final curVer = (meta.data()?['version'] as num?)?.toInt() ?? 1;
        await firestore.collection('wordlist_meta').doc('metadata').set({
          'version': curVer + 1,
          'last_updated': now,
        });
        debugPrint('[AI_LEARN] Auto-saved new English keywords to $intentKey: $addedEn (Synced SQLite & Cloud)');
      } catch (e) {
        debugPrint('[AI_LEARN] Auto-saved new English keywords to local SQLite ($e)');
      }
    }
  }

  /// Permanently promotes keywords into corrected intent/category after 2-3 user edits
  Future<void> promoteKeywordPermanently({
    required String keyword,
    required String correctedIntent,
    String? oldIntent,
    required String correctedCategory,
  }) async {
    final cleanKw = keyword.trim().toLowerCase();
    if (!AppDatabase.englishWordRegex.hasMatch(cleanKw)) return;

    const genericNonLoanWords = {
      'gave', 'give', 'given', 'got', 'get', 'me', 'i', 'paid', 'pay',
      'take', 'taken', 'was', 'were'
    };
    if (correctedIntent.startsWith('loan_') && genericNonLoanWords.contains(cleanKw)) {
      debugPrint('[LOAN_GUARD] Prevented generic word "$cleanKw" from entering loan intent');
      return;
    }

    final map = await getKeywordMap();
    if (!map.containsKey(correctedIntent)) return;

    // Remove from oldIntent
    if (oldIntent != null && map.containsKey(oldIntent)) {
      map[oldIntent]!['en']!.remove(cleanKw);
    }

    // Add to correctedIntent
    if (!map[correctedIntent]!['en']!.contains(cleanKw)) {
      map[correctedIntent]!['en']!.add(cleanKw);
    }

    await _saveFullMapToDb(map);
    _cachedMap = map;

    // Sync to Firestore
    try {
      final firestore = FirebaseFirestore.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      await firestore.collection('keyword_intent_map').doc(correctedIntent).set({
        'intent_key': correctedIntent,
        'ml_keywords': [],
        'en_keywords': map[correctedIntent]!['en']!,
        'updated_at': now,
      });

      if (oldIntent != null && map.containsKey(oldIntent)) {
        await firestore.collection('keyword_intent_map').doc(oldIntent).set({
          'intent_key': oldIntent,
          'ml_keywords': [],
          'en_keywords': map[oldIntent]!['en']!,
          'updated_at': now,
        });
      }

      if (correctedCategory.isNotEmpty && correctedCategory != 'Other' && correctedCategory != 'Loans') {
        await firestore.collection('shared_word_list').doc(cleanKw).set({
          'word': cleanKw,
          'category': correctedCategory,
          'type': correctedIntent == 'income' ? 'income' : 'expense',
          'aliases': [cleanKw],
          'updated_at': now,
        });
        await AppDatabase.instance.addLocalWordOnly(
          cleanKw,
          category: correctedCategory,
          type: correctedIntent == 'income' ? 'income' : 'expense',
        );
      }

      final meta = await firestore.collection('wordlist_meta').doc('metadata').get();
      final curVer = (meta.data()?['version'] as num?)?.toInt() ?? 1;
      await firestore.collection('wordlist_meta').doc('metadata').set({
        'version': curVer + 1,
        'last_updated': now,
      });
      debugPrint('[PROMOTED_TO_DB] Permanently promoted "$cleanKw" to $correctedIntent ($correctedCategory) in DB & Cloud');
    } catch (e) {
      debugPrint('[PROMOTED_TO_DB] Permanently promoted "$cleanKw" to SQLite ($e)');
    }
  }

  Future<void> _saveFullMapToDb(Map<String, Map<String, List<String>>> map) async {
    try {
      final db = await AppDatabase.instance.database;
      final batch = db.batch();
      for (final entry in map.entries) {
        batch.insert(
          'keyword_intent_map',
          {
            'intent_key': entry.key,
            'ml_keywords': '[]',
            'en_keywords': jsonEncode(entry.value['en']),
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (_) {}
  }

  String _normalizeEnglish(String word) {
    final w = word.toLowerCase().trim();
    if (w == 'gave' || w == 'given' || w == 'giving') return 'give';
    if (w == 'lent' || w == 'lending') return 'lend';
    if (w == 'got' || w == 'getting') return 'get';
    if (w == 'paid' || w == 'paying') return 'pay';
    if (w == 'returned' || w == 'returning') return 'return';
    if (w == 'borrowed' || w == 'borrowing') return 'borrow';
    if (w == 'bought' || w == 'buying') return 'buy';
    if (w == 'spent' || w == 'spending') return 'spend';
    if (w == 'hitting') return 'hit';
    if (w == 'losing' || w == 'losses') return 'lost';
    if (w == 'stealing') return 'stolen';
    return w;
  }
}
