import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../models/loan_model.dart';
import '../models/transaction_model.dart';
import 'ai_intent_service.dart';
import 'ai_router.dart';
import 'keyword_map_service.dart';
import 'sentence_filter_service.dart';
import 'transaction_notifier.dart';
import 'translation_service.dart';

class VoiceDraft {
  final String originalMalayalam;
  final String englishTranslation;
  final double amount;
  final String intent; // 'expense', 'income', 'loan_given', 'loan_taken', 'loan_repaid_to_me', 'loan_repaid_by_me'
  final String category;
  final String title;
  final String? personName;
  final String? itemName;
  final List<String> filteredEnWords;
  final bool wasAiUsed;

  VoiceDraft({
    required this.originalMalayalam,
    required this.englishTranslation,
    required this.amount,
    required this.intent,
    required this.category,
    required this.title,
    this.personName,
    this.itemName,
    required this.filteredEnWords,
    this.wasAiUsed = false,
  });

  VoiceDraft copyWith({
    String? originalMalayalam,
    String? englishTranslation,
    double? amount,
    String? intent,
    String? category,
    String? title,
    String? personName,
    String? itemName,
    List<String>? filteredEnWords,
    bool? wasAiUsed,
  }) {
    return VoiceDraft(
      originalMalayalam: originalMalayalam ?? this.originalMalayalam,
      englishTranslation: englishTranslation ?? this.englishTranslation,
      amount: amount ?? this.amount,
      intent: intent ?? this.intent,
      category: category ?? this.category,
      title: title ?? this.title,
      personName: personName ?? this.personName,
      itemName: itemName ?? this.itemName,
      filteredEnWords: filteredEnWords ?? this.filteredEnWords,
      wasAiUsed: wasAiUsed ?? this.wasAiUsed,
    );
  }
}

class VoiceProcessResult {
  final bool isSaved;
  final double? amount;
  final String? type;
  final String? category;
  final String? description;
  final String message;

  VoiceProcessResult({
    required this.isSaved,
    this.amount,
    this.type,
    this.category,
    this.description,
    required this.message,
  });
}

class VoiceProcessorService {
  static final VoiceProcessorService instance = VoiceProcessorService._init();
  VoiceProcessorService._init();

  /// Extracts the numeric amount directly from the ORIGINAL spoken text using RegExp(r'\d+(\.\d+)?')
  /// BEFORE passing to translation, preventing translation mangling (e.g. 1500 becoming 150).
  static double? _extractAmountFromOriginalText(String spokenText) {
    if (spokenText.trim().isEmpty) return null;

    final sanitized = spokenText.replaceAllMapped(
      RegExp(r'(\d+),(\d+)'),
      (m) => '${m[1]}${m[2]}',
    );

    // 1. Check for numbers near currency indicators in original spoken text
    final currencyPattern = RegExp(
      r'(?:(?:rs\.?|inr|₹)\s*)?(\d+(?:\.\d+)?)(?:\s*(?:rs\.?|inr|₹|rupees?|രൂപ|രൂപക്ക്|രൂപയ്ക്ക്))?',
      caseSensitive: false,
    );

    for (final match in currencyPattern.allMatches(sanitized)) {
      final full = match.group(0)?.toLowerCase() ?? '';
      final digits = match.group(1);
      if (digits != null &&
          (full.contains('₹') ||
              full.contains('rs') ||
              full.contains('രൂപ') ||
              full.contains('rupee') ||
              full.contains('inr'))) {
        final val = double.tryParse(digits);
        if (val != null && val > 0) {
          return val;
        }
      }
    }

    // 2. Direct RegExp(r'\d+(\.\d+)?') across the original spoken text
    final numRegex = RegExp(r'\d+(\.\d+)?');
    for (final match in numRegex.allMatches(sanitized)) {
      final val = double.tryParse(match.group(0)!);
      if (val != null && val > 0) {
        return val;
      }
    }

    return null;
  }

