import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../database/app_database.dart';
import '../models/transaction_model.dart';
import '../services/app_update_service.dart';
import '../services/language_settings_service.dart';
import '../services/transaction_notifier.dart';
import '../services/voice_processor_service.dart';
import '../theme/app_theme.dart';
import '../widgets/voice_confirmation_modal.dart';
import 'add_transaction_screen.dart';
import 'all_summary_sheet.dart';
import 'language_selection_screen.dart';
import 'loans_screen.dart';
import 'monthly_report_screen.dart';
import 'today_report_screen.dart';
import 'transaction_row_helper.dart';
import 'wordlist_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Today numbers
  double _todayBalance = 0.0;

  // Month numbers
  double _monthBalance = 0.0;

  // All time numbers
  double _allIncome = 0.0;
  double _allExpense = 0.0;
  double _allBalance = 0.0;

  // Loans info
  double _totalToReceive = 0.0;
  double _totalToPay = 0.0;

  List<TransactionItem> _recentTransactions = [];
  int _wordlistCount = 0;
  bool _isLoading = true;

  // Microphone Speech Recognition state
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechInitialized = false;
  bool _isListening = false;
  bool _isProcessing = false;
  int _speechSessionId = 0;
  String _lastProcessedText = '';
  DateTime? _lastProcessedTime;
  String _speechStatus = 'Tap mic to speak (Malayalam)';
  String _lastRecognizedWords = '';

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    TransactionUpdateNotifier.instance.updates.addListener(
      _onTransactionUpdated,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService.instance.checkForUpdate(context: context);
      }
    });
  }

  @override
  void dispose() {
    _speech.stop();
    TransactionUpdateNotifier.instance.updates.removeListener(
      _onTransactionUpdated,
    );
    super.dispose();
  }

  void _onTransactionUpdated() {
    if (mounted) {
      _loadDashboardData();
    }
  }

  Future<void> _loadDashboardData() async {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final monthStr = DateFormat('yyyy-MM').format(now);

    final db = AppDatabase.instance;
    final allTx = await db.getAllTransactions();

    double tInc = 0.0;
    double tExp = 0.0;
    double mInc = 0.0;
    double mExp = 0.0;
    double aInc = 0.0;
    double aExp = 0.0;

    for (final tx in allTx) {
      if (tx.type == 'INCOME') {
        aInc += tx.amount;
        if (tx.date.startsWith(monthStr)) mInc += tx.amount;
        if (tx.date == todayStr) tInc += tx.amount;
      } else if (tx.type == 'EXPENSE') {
        aExp += tx.amount;
        if (tx.date.startsWith(monthStr)) mExp += tx.amount;
        if (tx.date == todayStr) tExp += tx.amount;
      }
    }

    final loans = await db.getLoans();
    double toReceive = 0.0;
    double toPay = 0.0;
    for (final l in loans) {
      if (!l.isSettled) {
        if (l.type == 'GIVEN') {
          toReceive += l.amount;
        } else if (l.type == 'TAKEN') {
          toPay += l.amount;
        }
      }
    }

    final recents = await db.getRecentTransactions(limit: 15);
    final words = await db.getWordCount();

    if (mounted) {
      setState(() {
        _todayBalance = tInc - tExp;

        _monthBalance = mInc - mExp;

        _allIncome = aInc;
        _allExpense = aExp;
        _allBalance = aInc - aExp;

        _totalToReceive = toReceive;
        _totalToPay = toPay;

        _recentTransactions = recents;
        _wordlistCount = words;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleMicListening() async {
    if (_isProcessing) {
      debugPrint('[VOICE] duplicate ignored: processing currently in progress');
      return;
    }

    if (_isListening) {
      await _stopListening();
      return;
    }

    try {
      if (!_speechInitialized) {
        _speechInitialized = await _speech.initialize(
          onStatus: (status) {
            // Only stop if done or notListening; DO NOT call _onSpeechCompleted here!
            if ((status == 'done' || status == 'notListening') &&
                _isListening) {
              _stopListening();
            }
          },
          onError: (error) {
            if (mounted) {
              setState(() {
                _isListening = false;
                _speechStatus = 'Speech error: ${error.errorMsg}';
              });
            }
          },
        );
      }

      if (_speechInitialized) {
        _speechSessionId++;
        final currentSession = _speechSessionId;

        final selectedLang = await LanguageSettingsService.instance
            .getSelectedLanguage();

        setState(() {
          _isListening = true;
          _speechStatus = 'Listening... (${selectedLang.nativeName})';
          _lastRecognizedWords = '';
        });

        await _speech.listen(
          localeId: selectedLang.speechLocale,
          listenFor: const Duration(seconds: 15),
          pauseFor: const Duration(seconds: 3),
          onResult: (result) {
            _lastRecognizedWords = result.recognizedWords;
            if (result.finalResult) {
              debugPrint(
                '[VOICE] final result received (session $currentSession): ${_lastRecognizedWords.trim()}',
              );
              _onSpeechCompleted(session: currentSession);
            }
          },
        );
      } else {
        setState(() {
          _speechStatus = 'Microphone permission or recognition unavailable';
        });
      }
    } catch (e) {
      setState(() {
        _isListening = false;
        _speechStatus = 'Mic error: $e';
      });
    }
  }

  Future<void> _stopListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
    }
  }

  void _onSpeechCompleted({int? session}) async {
    if (_isProcessing) {
      debugPrint('[VOICE] duplicate ignored: already processing');
      return;
    }

    final words = _lastRecognizedWords.trim();
    if (words.isEmpty) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _speechStatus = 'No speech detected. Tap mic to retry';
        });
      }
      return;
    }

    // Safety net: ignore duplicate text within 3 seconds
    final now = DateTime.now();
    if (_lastProcessedText == words &&
        _lastProcessedTime != null &&
        now.difference(_lastProcessedTime!).inSeconds < 3) {
      debugPrint(
        '[VOICE] duplicate ignored: same text within 3 seconds: "$words"',
      );
      return;
    }

    // Stop recognizer before processing
    await _stopListening();

    _isProcessing = true;
    _lastProcessedText = words;
    _lastProcessedTime = now;

    setState(() {
      _speechStatus = 'Processing...';
    });

    try {
      final draft = await VoiceProcessorService.instance.parseSpokenInput(words);
      if (draft == null) {
        if (mounted) {
          setState(() {
            _speechStatus = 'No amount detected in speech';
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _speechStatus = 'Confirming...';
        });

        // Open sleek full-screen modal
        final confirmed = await showModalBottomSheet<VoiceConfirmationResult>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => VoiceConfirmationModal(draft: draft),
        );

        if (confirmed != null) {
          final res = await VoiceProcessorService.instance.saveVoiceDraft(
            confirmed.draft,
            wasEdited: confirmed.wasEdited,
            originalIntent: draft.intent,
            originalCategory: draft.category,
          );

          if (mounted) {
            setState(() {
              _speechStatus = 'Saved: ${res.message}';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${res.message} (${res.type})'),
                backgroundColor: res.type == 'INCOME'
                    ? AppColors.incomeGreen
                    : AppColors.expenseRed,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          debugPrint('[VOICE] Discarded by user without saving');
          if (mounted) {
            setState(() {
              _speechStatus = 'Discarded';
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[VOICE] Error in speech processing: $e');
    } finally {
      _isProcessing = false;
      _loadDashboardData();
    }
  }

  Future<void> _navigateToAdd(String type) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(initialType: type),
      ),
    );
    if (result == true) {
      _loadDashboardData();
    }
  }

  /// Compact currency formatter: ₹1.2K, ₹3.4L, or ₹120
  String _formatCompact(double val) {
    final abs = val.abs();
    final sign = val < 0 ? '-' : '';
    if (abs >= 100000) {
      return '$sign₹${(abs / 100000).toStringAsFixed(1)}L';
    } else if (abs >= 1000) {
      return '$sign₹${(abs / 1000).toStringAsFixed(1)}K';
    } else {
      return '$sign₹${abs.toStringAsFixed(0)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat('#,##0');

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Money Manager'),
        actions: [
          // Persistent Update Available Action (bypasses cooldown when tapped)
          ValueListenableBuilder<AppUpdateInfo?>(
            valueListenable: AppUpdateService.instance.updateInfoNotifier,
            builder: (context, updateInfo, _) {
              if (updateInfo == null) return const SizedBox.shrink();
              final isMajor = updateInfo.isMajor;
              return IconButton(
                icon: Badge(
                  backgroundColor: isMajor ? const Color(0xFFE5212E) : AppColors.accentAmber,
                  smallSize: 8,
                  child: Icon(
                    isMajor ? Icons.warning_rounded : Icons.system_update_rounded,
                    color: isMajor ? const Color(0xFFE5212E) : AppColors.accentAmber,
                    size: 22,
                  ),
                ),
                tooltip: isMajor
                    ? 'Critical update: v${updateInfo.latestVersion}'
                    : 'Update available: v${updateInfo.latestVersion}',
                onPressed: () {
                  AppUpdateService.instance.showUpdateDialog(context, bypassCooldown: true);
                },
              );
            },
          ),
          // Change Language Action
          IconButton(
            icon: const Icon(
              Icons.language_rounded,
              color: AppColors.primaryLight,
              size: 22,
            ),
            tooltip: 'Voice Language',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const LanguageSelectionScreen(isFromSettings: true),
                ),
              ).then((_) => _loadDashboardData());
            },
          ),
          // Wordlist SQLite Sync Status Badge
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WordListScreen()),
              ).then((_) => _loadDashboardData());
            },
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primaryLight.withOpacity(0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.storage,
                    size: 14,
                    color: AppColors.primaryLight,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$_wordlistCount words',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Voice Mic Section (Minimal test/debug interface)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 20,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _isListening
                              ? AppColors.expenseRed
                              : const Color(0xFF2E3E56),
                          width: _isListening ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: _toggleMicListening,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isListening
                                    ? AppColors.expenseRed
                                    : AppColors.primary,
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (_isListening
                                                ? AppColors.expenseRed
                                                : AppColors.primary)
                                            .withOpacity(0.35),
                                    blurRadius: _isListening ? 20 : 10,
                                    spreadRadius: _isListening ? 6 : 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isListening
                                    ? Icons.mic
                                    : Icons.mic_none_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _speechStatus,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _isListening
                                  ? AppColors.expenseRed
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Debug results print directly to laptop terminal',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // 1. PURPLE BALANCE CARD -> TODAY
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF312E81), Color(0xFF1E1B4B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.2),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Tap Today -> Opens Today's Full Report
                          InkWell(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const TodayReportScreen(),
                                ),
                              ).then((_) => _loadDashboardData());
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                22,
                                20,
                                22,
                                14,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Today',
                                        style: TextStyle(
                                          color: Color(0xFFC7D2FE),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        size: 12,
                                        color: Colors.white.withOpacity(0.4),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${_todayBalance >= 0 ? '+' : '-'}₹${currency.format(_todayBalance.abs())}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  // Small loan info line
                                  Text(
                                    'To receive ₹${currency.format(_totalToReceive)}${_totalToPay > 0 ? " • To pay ₹${currency.format(_totalToPay)}" : ""}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          Container(
                            height: 1,
                            color: Colors.white.withOpacity(0.12),
                          ),

                          // Bottom Row: "This Month" (slightly larger) & "All"
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                // Tap This Month -> Opens Monthly Report Page
                                Expanded(
                                  flex: 6,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const MonthlyReportScreen(),
                                        ),
                                      ).then((_) => _loadDashboardData());
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Text(
                                                'This Month',
                                                style: TextStyle(
                                                  color: Color(0xFFC7D2FE),
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(
                                                Icons.arrow_forward_ios,
                                                size: 10,
                                                color: Colors.white.withOpacity(
                                                  0.4,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatCompact(_monthBalance),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'To rec: ₹${currency.format(_totalToReceive)}',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.65,
                                              ),
                                              fontSize: 10,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                Container(
                                  height: 38,
                                  width: 1,
                                  color: Colors.white.withOpacity(0.15),
                                ),

                                // Tap All -> Opens AI Summary Sheet
                                Expanded(
                                  flex: 5,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (_) => AllSummarySheet(
                                          received: _allIncome,
                                          spent: _allExpense,
                                          remaining: _allBalance,
                                          toReceive: _totalToReceive,
                                          toPay: _totalToPay,
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Text(
                                                'All',
                                                style: TextStyle(
                                                  color: Color(0xFFC7D2FE),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(
                                                Icons.auto_awesome,
                                                size: 10,
                                                color: AppColors.primaryLight
                                                    .withOpacity(0.8),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatCompact(_allBalance),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'To rec: ₹${currency.format(_totalToReceive)}',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.65,
                                              ),
                                              fontSize: 10,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 2. QUICK BUTTONS: Expense, Income, Loans (Wordlist removed, share width evenly)
                    Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            title: 'Expense',
                            icon: Icons.remove_circle_outline,
                            color: AppColors.expenseRed,
                            onTap: () => _navigateToAdd('EXPENSE'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _actionButton(
                            title: 'Income',
                            icon: Icons.add_circle_outline,
                            color: AppColors.incomeGreen,
                            onTap: () => _navigateToAdd('INCOME'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _actionButton(
                            title: 'Loans',
                            icon: Icons.people_outline,
                            color: AppColors.loanBlue,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LoansScreen(),
                                ),
                              ).then((_) => _loadDashboardData());
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // 3. RECENT TRANSACTIONS (Grammar fix: "1 item" vs "N items")
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Recent Transactions',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _recentTransactions.length == 1
                              ? '1 item'
                              : '${_recentTransactions.length} items',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Recent Transactions List
                    if (_recentTransactions.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 48,
                              color: AppColors.textSecondary.withOpacity(0.5),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No transactions recorded yet',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _recentTransactions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _recentTransactions[index];
                          return TransactionRowHelper.buildTransactionRow(
                            context: context,
                            item: item,
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _actionButton({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2E3E56)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
