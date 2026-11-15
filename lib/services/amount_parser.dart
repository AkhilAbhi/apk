class AmountParser {
  // English number words
  static const Map<String, double> _engUnits = {
    'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
    'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15,
    'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19,
    'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50,
    'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
  };

  static const Map<String, double> _engMultipliers = {
    'hundred': 100,
    'thousand': 1000,
    'lakh': 100000,
    'lac': 100000,
    'lakhs': 100000,
    'crore': 10000000,
    'crores': 10000000,
  };

  // Malayalam number words mapping
  static const Map<String, double> _mlNumbers = {
    'പത്ത്': 10,
    'ഇരുപത്': 20,
    'മുപ്പത്': 30,
    'നാൽപ്പത്': 40,
    'നാല്പത്': 40,
    'അമ്പത്': 50,
    'അറുപത്': 60,
    'എഴുപത്': 70,
    'എൺപത്': 80,
    'തൊണ്ണൂറ്': 90,
    'നൂറ്': 100,
    'നൂറു': 100,
    'ഇരുന്നൂറ്': 200,
    'മുന്നൂറ്': 300,
    'നാനൂറ്': 400,
    'അഞ്ഞൂറ്': 500,
    'അഞ്ഞൂറു': 500,
    'അറുന്നൂറ്': 600,
    'എഴുന്നൂറ്': 700,
    'എണ്ണൂറ്': 800,
    'തൊള്ളായിരം': 900,
    'ആയിരം': 1000,
    'പതിനായിരം': 10000,
    'ലക്ഷം': 100000,
    'കോടി': 10000000,
  };

  /// Parses financial amount from Malayalam and/or translated English text.
  /// Prioritizes original spoken text (Malayalam) first, ensuring translation mangling never overrides numbers.
  static double? parseAmount({required String englishText, required String malayalamText}) {
    final originalCandidates = <_CandidateAmount>[];

    // 1. Scan original spoken text first
    _extractDigits(malayalamText, originalCandidates);
    _extractMalayalamWords(malayalamText, originalCandidates);

    final validOriginal = originalCandidates.where((c) => c.amount > 0).toList();
    if (validOriginal.isNotEmpty) {
      final currencyNext = validOriginal.where((c) => c.isNearCurrency).toList();
      if (currencyNext.isNotEmpty) {
        currencyNext.sort((a, b) => b.amount.compareTo(a.amount));
        return currencyNext.first.amount;
      }
      validOriginal.sort((a, b) => b.amount.compareTo(a.amount));
      return validOriginal.first.amount;
    }

    // 2. Fall back to translated English text only if original text had no amount
    final englishCandidates = <_CandidateAmount>[];
    _extractDigits(englishText, englishCandidates);
    _extractEnglishWords(englishText, englishCandidates);

    final validEnglish = englishCandidates.where((c) => c.amount > 0).toList();
    if (validEnglish.isEmpty) return null;

    final currencyNext = validEnglish.where((c) => c.isNearCurrency).toList();
    if (currencyNext.isNotEmpty) {
      currencyNext.sort((a, b) => b.amount.compareTo(a.amount));
      return currencyNext.first.amount;
    }

    validEnglish.sort((a, b) => b.amount.compareTo(a.amount));
    return validEnglish.first.amount;
  }

  static void _extractDigits(String text, List<_CandidateAmount> list) {
    // Normalize comma-separated numbers (e.g. 1,500 -> 1500)
    final sanitized = text.replaceAllMapped(
      RegExp(r'(\d+),(\d+)'),
      (m) => '${m[1]}${m[2]}',
    );

    // Matches numbers with optional currency prefix or suffix, capturing ALL continuous digits (\d+)
    final regex = RegExp(
      r'(?:(?:rs\.?|inr|₹)\s*)?(\d+(?:\.\d+)?)(?:\s*(?:rs\.?|inr|₹|rupees?|രൂപ|രൂപക്ക്|രൂപയ്ക്ക്))?',
      caseSensitive: false,
    );

    for (final match in regex.allMatches(sanitized)) {
      final rawDigits = match.group(1);
      if (rawDigits != null) {
        final val = double.tryParse(rawDigits);
        if (val != null && val > 0) {
          final fullMatch = match.group(0)?.toLowerCase() ?? '';
          final hasCurrency = fullMatch.contains('rs') ||
              fullMatch.contains('₹') ||
              fullMatch.contains('rupee') ||
              fullMatch.contains('രൂപ');
          list.add(_CandidateAmount(amount: val, isNearCurrency: hasCurrency));
        }
      }
    }
  }

  static void _extractMalayalamWords(String text, List<_CandidateAmount> list) {
    // Check direct mapped words like അഞ്ഞൂറ് (500), ആയിരം (1000)
    for (final entry in _mlNumbers.entries) {
      if (text.contains(entry.key)) {
        // Check multiplier prefix (e.g., രണ്ട് ആയിരം -> 2000, അഞ്ച് ലക്ഷം -> 500000)
        double multiplier = 1;
        if (text.contains('രണ്ട് ${entry.key}')) multiplier = 2;
        if (text.contains('മൂന്ന് ${entry.key}')) multiplier = 3;
        if (text.contains('നാല് ${entry.key}')) multiplier = 4;
        if (text.contains('അഞ്ച് ${entry.key}')) multiplier = 5;
        if (text.contains('പത്ത് ${entry.key}')) multiplier = 10;

        final amount = entry.value * multiplier;
        final hasCurrency = text.contains('രൂപ');
        list.add(_CandidateAmount(amount: amount, isNearCurrency: hasCurrency));
      }
    }
  }

  static void _extractEnglishWords(String text, List<_CandidateAmount> list) {
    final tokens = text.toLowerCase().split(RegExp(r'[\s\-]+'));
    double current = 0;
    double total = 0;
    bool foundAny = false;

    for (final token in tokens) {
      if (_engUnits.containsKey(token)) {
        current += _engUnits[token]!;
        foundAny = true;
      } else if (_engMultipliers.containsKey(token)) {
        final mult = _engMultipliers[token]!;
        if (current == 0) current = 1;
        if (mult >= 1000) {
          total += current * mult;
          current = 0;
        } else {
          current *= mult;
        }
        foundAny = true;
      } else {
        if (foundAny) {
          total += current;
          if (total > 0) {
            list.add(_CandidateAmount(
              amount: total,
              isNearCurrency: text.contains('rupee') || text.contains('rs') || text.contains('₹'),
            ));
          }
          current = 0;
          total = 0;
          foundAny = false;
        }
      }
    }

    if (foundAny) {
      total += current;
      if (total > 0) {
        list.add(_CandidateAmount(
          amount: total,
          isNearCurrency: text.contains('rupee') || text.contains('rs') || text.contains('₹'),
        ));
      }
    }
  }
}

class _CandidateAmount {
  final double amount;
  final bool isNearCurrency;

  _CandidateAmount({required this.amount, required this.isNearCurrency});
}
