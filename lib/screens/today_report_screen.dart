import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/app_database.dart';
import '../models/transaction_model.dart';
import '../services/transaction_notifier.dart';
import '../theme/app_theme.dart';
import 'transaction_row_helper.dart';

class TodayReportScreen extends StatefulWidget {
  const TodayReportScreen({super.key});

  @override
  State<TodayReportScreen> createState() => _TodayReportScreenState();
}

class _TodayReportScreenState extends State<TodayReportScreen> {
  bool _isLoading = true;
  double _income = 0.0;
  double _expense = 0.0;
  double _lentToday = 0.0;
  double _receivedBackToday = 0.0;
  double _toReceiveTotal = 0.0;
  double _toPayTotal = 0.0;
  List<Map<String, dynamic>> _categories = [];
  List<TransactionItem> _transactions = [];

  @override
  void initState() {
    super.initState();
    _loadTodayData();
    TransactionUpdateNotifier.instance.updates.addListener(_onTransactionUpdated);
  }

  @override
  void dispose() {
    TransactionUpdateNotifier.instance.updates.removeListener(_onTransactionUpdated);
    super.dispose();
  }

  void _onTransactionUpdated() {
    if (mounted) {
      _loadTodayData();
    }
  }

  Future<void> _loadTodayData() async {
    setState(() => _isLoading = true);
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final db = AppDatabase.instance;
    final allTx = await db.getAllTransactions();
    final todayTx = allTx.where((t) => t.date == todayStr).toList();

    double inc = 0.0;
    double exp = 0.0;
    final Map<String, double> catMap = {};

    for (final t in todayTx) {
      if (t.type == 'INCOME') {
        inc += t.amount;
      } else if (t.type == 'EXPENSE') {
        exp += t.amount;
        if (t.category != 'Loans') {
          catMap[t.category] = (catMap[t.category] ?? 0.0) + t.amount;
        }
      }
    }

    final catList = catMap.entries.map((e) => {
      'category': e.key,
      'amount': e.value,
    }).toList();
    catList.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));

    final loans = await db.getLoans();
    double lent = 0.0;
    double receivedBack = 0.0;
    double toReceive = 0.0;
    double toPay = 0.0;

    for (final l in loans) {
      if (l.type == 'GIVEN') {
        if (!l.isSettled) toReceive += l.amount;
        if (l.date == todayStr) lent += l.amount;
      } else if (l.type == 'TAKEN') {
        if (!l.isSettled) toPay += l.amount;
        if (l.date == todayStr) receivedBack += l.amount;
      }
    }

    if (mounted) {
      setState(() {
        _income = inc;
        _expense = exp;
        _lentToday = lent;
        _receivedBackToday = receivedBack;
        _toReceiveTotal = toReceive;
        _toPayTotal = toPay;
        _categories = catList;
        _transactions = todayTx;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat('#,##0.00');
    final todayDisplay = DateFormat('dd MMMM yyyy').format(DateTime.now());
    final balance = _income - _expense;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Report"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    todayDisplay,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Today Summary Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF312E81), Color(0xFF1E1B4B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Today's Net Balance",
                          style: TextStyle(color: Color(0xFFC7D2FE), fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${balance >= 0 ? '+' : '-'}₹${currency.format(balance.abs())}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Received Today', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '+₹${currency.format(_income)}',
                                    style: const TextStyle(color: AppColors.incomeGreen, fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            Container(height: 30, width: 1, color: Colors.white24),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Spent Today', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '-₹${currency.format(_expense)}',
                                    style: const TextStyle(color: AppColors.expenseRed, fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Loan Info Box
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF2E3E56)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.handshake_outlined, size: 18, color: AppColors.loanBlue),
                            SizedBox(width: 8),
                            Text('Loans Summary', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Lent Today: ₹${currency.format(_lentToday)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            Text('Repaid Today: ₹${currency.format(_receivedBackToday)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ],
                        ),
                        const Divider(color: Color(0xFF2E3E56), height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'To receive: ₹${currency.format(_toReceiveTotal)}',
                              style: const TextStyle(color: AppColors.incomeGreen, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            if (_toPayTotal > 0)
                              Text(
                                'To pay: ₹${currency.format(_toPayTotal)}',
                                style: const TextStyle(color: AppColors.expenseRed, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Category Breakdown
                  if (_categories.isNotEmpty) ...[
                    const Text('Category-wise Spending', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF2E3E56)),
                      ),
                      child: Column(
                        children: _categories.map((c) {
                          final amount = c['amount'] as double;
                          final pct = _expense > 0 ? (amount / _expense) : 0.0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(c['category'] as String, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                                    Text('₹${currency.format(amount)} (${(pct * 100).toStringAsFixed(1)}%)', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: pct,
                                    backgroundColor: const Color(0xFF2E3E56),
                                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                                    minHeight: 6,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Today's Transactions
                  Text("Today's Transactions (${_transactions.length})", style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_transactions.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                      alignment: Alignment.center,
                      child: const Text('No transactions recorded today', style: TextStyle(color: AppColors.textSecondary)),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _transactions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, idx) {
                        final tx = _transactions[idx];
                        return TransactionRowHelper.buildTransactionRow(
                          context: context,
                          item: tx,
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}
