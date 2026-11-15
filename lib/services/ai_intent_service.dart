import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import 'groq_service.dart';
import 'key_store.dart';

class AiSentenceUnderstandingResult {
  final String intent; // 'expense', 'income', 'loan_given', 'loan_taken', 'loan_repaid_to_me', 'loan_repaid_by_me'
  final String category;
  final String title; // Clean 2-3 word English title (e.g. "Lost Money", "Fuel / Petrol")
  final String? person;
  final List<String> keywordsEn;
  final List<String> promoteFromIgnore;

  AiSentenceUnderstandingResult({
    required this.intent,
    required this.category,
    required this.title,
    this.person,
    required this.keywordsEn,
    required this.promoteFromIgnore,
  });

  factory AiSentenceUnderstandingResult.fromJson(Map<String, dynamic> json) {
    List<String> parseList(dynamic val) {
      if (val is List) {
        return val
            .map((e) => e.toString().trim().toLowerCase())
            .where((s) => s.isNotEmpty && AppDatabase.englishWordRegex.hasMatch(s))
            .toList();
      }
      return [];
    }

    String intent = (json['intent'] as String? ?? 'expense').toLowerCase().trim();
    if (!const ['loan_taken', 'loan_given', 'loan_repaid_to_me', 'loan_repaid_by_me', 'income', 'expense'].contains(intent)) {
      intent = 'expense';
    }

    String title = (json['title'] as String? ?? '').trim();
    if (title.isEmpty) {
      if (intent == 'loan_given') {
        title = 'Loan Given';
      } else if (intent == 'loan_taken') {
        title = 'Loan Taken';
      } else if (intent == 'loan_repaid_to_me' || intent == 'loan_repaid_by_me') {
        title = 'Loan Repaid';
      } else if (intent == 'income') {
        title = 'Income';
      } else {
        title = 'Expense';
      }
    }

    final enKws = parseList(json['keywords_en'] ?? json['new_keywords_en']);
    final promoteKws = parseList(json['promote_from_ignore']);

    return AiSentenceUnderstandingResult(
      intent: intent,
      category: (json['category'] as String? ?? 'Other').trim(),
      title: title,
      person: json['person'] as String?,
      keywordsEn: enKws,
      promoteFromIgnore: promoteKws,
    );
  }
}

class AiIntentService {
  static final AiIntentService instance = AiIntentService._init();
  AiIntentService._init();

  /// Analyzes FULL spoken Malayalam sentence with English translation using Groq (fallback Gemini).
  /// NEVER queries single words!
  Future<AiSentenceUnderstandingResult?> understandSentence({
    required String malayalamText,
    required String englishText,
    required List<String> filteredEnWords,
    required List<String> ignoredEnWords,
    required List<String> top3Keys,
  }) async {
    debugPrint('[STEP 5] Unknown meaningful word(s) detected -> Sending full Malayalam sentence to Groq...');

    final prompt = '''
Understand the true financial meaning of this Malayalam spoken sentence.
Original Malayalam sentence: "$malayalamText"
Translated English sentence: "$englishText"
Filtered Active English Words: ${filteredEnWords.join(', ')}
Filtered Ignored English Words: ${ignoredEnWords.join(', ')}
Candidate Intents: ${top3Keys.join(', ')}

Available intents:
1. "expense" (Purchases, food, fuel, bills, lost money, stolen money, fees, rent, etc.)
2. "income" (Salary, earnings, rewards, gifts, cash received - NOT a loan)
3. "loan_given" (I lent money to someone -> to receive back)
4. "loan_taken" (Someone gave me a loan / borrowed money -> to pay back)
5. "loan_repaid_to_me" (Someone returned borrowed money back to me)
6. "loan_repaid_by_me" (I returned borrowed money back to someone)

RULES:
- A sentence is a loan ONLY if explicit loan/debt/borrow/lend words are present. Simple statements like "someone gave me money" or "i received money" are "income", NOT loans.
- Analyze the true meaning of the sentence. If any word currently in the ignored list (e.g., 'got', 'paid', 'lost', 'stolen', etc.) is actually a critical meaningful keyword for this intent/category, return it inside "promote_from_ignore" so the app can rescue it.
- If money was lost, stolen, or dropped, intent is "expense", category is "Other", title is "Lost Money" or "Stolen Money".
- Never output filler words like "even", "just", "hand", "pocket", "was" as the title or keywords.
- Create a clean human-readable 2-3 word English title (e.g., "Lost Money", "Fuel / Petrol", "Loan Given").
- Extract 1-3 core meaningful English action/item keywords (e.g., ["lost", "stolen", "petrol"]). ONLY lowercase a-z English words.

STRICT INSTRUCTION: Return ONLY a valid JSON object:
{
  "intent": "expense",
  "category": "Other",
  "title": "Lost Money",
  "person": null,
  "keywords_en": ["lost", "stolen"],
  "promote_from_ignore": ["lost"]
}
''';

    // 1. Try Groq Primary
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
      client.connectionTimeout = const Duration(seconds: 8);
      final req = await client.postUrl(Uri.parse(GroqService.endpoint));
      req.headers.set('Authorization', 'Bearer $apiKey');
      req.headers.set('Content-Type', 'application/json; charset=UTF-8');
      req.headers.set('User-Agent', 'Mozilla/5.0');
      req.write(body);

      final resp = await req.close();
      final respBody = await resp.transform(utf8.decoder).join();
      client.close();

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(respBody);
        final content = decoded['choices']?[0]?['message']?['content'] as String?;
        if (content != null && content.isNotEmpty) {
          final parsed = jsonDecode(content);
          if (parsed is Map<String, dynamic>) {
            final res = AiSentenceUnderstandingResult.fromJson(parsed);
            debugPrint('[STEP 5] Groq result: intent=${res.intent}, category=${res.category}, title="${res.title}", learned_keywords=${res.keywordsEn}, rescue=${res.promoteFromIgnore}');
            return res;
          }
        }
      }
    } catch (e) {
      debugPrint('[STEP 5] Groq failed: $e. Switching to Gemini backup...');
    }

    // 2. Try Gemini Backup
    try {
      final apiKey = KeyStore.instance.geminiApiKey;
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);

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

      final req = await client.postUrl(url);
      req.headers.set('Content-Type', 'application/json; charset=UTF-8');
      req.write(reqBody);

      final resp = await req.close();
      final respBody = await resp.transform(utf8.decoder).join();
      client.close();

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(respBody);
        final parts = decoded['candidates']?[0]?['content']?['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          final text = parts[0]['text'] as String;
          final clean = text.replaceAll('```json', '').replaceAll('```', '').trim();
          final parsed = jsonDecode(clean);
          if (parsed is Map<String, dynamic>) {
            final res = AiSentenceUnderstandingResult.fromJson(parsed);
            debugPrint('[STEP 5] Gemini result: intent=${res.intent}, category=${res.category}, title="${res.title}", learned_keywords=${res.keywordsEn}, rescue=${res.promoteFromIgnore}');
            return res;
          }
        }
      }
    } catch (e) {
      debugPrint('[STEP 5] Gemini failed: $e');
    }

    return null;
  }
}