  /// Parses voice input into a structured VoiceDraft (before opening confirmation modal)
  Future<VoiceDraft?> parseSpokenInput(String spokenText) async {
    final cleanInput = spokenText.trim();
    if (cleanInput.isEmpty) return null;

    // Step 1: Input log
    debugPrint('[STEP 1] Voice: $cleanInput');

    // Extract numeric amount directly from the ORIGINAL spoken text BEFORE passing to translation
    final directOriginalAmount = _extractAmountFromOriginalText(cleanInput);
    if (directOriginalAmount != null) {
      debugPrint('[AMOUNT] Extracted directly from ORIGINAL spoken text: $directOriginalAmount');
    }

    // Step 2: Translate to English (offline ML Kit with fallback)
    // ONLY used for intent, category, and keyword analysis
    final englishTranslation = await TranslationService.instance.translateToEnglish(cleanInput);

    // Step 3: Extract amount and filter small joining/ignore words (ALWAYS trust original spoken amount)
    final filtered = await SentenceFilterService.instance.filterSentence(
      malayalamText: cleanInput,
      englishText: englishTranslation,
      overrideAmount: directOriginalAmount,
    );

    final amount = directOriginalAmount ?? filtered.amount;
    if (amount == null || amount <= 0) {
      debugPrint('[AMOUNT] No numeric amount found in original "$cleanInput" or translated "$englishTranslation". Skipping transaction save.');
      return null;
    }
    debugPrint('[AMOUNT] Final trusted amount: $amount (from original text: ${directOriginalAmount != null})');

    // Step 4: Check filtered keywords against keyword map & calculate weighted match scores
    final matchResult = await KeywordMapService.instance.matchSentence(
      filtered,
      englishTranslation: englishTranslation,
    );

    String decidedIntent = matchResult.key;
    String? personName = matchResult.personName;
    String? itemName = matchResult.itemName;
    String category = 'Other';
    String? customTitle;
    bool wasAiUsed = false;

    // Check if item is already known in local SQLite database
    if (itemName == null || itemName.isEmpty) {
      itemName = _detectItemWord(filtered.enWords, decidedIntent);
    }

    String? localCategory;
    if (itemName != null && itemName.isNotEmpty && !SentenceFilterService.defaultEnIgnore.contains(itemName)) {
      final localWord = await AppDatabase.instance.findWordInDatabase(itemName.toLowerCase().trim());
      if (localWord != null) {
        localCategory = localWord.category;
      }
    }

    final bool hasExplicitLoan = KeywordMapService.loanCoreKeywords.any((kw) {
      return RegExp(r'\b' + kw + r'\b', caseSensitive: false).hasMatch(englishTranslation);
    });

    // Determine if AI is needed:
    // AI is called if:
    // 1. Intent match is not confident
    // 2. OR item word is unknown locally
    // 3. OR no explicit loan keyword was present (to block any guessed loan)
    final bool isKnownItem = (itemName == null || itemName.isEmpty || localCategory != null || SentenceFilterService.defaultEnIgnore.contains(itemName));
    final bool needsAi = !matchResult.isConfident || !isKnownItem || (!hasExplicitLoan && decidedIntent.startsWith('loan_'));

    if (!needsAi) {
      // HIGH SCORE (CONFIDENT MATCH): Pick offline with ZERO AI calls!
      category = localCategory ?? (decidedIntent == 'income' ? 'Salary' : (itemName?.toLowerCase() == 'petrol' ? 'Fuel' : 'Other'));
      debugPrint('[DECISION] High score confident match offline: $decidedIntent (score=${matchResult.score}, margin=${matchResult.margin}, category=$category)');
    } else {
      wasAiUsed = true;
      // FIRST TIME / LOW SCORE / UNKNOWN WORD: Send FULL Malayalam sentence to AI (NEVER single words!)
      debugPrint('[DECISION] Unknown word or low score (score=${matchResult.score}, margin=${matchResult.margin}). Sending full sentence to AI...');
      final sortedKeys = matchResult.allScores.keys.toList()
        ..sort((a, b) => matchResult.allScores[b]!.compareTo(matchResult.allScores[a]!));
      final top3 = sortedKeys.take(3).toList();

      final aiResult = await AiIntentService.instance.understandSentence(
        malayalamText: cleanInput,
        englishText: englishTranslation,
        filteredEnWords: filtered.enWords,
        ignoredEnWords: filtered.removedEnWords,
        top3Keys: top3,
      );

      if (aiResult != null) {
        decidedIntent = aiResult.intent;
        personName = aiResult.person ?? personName;
        category = aiResult.category;
        customTitle = aiResult.title;
        debugPrint('[DECISION] AI verified intent: $decidedIntent (category=$category, title="$customTitle", person=$personName)');

        // Smart ignore-list recovery
        if (aiResult.promoteFromIgnore.isNotEmpty) {
          await SentenceFilterService.instance.rescueIgnoredWords(
            words: aiResult.promoteFromIgnore,
            intentKey: decidedIntent,
            category: category,
          );
        }

        // Auto-save new keywords
        if (aiResult.keywordsEn.isNotEmpty) {
          await KeywordMapService.instance.learnKeywords(
            intentKey: decidedIntent,
            newEnKeywords: aiResult.keywordsEn,
          );
        }
      } else {
        category = localCategory ?? 'Other';
        debugPrint('[DECISION] AI unavailable. Using highest weighted score: $decidedIntent');
      }
    }

    final title = (customTitle != null && customTitle.isNotEmpty)
        ? customTitle
        : (itemName != null && itemName.isNotEmpty ? _capitalize(itemName) : _defaultTitleForIntent(decidedIntent, personName));

    return VoiceDraft(
      originalMalayalam: cleanInput,
      englishTranslation: englishTranslation,
      amount: amount,
      intent: decidedIntent,
      category: category,
      title: title,
      personName: personName,
      itemName: itemName,
      filteredEnWords: filtered.enWords,
      wasAiUsed: wasAiUsed,
    );
  }

