import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import 'gemini_service.dart';
import 'groq_service.dart';
import 'key_store.dart';
import 'keyword_map_service.dart';
import 'sentence_filter_service.dart';

class AiRouter {
  static final AiRouter instance = AiRouter._init();
  AiRouter._init();

  /// Default categories used in the app if local DB is empty
  static const List<String> defaultCategories = [
    'Food',
    'Fuel',
    'Travel',
    'Bills',
    'Shopping',
    'Salary',
    'Healthcare',
    'Entertainment',
    'Investment',
    'Personal',
    'Education',
    'Expense',
    'Income',
    'Loans',
    'Other',
  ];

  /// Fetches allowed categories from local SQLite word list to send to AI
  Future<List<String>> _getAllowedCategories() async {
    try {
      final db = await AppDatabase.instance.database;
      final result = await db.rawQuery('SELECT DISTINCT category FROM shared_word_list WHERE category IS NOT NULL');
      final categories = result
          .map((row) => row['category'] as String?)
          .where((cat) => cat != null && cat.trim().isNotEmpty)
          .map((cat) => cat!.trim())
          .toSet();

      categories.addAll(defaultCategories);
      return categories.toList();
    } catch (_) {
      return defaultCategories;
    }
  }

  /// Validates AI response:
  /// - type must be exactly 'income' or 'expense'
  /// - category must match one of the allowed categories (case-insensitive) or be 'Other'
  AiWordResult? _validateResult(AiWordResult? result, List<String> allowedCategories) {
    if (result == null) return null;

    final type = result.type.toLowerCase().trim();
    if (type != 'income' && type != 'expense') {
      return null;
    }

    final matchedCategory = allowedCategories.firstWhere(
      (cat) => cat.toLowerCase() == result.category.toLowerCase(),
      orElse: () => 'Other',
    );

    return AiWordResult(
      word: result.word,
      type: type,
      category: matchedCategory,
    );
  }

  /// Order of providers:
  /// 1. Groq (primary) -> validation -> (retry once if invalid)
  /// 2. Gemini (backup) -> validation
  /// Returns validated result or null if both fail.
  Future<AiWordResult?> classifyWord(String word) async {
    final cleanWord = word.trim().toLowerCase();
    if (cleanWord.isEmpty || !AppDatabase.englishWordRegex.hasMatch(cleanWord)) return null;

    final allowedCategories = await _getAllowedCategories();

    // 1. Try Groq first
    debugPrint('[STEP 5] Word "$cleanWord" not found anywhere. Asking Groq...');
    var groqResult = await GroqService.instance.classifyWord(
      cleanWord,
      allowedCategories: allowedCategories,
      isRetry: false,
    );

    var validated = _validateResult(groqResult, allowedCategories);

    // If Groq gave invalid format, retry once with stricter instruction
    if (groqResult != null && validated == null) {
      debugPrint('[STEP 5] Groq response invalid format. Retrying Groq once with strict prompt...');
      groqResult = await GroqService.instance.classifyWord(
        cleanWord,
        allowedCategories: allowedCategories,
        isRetry: true,
      );
      validated = _validateResult(groqResult, allowedCategories);
    }

    if (validated != null) {
      debugPrint('[STEP 5] Groq result: type=${validated.type}, category=${validated.category} -> valid');
      return validated;
    }

    // 2. Groq failed -> Switch to Gemini backup
    debugPrint('[STEP 5] Groq failed. Switching to Gemini...');
    final geminiResult = await GeminiService.instance.classifyWord(
      cleanWord,
      allowedCategories: allowedCategories,
    );

    final validatedGemini = _validateResult(geminiResult, allowedCategories);
    if (validatedGemini != null) {
      debugPrint('[STEP 5] Gemini result: type=${validatedGemini.type}, category=${validatedGemini.category} -> valid');
      return validatedGemini;
    }

    debugPrint('[STEP 5] Both Groq and Gemini classification failed for "$cleanWord".');
    return null;
  }

