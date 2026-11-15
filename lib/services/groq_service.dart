import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'key_store.dart';

class AiWordResult {
  final String word;
  final String type; // 'income' or 'expense'
  final String category;

  AiWordResult({
    required this.word,
    required this.type,
    required this.category,
  });

  factory AiWordResult.fromJson(Map<String, dynamic> json, String fallbackWord) {
    return AiWordResult(
      word: (json['word'] as String? ?? fallbackWord).toLowerCase().trim(),
      type: (json['type'] as String? ?? 'expense').toLowerCase().trim(),
      category: (json['category'] as String? ?? 'Other').trim(),
    );
  }
}

class GroqService {
  static final GroqService instance = GroqService._init();
  GroqService._init();

  // Fast, free-tier active Groq model
  static const String modelName = 'openai/gpt-oss-120b';
  static const String endpoint = 'https://api.groq.com/openai/v1/chat/completions';

  // Cooldown tracker for HTTP 429 rate limit
  DateTime? _cooldownUntil;

  bool get isUnderCooldown {
    if (_cooldownUntil == null) return false;
    return DateTime.now().isBefore(_cooldownUntil!);
  }

  void setCooldown(Duration duration) {
    _cooldownUntil = DateTime.now().add(duration);
  }

  /// Calls Groq OpenAI-compatible Chat Completions endpoint with JSON output.
  /// [allowedCategories] is passed to guide strict category mapping.
  /// [isRetry] enables a stricter prompt on second attempt.
  Future<AiWordResult?> classifyWord(
    String englishWord, {
    required List<String> allowedCategories,
    bool isRetry = false,
  }) async {
    final cleanWord = englishWord.trim().toLowerCase();
    if (cleanWord.isEmpty) return null;

    if (isUnderCooldown) {
      final remainingSec = _cooldownUntil!.difference(DateTime.now()).inSeconds;
      debugPrint('[GroqService] Groq is in cooldown ($remainingSec s remaining). Skipping to backup.');
      return null;
    }

    final categoriesStr = allowedCategories.join(', ');
    final systemPrompt = isRetry
        ? 'STRICT ENFORCEMENT: You are a financial classifier. Output ONLY valid JSON: {"word": "$cleanWord", "type": "income" OR "expense", "category": "<one of: $categoriesStr, or Other>"}. No other text.'
        : 'You are a financial classification system. Given the English word or phrase from a money-tracking note, return only JSON {"word": "$cleanWord", "type": "income" or "expense", "category": "<one of the allowed categories>"}.\nAllowed categories: $categoriesStr, Other.\ntype MUST be exactly "income" or "expense".';

    final requestBody = jsonEncode({
      'model': modelName,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': 'Classify: $cleanWord'}
      ],
      'response_format': {'type': 'json_object'},
      'temperature': 0,
    });

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);

    try {
      final apiKey = KeyStore.instance.groqApiKey;
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.set('Authorization', 'Bearer $apiKey');
      request.headers.set('Content-Type', 'application/json; charset=UTF-8');
      request.headers.set('User-Agent', 'Mozilla/5.0 (Linux; Android)');
      request.write(requestBody);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final jsonRes = jsonDecode(responseBody);
        final choices = jsonRes['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final content = choices[0]['message']?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            final parsed = jsonDecode(content);
            if (parsed is Map<String, dynamic>) {
              return AiWordResult.fromJson(parsed, cleanWord);
            }
          }
        }
      } else if (response.statusCode == 429) {
        debugPrint('[GroqService] HTTP 429 Rate Limit encountered. Setting 60s cooldown.');
        setCooldown(const Duration(seconds: 60));
      } else {
        debugPrint('[GroqService] HTTP ${response.statusCode}: $responseBody');
      }
    } catch (e) {
      debugPrint('[GroqService] Request error: $e');
    } finally {
      client.close();
    }

    return null;
  }
}

