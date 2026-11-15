import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLanguage {
  final String code; // 'ml', 'ta', 'hi', 'kn', 'te', 'ar', 'en'
  final String speechLocale; // 'ml_IN', 'ta_IN', 'hi_IN', 'kn_IN', 'te_IN', 'ar_SA', 'en_IN'
  final String nativeName; // 'മലയാളം'
  final String englishName; // 'Malayalam'
  final TranslateLanguage? mlKitLanguage; // TranslateLanguage.tamil, etc. (null for ML where we use offline translator)

  const AppLanguage({
    required this.code,
    required this.speechLocale,
    required this.nativeName,
    required this.englishName,
    this.mlKitLanguage,
  });

  String get displayName => '$nativeName ($englishName)';
}

class LanguageSettingsService {
  static final LanguageSettingsService instance = LanguageSettingsService._init();
  LanguageSettingsService._init();

  static const String _prefLangKey = 'user_voice_language_code';
  static const String _prefSetupDoneKey = 'language_setup_completed_v1';

  static const List<AppLanguage> supportedLanguages = [
    AppLanguage(
      code: 'ml',
      speechLocale: 'ml_IN',
      nativeName: 'മലയാളം',
      englishName: 'Malayalam',
      mlKitLanguage: null, // Malayalam uses on-device dictionary + Google Translate online
    ),
    AppLanguage(
      code: 'ta',
      speechLocale: 'ta_IN',
      nativeName: 'தமிழ்',
      englishName: 'Tamil',
      mlKitLanguage: TranslateLanguage.tamil,
    ),
    AppLanguage(
      code: 'hi',
      speechLocale: 'hi_IN',
      nativeName: 'हिन्दी',
      englishName: 'Hindi',
      mlKitLanguage: TranslateLanguage.hindi,
    ),
    AppLanguage(
      code: 'kn',
      speechLocale: 'kn_IN',
      nativeName: 'ಕನ್ನಡ',
      englishName: 'Kannada',
      mlKitLanguage: TranslateLanguage.kannada,
    ),
    AppLanguage(
      code: 'te',
      speechLocale: 'te_IN',
      nativeName: 'తెలుగు',
      englishName: 'Telugu',
      mlKitLanguage: TranslateLanguage.telugu,
    ),
    AppLanguage(
      code: 'ar',
      speechLocale: 'ar_SA',
      nativeName: 'العربية',
      englishName: 'Arabic',
      mlKitLanguage: TranslateLanguage.arabic,
    ),
    AppLanguage(
      code: 'en',
      speechLocale: 'en_IN',
      nativeName: 'English',
      englishName: 'English',
      mlKitLanguage: TranslateLanguage.english,
    ),
  ];

  final OnDeviceTranslatorModelManager _modelManager = OnDeviceTranslatorModelManager();

  /// Gets currently selected language (default Malayalam)
  Future<AppLanguage> getSelectedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString(_prefLangKey) ?? 'ml';
    return supportedLanguages.firstWhere(
      (l) => l.code == savedCode,
      orElse: () => supportedLanguages.first,
    );
  }

  /// Checks if language setup should be shown to user:
  /// true IF:
  /// a) First time opening app (no setup flag or no saved language), OR
  /// b) Previously downloaded language model was deleted or is missing from device storage.
  Future<bool> shouldShowLanguageSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final bool setupDone = prefs.getBool(_prefSetupDoneKey) ?? false;
    final String? savedCode = prefs.getString(_prefLangKey);

    if (!setupDone || savedCode == null) {
      debugPrint('[LANG_CHECK] First-time onboarding required (no language saved).');
      return true;
    }

    final lang = supportedLanguages.firstWhere(
      (l) => l.code == savedCode,
      orElse: () => supportedLanguages.first,
    );

    // If language has an ML Kit model, check if model is physically downloaded on storage
    if (lang.mlKitLanguage != null && lang.code != 'en') {
      try {
        final isDownloaded = await _modelManager.isModelDownloaded(lang.mlKitLanguage!.bcpCode);
        debugPrint('[LANG_CHECK] Language ${lang.englishName} model physically on storage: $isDownloaded');
        if (!isDownloaded) {
          debugPrint('[LANG_CHECK] Language model was deleted/missing. Prompting setup.');
          return true;
        }
      } catch (e) {
        debugPrint('[LANG_CHECK] Model check error: $e');
      }
    }

    debugPrint('[LANG_CHECK] Language setup verified (${lang.englishName}).');
    return false;
  }

  /// Downloads language pack / verifies readiness and saves user selection
  Future<bool> setupLanguage(AppLanguage language, {Function(double progress)? onProgress}) async {
    debugPrint('[LANG_CHECK] Initializing language pack for ${language.displayName}...');

    try {
      if (language.mlKitLanguage != null && language.code != 'en') {
        final bcp = language.mlKitLanguage!.bcpCode;
        final alreadyDownloaded = await _modelManager.isModelDownloaded(bcp);
        if (!alreadyDownloaded) {
          debugPrint('[LANG_CHECK] Downloading ML Kit model for $bcp...');
          await _modelManager.downloadModel(bcp);
          debugPrint('[LANG_CHECK] Download complete for $bcp.');
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLangKey, language.code);
      await prefs.setBool(_prefSetupDoneKey, true);
      debugPrint('[LANG_CHECK] Language successfully configured: ${language.code}');
      return true;
    } catch (e) {
      debugPrint('[LANG_CHECK] Error downloading/setting up language: $e');
      // Still persist choice so app doesn't get blocked
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLangKey, language.code);
      await prefs.setBool(_prefSetupDoneKey, true);
      return false;
    }
  }
}