  /// Pre-save AI learning step (with 3-second timeout)
  /// Sends the translated English sentence and user's confirmed intent + category
  /// to extract core English keywords and store them into SQLite & Firestore.
  Future<List<String>> learnPreSaveKeywords({
    required String englishSentence,
    required String confirmedIntent,
    required String confirmedCategory,
  }) async {
    final cleanSentence = englishSentence.trim();
    if (cleanSentence.isEmpty) return [];

    final prompt = '''
The user confirmed this transaction as intent='$confirmedIntent' and category='$confirmedCategory'.
English sentence: "$cleanSentence"

Extract the core meaningful keywords (100% lowercase English only, no ignore words, matching ^[a-z0-9_]+\$) from the English sentence that represent this intent/category. Suggest if these keywords belong to an existing category or require a new category name.

STRICT INSTRUCTION: Return ONLY a valid JSON object:
{
  "keywords": ["keyword1", "keyword2"],
  "category": "$confirmedCategory"
}
''';

    List<String> learnedWords = [];

    // Helper: Call Groq with 3-second timeout
    try {
      final apiKey = KeyStore.instance.groqApiKey;
      final body = jsonEncode({
        'model': GroqService.modelName,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'response_format': {'type': 'json_object'},
        'temperature': 0,
      });

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final req = await client.postUrl(Uri.parse(GroqService.endpoint))
          .timeout(const Duration(seconds: 3));
      req.headers.set('Authorization', 'Bearer $apiKey');
      req.headers.set('Content-Type', 'application/json; charset=UTF-8');
      req.headers.set('User-Agent', 'Mozilla/5.0');
      req.write(body);

      final resp = await req.close().timeout(const Duration(seconds: 3));
      final respBody = await resp.transform(utf8.decoder).join();
      client.close();

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(respBody);
        final content = decoded['choices']?[0]?['message']?['content'] as String?;
        if (content != null && content.isNotEmpty) {
          final parsed = jsonDecode(content);
          if (parsed is Map && parsed['keywords'] is List) {
            learnedWords = (parsed['keywords'] as List)
                .map((e) => e.toString().trim().toLowerCase())
                .where((w) => w.isNotEmpty && AppDatabase.englishWordRegex.hasMatch(w) && !SentenceFilterService.defaultEnIgnore.contains(w))
                .toList();
          }
        }
      }
    } catch (_) {
      // If Groq fails or times out, try Gemini backup with 3s timeout
      try {
        final apiKey = KeyStore.instance.geminiApiKey;
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 3);
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent?key=$apiKey',
        );
        final reqBody = jsonEncode({
          "contents": [
            {
              "parts": [{"text": prompt}]
            }
          ],
          "generationConfig": {"temperature": 0.1, "responseMimeType": "application/json"}
        });

        final req = await client.postUrl(url).timeout(const Duration(seconds: 3));
        req.headers.set('Content-Type', 'application/json; charset=UTF-8');
        req.write(reqBody);

        final resp = await req.close().timeout(const Duration(seconds: 3));
        final respBody = await resp.transform(utf8.decoder).join();
        client.close();

        if (resp.statusCode == 200) {
          final decoded = jsonDecode(respBody);
          final parts = decoded['candidates']?[0]?['content']?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text'] as String;
            final clean = text.replaceAll('```json', '').replaceAll('```', '').trim();
            final parsed = jsonDecode(clean);
            if (parsed is Map && parsed['keywords'] is List) {
              learnedWords = (parsed['keywords'] as List)
                  .map((e) => e.toString().trim().toLowerCase())
                  .where((w) => w.isNotEmpty && AppDatabase.englishWordRegex.hasMatch(w) && !SentenceFilterService.defaultEnIgnore.contains(w))
                  .toList();
            }
          }
        }
      } catch (_) {}
    }

    if (learnedWords.isNotEmpty) {
      // Database Update: Save clean English keywords into category/intent in SQLite & Firestore
      for (final kw in learnedWords) {
        if (!AppDatabase.englishWordRegex.hasMatch(kw)) continue;

        // 1. Local SQLite
        await AppDatabase.instance.addLocalWordOnly(
          kw,
          category: confirmedCategory,
          type: confirmedIntent == 'income' ? 'income' : 'expense',
        );

        // 2. Keyword map
        await KeywordMapService.instance.learnKeywords(
          intentKey: confirmedIntent,
          newEnKeywords: [kw],
        );

        // 3. Remote Firestore shared_word_list
        try {
          final firestore = FirebaseFirestore.instance;
          final now = DateTime.now().millisecondsSinceEpoch;
          await firestore.collection('shared_word_list').doc(kw).set({
            'word': kw,
            'category': confirmedCategory,
            'type': confirmedIntent == 'income' ? 'income' : 'expense',
            'aliases': [kw],
            'updated_at': now,
          });

          final metaDoc = await firestore.collection('wordlist_meta').doc('metadata').get();
          final curVer = (metaDoc.data()?['version'] as num?)?.toInt() ?? 1;
          await firestore.collection('wordlist_meta').doc('metadata').set({
            'version': curVer + 1,
            'last_updated': now,
          });
        } catch (_) {}
      }

      debugPrint('[PRE_SAVE_LEARN] Confirmed intent=$confirmedIntent, category=$confirmedCategory -> Learned English keywords: $learnedWords');
    }

    return learnedWords;
  }
}
