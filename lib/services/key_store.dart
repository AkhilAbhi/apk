class KeyStore {
  static final KeyStore instance = KeyStore._init();
  KeyStore._init();

  static const int _salt = 0x5A;

  // Obfuscated Groq API key bytes
  static const List<int> _groqBytes = [
    61, 41, 49, 5, 29, 14, 13, 59, 24, 29, 46, 52, 34, 2, 52, 109, 28, 46, 9, 2,
    14, 57, 3, 41, 13, 29, 62, 35, 56, 105, 28, 3, 49, 22, 15, 43, 19, 12, 50,
    14, 21, 23, 2, 49, 43, 42, 50, 51, 60, 52, 62, 52, 25, 62, 11, 105
  ];

  // Obfuscated Gemini API key bytes
  static const List<int> _geminiBytes = [
    27, 11, 116, 27, 56, 98, 8, 20, 108, 17, 51, 34, 104, 11, 57, 54, 5, 107, 57,
    21, 20, 51, 29, 22, 9, 34, 21, 110, 14, 107, 52, 46, 48, 54, 42, 119, 50,
    23, 106, 34, 50, 107, 61, 48, 51, 45, 43, 15, 49, 20, 3, 46, 27
  ];

  String _deobfuscate(List<int> bytes) {
    return String.fromCharCodes(bytes.map((b) => b ^ _salt));
  }

  /// Returns the Groq API key deobfuscated at runtime
  String get groqApiKey => _deobfuscate(_groqBytes);

  /// Returns the Gemini API key deobfuscated at runtime
  String get geminiApiKey => _deobfuscate(_geminiBytes);

  /// Returns masked representation for logging (e.g. "gsk_****")
  String maskKey(String key) {
    if (key.length <= 4) return '****';
    return '${key.substring(0, 4)}****';
  }
}

