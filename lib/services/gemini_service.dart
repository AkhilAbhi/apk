import 'dart:convert';
import 'dart:io';
import 'groq_service.dart';
import 'key_store.dart';

// Alias for backwards compatibility
typedef GeminiWordResult = AiWordResult;

class GeminiService {
  static final GeminiService instance = GeminiService._init();
  GeminiService._init();

  // Fast and stable models
  static const List<String> candidateModels = [
    "gemini-3.5-flash-lite",
    "gemini-3-flash-preview",
    "gemini-3.8-flash",
  ];

  /// Calls Gemini REST API as backup classifier.
  Future<AiWordResult?> classifyWord(
    String englishWord, {
    List<String> allowedCategories = const [],
  }) async {
    final cleanWord = englishWord.trim().toLowerCase();
    if (cleanWord.isEmpty) return null;

    final categoriesStr = allowedCategories.isNotEmpty
        ? allowedCategories.join(', ')
        : 'Food, Fuel, Travel, Bills, Shopping, Salary, Healthcare, Tools, Personal, Investment, Other';

    final prompt = '''
You are a financial classification system. Given the English word or phrase: "$cleanWord"
Determine if it represents an income or expense transaction, and its most accurate category.
Possible types: "income" or "expense".
Allowed categories: $categoriesStr, Other.

STRICT INSTRUCTION: Return ONLY a valid JSON object.
Format:
{"word": "$cleanWord", "type": "expense", "category": "Food"}
''';

    final requestBody = jsonEncode({
      "contents": [
        {
          "parts": [
            {"text": prompt}
          ]
        }
      ],
      "generationConfig": {
        "temperature": 0.1,
        "maxOutputTokens": 100,
        "responseMimeType": "application/json"
      }
    });

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    final apiKey = KeyStore.instance.geminiApiKey;

    for (final model in candidateModels) {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
      );

      try {
        final request = await client.postUrl(url);
        request.headers.set('Content-Type', 'application/json; charset=UTF-8');
        request.write(requestBody);

        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();

        if (response.statusCode == 200) {
          final jsonRes = jsonDecode(responseBody);
          final candidates = jsonRes['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'];
            if (content != null && content['parts'] != null) {
              final parts = content['parts'] as List;
              for (final part in parts) {
                if (part is Map && part.containsKey('text')) {
                  final text = (part['text'] as String).trim();
                  final cleanText = text
                      .replaceAll('```json', '')
                      .replaceAll('```', '')
                      .trim();

                  dynamic parsed = jsonDecode(cleanText);
                  if (parsed is List && parsed.isNotEmpty) {
                    parsed = parsed[0];
                  }
                  if (parsed is Map<String, dynamic>) {
                    client.close();
                    return AiWordResult.fromJson(parsed, cleanWord);
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    client.close();
    return null;
  }
}
