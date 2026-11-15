import '../database/app_database.dart';

class MalayalamOfflineTranslator {
  static final MalayalamOfflineTranslator instance = MalayalamOfflineTranslator._init();
  MalayalamOfflineTranslator._init();

  // Common vocabulary for pure word-by-word meaning translation
  static const Map<String, String> _vocab = {
    // Pronouns & Fillers
    'ഞാൻ': 'I',
    'എനിക്ക്': 'I',
    'നമുക്ക്': 'we',
    'അവൻ': 'he',
    'അവൾ': 'she',
    'ഇന്ന്': 'today',
    'ഇന്നലെ': 'yesterday',
    'നാളെ': 'tomorrow',

    // Currency & Prepositions
    'രൂപ': 'rupees',
    'രൂപയ്ക്ക്': 'rupees',
    'രൂപക്ക്': 'rupees',
    'രൂപയ്ക്കും': 'rupees',
    'രൂപക്കും': 'rupees',
    'rs': 'rupees',
    'inr': 'rupees',
    '₹': 'rupees',
    'ഒരു': 'a',

    // Action verbs (Expense & Income)
    'വാങ്ങി': 'bought',
    'വാങ്ങിച്ചു': 'bought',
    'മേടിച്ചു': 'bought',
    'അടിച്ചു': 'spent',
    'അടിച്ചത്': 'spent',
    'നിറച്ചു': 'spent',
    'കിട്ടി': 'got',
    'ലഭിച്ചു': 'got',
    'വന്നു': 'got',
    'കിട്ടിയത്': 'got',
    'കൊടുത്തു': 'paid',
    'നൽകി': 'paid',
    'അടച്ചു': 'paid',
    'ചിലവായി': 'spent',
    'ചിലവാക്കി': 'spent',
    'ചിലവ്': 'spent',
    'കടം വാങ്ങി': 'borrowed',
    'കടം കൊടുത്തു': 'lent',

    // Common everyday items
    'മാഗി': 'maggi',
    'ചായ': 'tea',
    'കാപ്പി': 'coffee',
    'പെട്രോൾ': 'petrol',
    'ഡീസൽ': 'diesel',
    'പാൽ': 'milk',
    'പാല്': 'milk',
    'അരി': 'rice',
    'പഞ്ചസാര': 'sugar',
    'മുട്ട': 'egg',
    'മീൻ': 'fish',
    'ബീഫ്': 'beef',
    'ചിക്കൻ': 'chicken',
    'പച്ചക്കറി': 'vegetables',
    'തക്കാളി': 'tomato',
    'ഉള്ളി': 'onion',
    'സവാള': 'onion',
    'വാടക': 'rent',
    'ശമ്പളം': 'salary',
    'കൂലി': 'wage',
    'റീചാർജ്': 'recharge',
  };

  // Malayalam number words to digits
  static const Map<String, String> _numberWords = {
    'പൂജ്യം': '0',
    'ഒന്ന്': '1',
    'രണ്ട്': '2',
    'മൂന്ന്': '3',
    'നാല്': '4',
    'അഞ്ച്': '5',
    'ആറ്': '6',
    'ഏഴ്': '7',
    'എട്ട്': '8',
    'ഒൻപത്': '9',
    'പത്ത്': '10',
    'ഇരുപത്': '20',
    'മുപ്പത്': '30',
    'നാൽപ്പത്': '40',
    'അൻപത്': '50',
    'അറുപത്': '60',
    'എഴുപത്': '70',
    'എൺപത്': '80',
    'തൊണ്ണൂറ്': '90',
    'നൂറ്': '100',
    'അഞ്ഞൂറ്': '500',
    'ആയിരം': '1000',
  };