  /// Saves the confirmed or edited VoiceDraft to SQLite with self-learning
  Future<VoiceProcessResult> saveVoiceDraft(
    VoiceDraft draft, {
    bool wasEdited = false,
    String? originalIntent,
    String? originalCategory,
  }) async {
    final bool intentChanged = originalIntent != null && originalIntent != draft.intent;
    final bool categoryChanged = originalCategory != null && originalCategory != draft.category;

    if (wasEdited && (intentChanged || categoryChanged)) {
      debugPrint('[POPUP_EDIT] User edited from ($originalIntent, $originalCategory) -> (${draft.intent}, ${draft.category})');

      final db = AppDatabase.instance;
      for (final kw in draft.filteredEnWords) {
        final cleanKw = kw.toLowerCase().trim();
        if (cleanKw.isEmpty || !AppDatabase.englishWordRegex.hasMatch(cleanKw)) continue;
        if (SentenceFilterService.defaultEnIgnore.contains(cleanKw)) continue;

        final newCount = await db.recordUserCorrection(
          keyword: cleanKw,
          correctedIntent: draft.intent,
          correctedCategory: draft.category,
        );

        debugPrint('[CORRECTION_COUNT] Keyword "$cleanKw" correction count for ${draft.intent} is now $newCount');

        // Apply temporary override immediately
        KeywordMapService.instance.applyTemporaryOverride(
          keyword: cleanKw,
          intent: draft.intent,
        );

        if (newCount >= 2) {
          // Permanently promote to database and Firestore
          await KeywordMapService.instance.promoteKeywordPermanently(
            keyword: cleanKw,
            correctedIntent: draft.intent,
            oldIntent: originalIntent,
            correctedCategory: draft.category,
          );
          debugPrint('[PROMOTED_TO_DB] "$cleanKw" reached $newCount corrections -> Permanently promoted to ${draft.intent} / ${draft.category} in SQLite & Cloud');
        }
      }
    }

    // Trigger Pre-save AI analysis & dynamic learning in background
    AiRouter.instance.learnPreSaveKeywords(
      englishSentence: draft.englishTranslation,
      confirmedIntent: draft.intent,
      confirmedCategory: draft.category,
    ).catchError((e) {
      debugPrint('[PRE_SAVE_LEARN] Note: $e');
      return <String>[];
    });

    // Step 5: Save Transaction / Loan
    final saveSummary = await _saveByIntent(
      intent: draft.intent,
      amount: draft.amount,
      personName: draft.personName,
      itemName: draft.itemName,
      customTitle: draft.title,
      customCategory: draft.category,
      cleanMalayalam: draft.originalMalayalam,
      englishTranslation: draft.englishTranslation,
    );

    // Refresh UI across all tabs
    TransactionUpdateNotifier.instance.notifyTransactionSaved();

    return saveSummary;
  }

