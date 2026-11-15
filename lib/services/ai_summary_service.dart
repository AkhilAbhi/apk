import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'key_store.dart';

class AiSummaryService {
  static final AiSummaryService instance = AiSummaryService._init();
  AiSummaryService._init();

  static const String groqModel = 'openai/gpt-oss-120b';
  static const String groqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';

  /// Generates a friendly Malayalam summary of financial figures using Groq, fallback to Gemini.
  Future<String> generateFinancialSummaryMl({
    required double received,
    required double spent,
    required double remaining,
    required double toReceive,
    required double toPay,
  }) async {
    final prompt = '''
You are a friendly personal money manager AI. Summarize these exact financial figures in clear, warm Malayalam (3 to 5 sentences):
- Total Received (ആകെ കിട്ടിയത്): ₹${received.toStringAsFixed(0)}
- Total Spent (ആകെ ചിലവാക്കിയത്): ₹${spent.toStringAsFixed(0)}
- Balance Remaining (കയ്യിലുള്ള ബാക്കി): ₹${remaining.toStringAsFixed(0)}
- Money Still to Receive (മറ്റുള്ളവരിൽ നിന്ന് കിട്ടാനുള്ള കടം): ₹${toReceive.toStringAsFixed(0)}
${toPay > 0 ? "- Money Still to Pay (തിരിച്ചു കൊടുക്കാനുള്ള കടം): ₹${toPay.toStringAsFixed(0)}" : ""}

STRICT INSTRUCTIONS:
1. Write purely in Malayalam script (no English sentences).
2. You MUST mention all these exact numbers without altering any digits.
3. Include one short, helpful financial tip at the end.
4. Keep it friendly and concise (under 80 words). Do not use markdown headers.
''';

    // 1. Try Groq
    try {
      final groqKey = KeyStore.instance.groqApiKey;
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);

      final reqBody = jsonEncode({
        'model': groqModel,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'temperature': 0.2,
      });

      final request = await client.postUrl(Uri.parse(groqEndpoint));
      request.headers.set('Authorization', 'Bearer $groqKey');
      request.headers.set('Content-Type', 'application/json; charset=UTF-8');
      request.headers.set('User-Agent', 'Mozilla/5.0');
      request.write(reqBody);

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        final data = jsonDecode(body);
        final content = data['choices']?[0]?['message']?['content'] as String?;
        if (content != null && content.trim().isNotEmpty) {
          debugPrint('[AiSummary] Generated with Groq.');
          return content.trim();
        }
      }
    } catch (e) {
      debugPrint('[AiSummary] Groq failed ($e). Trying Gemini...');
    }

    // 2. Try Gemini backup
    try {
      final geminiKey = KeyStore.instance.geminiApiKey;
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent?key=$geminiKey',
      );

      final reqBody = jsonEncode({
        "contents": [
          {
            "parts": [{"text": prompt}]
          }
        ],
        "generationConfig": {"temperature": 0.2, "maxOutputTokens": 300}
      });

      final request = await client.postUrl(url);
      request.headers.set('Content-Type', 'application/json; charset=UTF-8');
      request.write(reqBody);

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        final data = jsonDecode(body);
        final content = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
        if (content != null && content.trim().isNotEmpty) {
          debugPrint('[AiSummary] Generated with Gemini.');
          return content.trim();
        }
      }
    } catch (e) {
      debugPrint('[AiSummary] Gemini failed ($e).');
    }

    // 3. Fallback computed text (no crash)
    return 'ഇതുവരെ ആകെ ₹${received.toStringAsFixed(0)} ലഭിക്കുകയും, ₹${spent.toStringAsFixed(0)} ചിലവാക്കുകയും ചെയ്തു. നിലവിൽ നിങ്ങളുടെ കയ്യിൽ ₹${remaining.toStringAsFixed(0)} ബാക്കിയുണ്ട്. മറ്റുള്ളവരിൽ നിന്ന് കിട്ടാനുള്ള കടം ₹${toReceive.toStringAsFixed(0)} ആണ്. ചിലവുകൾ ശ്രദ്ധയോടെ കൈകാര്യം ചെയ്യുക.';
  }
}