  /// Translates Malayalam text into English word-by-word on-device without internet.
  Future<String> translateMalayalamToEnglish(String malayalamText) async {
    final cleaned = malayalamText.trim();
    if (cleaned.isEmpty) return '';

    final tokens = cleaned.split(RegExp(r'\s+'));
    final List<String> translatedTokens = [];

    String? actionVerb;
    String? amountStr;
    bool hasRupees = false;
    final List<String> itemTokens = [];
    final List<String> subjectTokens = [];

    for (final rawToken in tokens) {
      final token = rawToken.replaceAll(RegExp(r'[.,!?]'), '').trim();
      if (token.isEmpty) continue;

      // 1. Direct number check
      if (RegExp(r'^\d+(\.\d+)?$').hasMatch(token)) {
        amountStr = token;
        continue;
      }

      // 2. Number word check
      if (_numberWords.containsKey(token)) {
        amountStr = _numberWords[token];
        continue;
      }

      // 3. Currency check
      if (token == 'രൂപ' || token == 'രൂപയ്ക്ക്' || token == 'രൂപക്ക്' || token == 'രൂപയ്ക്കും' || token == 'രൂപക്കും' || token == 'rs' || token == 'rupees') {
        hasRupees = true;
        continue;
      }

      // 4. Action verb check
      if (token == 'വാങ്ങി' || token == 'വാങ്ങിച്ചു' || token == 'മേടിച്ചു') {
        actionVerb = 'bought';
        continue;
      }
      if (token == 'കിട്ടി' || token == 'ലഭിച്ചു' || token == 'വന്നു' || token == 'കിട്ടിയത്') {
        actionVerb = 'got';
        continue;
      }
      if (token == 'കൊടുത്തു' || token == 'നൽകി' || token == 'അടച്ചു') {
        actionVerb = 'paid';
        continue;
      }
      if (token == 'ചിലവായി' || token == 'ചിലവാക്കി' || token == 'ചിലവ്') {
        actionVerb = 'spent';
        continue;
      }

      // 5. Subject pronoun check
      if (token == 'ഞാൻ' || token == 'എനിക്ക്') {
        subjectTokens.add('I');
        continue;
      }

      // 6. Check Vocabulary lookup
      if (_vocab.containsKey(token)) {
        itemTokens.add(_vocab[token]!);
        continue;
      }

      // 7. Check local SQLite word list
      final dbMatch = await AppDatabase.instance.findWordInDatabase(token);
      if (dbMatch != null) {
        itemTokens.add(dbMatch.word);
        continue;
      }

      // 8. If already English/ASCII, keep as is
      if (RegExp(r'^[a-zA-Z0-9]+$').hasMatch(token)) {
        itemTokens.add(token.toLowerCase());
        continue;
      }

      // 9. On-device phonetic transliteration (e.g. മാഗി -> maggi)
      final transliterated = _transliterateMalayalam(token);
      itemTokens.add(transliterated);
    }

    // Assemble naturally formatted pure English translation:
    // e.g. "I bought maggi for 20 rupees" or "I got 50 rupees"
    if (subjectTokens.isNotEmpty) {
      translatedTokens.addAll(subjectTokens);
    }

    if (actionVerb != null) {
      translatedTokens.add(actionVerb);
    }

    if (itemTokens.isNotEmpty) {
      translatedTokens.add(itemTokens.join(' '));
    }

    if (amountStr != null) {
      if (actionVerb == 'bought') {
        translatedTokens.add('for');
      }
      translatedTokens.add(amountStr);
      translatedTokens.add('rupees');
    } else if (hasRupees) {
      translatedTokens.add('rupees');
    }

    return translatedTokens.join(' ').trim();
  }

  /// Accurate Malayalam to English phonetic transliterator for unknown words
  static String _transliterateMalayalam(String text) {
    if (text == 'മാഗി' || text == 'മാഗീ') return 'maggi';

    final buffer = StringBuffer();
    final chars = text.runes.toList();

    for (int i = 0; i < chars.length; i++) {
      final ch = String.fromCharCode(chars[i]);

      switch (ch) {
        case 'അ': buffer.write('a'); break;
        case 'ആ': case 'ാ': buffer.write('a'); break;
        case 'ഇ': case 'ി': buffer.write('i'); break;
        case 'ഈ': case 'ീ': buffer.write('ee'); break;
        case 'ഉ': case 'ു': buffer.write('u'); break;
        case 'ഊ': case 'ൂ': buffer.write('oo'); break;
        case 'എ': case 'െ': buffer.write('e'); break;
        case 'ഏ': case 'േ': buffer.write('e'); break;
        case 'ഐ': case 'ൈ': buffer.write('ai'); break;
        case 'ഒ': case 'ൊ': buffer.write('o'); break;
        case 'ഓ': case 'ോ': buffer.write('o'); break;
        case 'ൗ': buffer.write('au'); break;
        case '്': break;
        case 'ക': buffer.write('k'); break;
        case 'ഖ': buffer.write('kh'); break;
        case 'ഗ': buffer.write('g'); break;
        case 'ഘ': buffer.write('gh'); break;
        case 'ങ': buffer.write('ng'); break;
        case 'ച': buffer.write('ch'); break;
        case 'ഛ': buffer.write('chh'); break;
        case 'ജ': buffer.write('j'); break;
        case 'ഞ': buffer.write('nj'); break;
        case 'ട': buffer.write('t'); break;
        case 'ഠ': buffer.write('th'); break;
        case 'ഡ': buffer.write('d'); break;
        case 'ണ': case 'ൺ': buffer.write('n'); break;
        case 'ത': case 'ഥ': buffer.write('th'); break;
        case 'ദ': case 'ധ': buffer.write('d'); break;
        case 'ന': case 'ൻ': buffer.write('n'); break;
        case 'പ': buffer.write('p'); break;
        case 'ഫ': buffer.write('ph'); break;
        case 'ബ': buffer.write('b'); break;
        case 'ഭ': buffer.write('bh'); break;
        case 'മ': buffer.write('m'); break;
        case 'യ': buffer.write('y'); break;
        case 'ര': case 'ർ': buffer.write('r'); break;
        case 'ല': case 'ൽ': buffer.write('l'); break;
        case 'വ': buffer.write('v'); break;
        case 'ശ': case 'ഷ': buffer.write('sh'); break;
        case 'സ': buffer.write('s'); break;
        case 'ഹ': buffer.write('h'); break;
        case 'ള': buffer.write('l'); break;
        case 'ഴ': buffer.write('zh'); break;
        case 'റ': buffer.write('r'); break;
        default:
          if (ch.codeUnitAt(0) < 128) {
            buffer.write(ch);
          }
      }
    }

    final res = buffer.toString().toLowerCase();
    if (res == 'magi') return 'maggi';
    return res;
  }
}