  /// Backward-compatible direct pipeline
  Future<VoiceProcessResult> processSpokenInput(String spokenText) async {
    final draft = await parseSpokenInput(spokenText);
    if (draft == null) {
      return VoiceProcessResult(
        isSaved: false,
        message: 'No amount found in speech',
      );
    }
    return await saveVoiceDraft(draft);
  }

  String? _detectItemWord(List<String> enWords, String intent) {
    const skipActionWords = {
      'me', 'i', 'my', 'you', 'loan', 'gave', 'given', 'lent', 'borrowed',
      'got', 'paid', 'back', 'returned', 'bought', 'spent', 'salary',
      'income', 'expense', 'hit'
    };
    for (final w in enWords) {
      if (!skipActionWords.contains(w) && !SentenceFilterService.defaultEnIgnore.contains(w)) {
        return w;
      }
    }
    return null;
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String _defaultTitleForIntent(String intent, String? personName) {
    final personDisplay = (personName != null && personName.trim().isNotEmpty) ? personName.trim() : 'Someone';
    switch (intent) {
      case 'loan_given':
        return 'Loan Given ($personDisplay)';
      case 'loan_taken':
        return 'Loan Taken ($personDisplay)';
      case 'loan_repaid_to_me':
        return 'Loan Repaid by $personDisplay';
      case 'loan_repaid_by_me':
        return 'Loan Repaid to $personDisplay';
      case 'income':
        return 'Income';
      case 'expense':
      default:
        return 'Expense';
    }
  }

  Future<VoiceProcessResult> _saveByIntent({
    required String intent,
    required double amount,
    String? personName,
    String? itemName,
    String? customTitle,
    required String customCategory,
    required String cleanMalayalam,
    required String englishTranslation,
  }) async {
    final db = AppDatabase.instance;
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm').format(now);
    final txId = const Uuid().v4();

    String resolvedType = 'EXPENSE';
    String resolvedCategory = customCategory != 'Other' ? customCategory : 'Other';
    String description = '';

    final personDisplay = (personName != null && personName.trim().isNotEmpty) ? personName.trim() : 'Someone';

    switch (intent) {
      case 'loan_taken':
        resolvedType = 'INCOME';
        resolvedCategory = 'Loans';
        description = (customTitle != null && customTitle.isNotEmpty && customTitle != 'Expense')
            ? customTitle
            : 'Loan taken ($personDisplay)';
        await db.insertLoan(LoanItem(
          id: txId,
          personName: personDisplay,
          amount: amount,
          type: 'TAKEN',
          date: dateStr,
          isSettled: false,
          note: cleanMalayalam,
          createdAt: now.millisecondsSinceEpoch,
        ));
        break;

      case 'loan_given':
        resolvedType = 'EXPENSE';
        resolvedCategory = 'Loans';
        description = (customTitle != null && customTitle.isNotEmpty && customTitle != 'Expense')
            ? customTitle
            : 'Loan given ($personDisplay)';
        await db.insertLoan(LoanItem(
          id: txId,
          personName: personDisplay,
          amount: amount,
          type: 'GIVEN',
          date: dateStr,
          isSettled: false,
          note: cleanMalayalam,
          createdAt: now.millisecondsSinceEpoch,
        ));
        break;

      case 'loan_repaid_to_me':
        resolvedType = 'INCOME';
        resolvedCategory = 'Loans';
        description = (customTitle != null && customTitle.isNotEmpty && customTitle != 'Expense')
            ? customTitle
            : 'Loan repaid by $personDisplay';
        await _settleMatchingLoan(personName: personName, amount: amount, loanType: 'GIVEN');
        break;

      case 'loan_repaid_by_me':
        resolvedType = 'EXPENSE';
        resolvedCategory = 'Loans';
        description = (customTitle != null && customTitle.isNotEmpty && customTitle != 'Expense')
            ? customTitle
            : 'Loan repaid to $personDisplay';
        await _settleMatchingLoan(personName: personName, amount: amount, loanType: 'TAKEN');
        break;

      case 'income':
        resolvedType = 'INCOME';
        resolvedCategory = customCategory != 'Other' ? customCategory : 'Salary';
        description = (customTitle != null && customTitle.isNotEmpty && customTitle != 'Expense')
            ? customTitle
            : (itemName != null && itemName.isNotEmpty ? _capitalize(itemName) : 'Income');
        break;

      case 'expense':
      default:
        resolvedType = 'EXPENSE';
        resolvedCategory = customCategory != 'Other' ? customCategory : (itemName?.toLowerCase() == 'petrol' ? 'Fuel' : 'Other');
        description = (customTitle != null && customTitle.isNotEmpty)
            ? customTitle
            : (itemName != null && itemName.isNotEmpty ? _capitalize(itemName) : 'Expense');
        break;
    }

    // Safety check: ensure ignore words NEVER become description
    if (SentenceFilterService.defaultEnIgnore.contains(description.toLowerCase().trim())) {
      description = resolvedType == 'INCOME' ? 'Income' : 'Expense';
    }

    final txItem = TransactionItem(
      id: txId,
      amount: amount,
      type: resolvedType,
      category: resolvedCategory,
      description: description,
      date: dateStr,
      time: timeStr,
      paymentMode: 'Cash',
      isSynced: 0,
      createdAt: now.millisecondsSinceEpoch,
    );

    await db.insertTransaction(txItem);
    debugPrint('[SAVE] $intent $amount $description saved (id=$txId)');

    return VoiceProcessResult(
      isSaved: true,
      amount: amount,
      type: resolvedType,
      category: resolvedCategory,
      description: description,
      message: '₹${amount.toStringAsFixed(0)} saved',
    );
  }

  Future<void> _settleMatchingLoan({
    String? personName,
    required double amount,
    required String loanType,
  }) async {
    final db = AppDatabase.instance;
    final loans = await db.getLoans();
    final openLoans = loans.where((l) => l.type == loanType && !l.isSettled).toList();

    LoanItem? target;
    if (personName != null && personName.trim().isNotEmpty) {
      final nameClean = personName.trim().toLowerCase();
      final match = openLoans.where((l) => l.personName.toLowerCase().contains(nameClean));
      if (match.isNotEmpty) target = match.first;
    }
    target ??= openLoans.isNotEmpty ? openLoans.first : null;

    if (target != null) {
      if (amount >= target.amount) {
        await db.toggleLoanSettled(target.id, true);
        debugPrint('[LOAN] Settled loan of ₹${target.amount} for ${target.personName}');
      } else {
        final remaining = target.amount - amount;
        await db.updateLoan(LoanItem(
          id: target.id,
          personName: target.personName,
          amount: remaining,
          type: target.type,
          date: target.date,
          dueDate: target.dueDate,
          isSettled: false,
          note: '${target.note ?? ""} (Partially repaid ₹$amount)',
          createdAt: target.createdAt,
        ));
        debugPrint('[LOAN] Partially repaid ₹$amount. Remaining ₹$remaining for ${target.personName}');
      }
    }
  }
}
