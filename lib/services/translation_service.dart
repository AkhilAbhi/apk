import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'language_settings_service.dart';
import 'malayalam_offline_translator.dart';

class TranslationService {
  static final TranslationService instance = TranslationService._init();
  TranslationService._init();

  OnDeviceTranslator? _mlKitTranslator;
  String? _currentMlKitSourceCode;

  /// Translates spoken input from currently selected language to English.
  Future<String> translateToEnglish(String sourceText) async {
    final cleanInput = sourceText.trim();
    if (cleanInput.isEmpty) return '';

    final selectedLang = await LanguageSettingsService.instance.getSelectedLanguage();
    if (selectedLang.code == 'en') {
      return cleanInput;
    }

    debugPrint('[TRANSLATE] Translating from ${selectedLang.displayName} to English...');

    // 1. Try On-Device ML Kit first if model available
    if (selectedLang.mlKitLanguage != null) {
      try {
        final bcp = selectedLang.mlKitLanguage!.bcpCode;
        final isDownloaded = await OnDeviceTranslatorModelManager().isModelDownloaded(bcp);
        if (isDownloaded) {
          if (_mlKitTranslator == null || _currentMlKitSourceCode != bcp) {
            _mlKitTranslator?.close();
            _mlKitTranslator = OnDeviceTranslator(
              sourceLanguage: selectedLang.mlKitLanguage!,
              targetLanguage: TranslateLanguage.english,
            );
            _currentMlKitSourceCode = bcp;
          }
          final translated = await _mlKitTranslator!.translateText(cleanInput);
          if (translated.trim().isNotEmpty) {
            debugPrint('[TRANSLATE] On-device ML Kit result: "$translated"');
            return translated.trim();
          }
        }
      } catch (e) {
        debugPrint('[TRANSLATE] ML Kit on-device note: $e');
      }
    }

    // 2. Try Google Translate Online endpoint
    try {
      final onlineResult = await _translateOnline(cleanInput, sourceLangCode: selectedLang.code).timeout(
        const Duration(seconds: 4),
        onTimeout: () => throw TimeoutException('Translation timeout'),
      );

      if (onlineResult != null && onlineResult.trim().isNotEmpty) {
        debugPrint('[TRANSLATE] Google Translate online result: "$onlineResult"');
        return onlineResult.trim();
      }
    } catch (_) {}

    // 3. Fallback to dictionary (Malayalam) or raw input
    if (selectedLang.code == 'ml') {
      final offlineResult = await MalayalamOfflineTranslator.instance.translateMalayalamToEnglish(cleanInput);
      debugPrint('[TRANSLATE] Dictionary offline fallback result: "$offlineResult"');
      return offlineResult;
    }

    return cleanInput;
  }

  /// Direct HTTP call to public Google Translate endpoint
  Future<String?> _translateOnline(String text, {required String sourceLangCode}) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);

    try {
      final encodedQuery = Uri.encodeComponent(text);
      final url = Uri.parse(
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=$sourceLangCode&tl=en&dt=t&q=$encodedQuery',
      );

      final request = await client.getUrl(url);
      request.headers.set('User-Agent', 'Mozilla/5.0 (Linux; Android 10)');

      final response = await request.close();
      if (response.statusCode != 200) return null;

      final responseBody = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(responseBody);

      if (decoded is List && decoded.isNotEmpty && decoded[0] is List) {
        final buffer = StringBuffer();
        for (final part in decoded[0]) {
          if (part is List && part.isNotEmpty && part[0] != null) {
            buffer.write(part[0].toString());
          }
        }
        final result = buffer.toString().trim();
        return result.isNotEmpty ? result : null;
      }
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
    return null;
  }
}
