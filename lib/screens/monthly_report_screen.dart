import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/app_database.dart';
import '../models/transaction_model.dart';
import '../services/transaction_notifier.dart';
import '../theme/app_theme.dart';
import 'transaction_row_helper.dart';

class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  DateTime _currentMonth = DateTime.now();
  bool _isLoading = true;
  double _income = 0.0;
  double _expense = 0.0;
  double _lentMonth = 0.0;
  double _repaidMonth = 0.0;
  double _totalToReceive = 0.0;
  double _totalToPay = 0.0;
  List<Map<String, dynamic>> _categories = [];
  Map<String, List<TransactionItem>> _daysMap = {};
  String? _selectedDay;

  @override
  void initState() {
    super.initState();
    _loadMonthData();
    TransactionUpdateNotifier.instance.updates.addListener(_onTransactionUpdated);
  }

  @override
  void dispose() {
    TransactionUpdateNotifier.instance.updates.removeListener(_onTransactionUpdated);
    super.dispose();
  }

  void _onTransactionUpdated() {
    if (mounted) {
      _loadMonthData();
    }
  }

  Future<void> _loadMonthData() async {
    setState(() => _isLoading = true);
    final monthPrefix = DateFormat('yyyy-MM').format(_currentMonth);

    final db = AppDatabase.instance;
    final allTx = await db.getAllTransactions();
    final monthTx = allTx.where((t) => t.date.startsWith(monthPrefix)).toList();

    double inc = 0.0;
    double exp = 0.0;
    final Map<String, double> catMap = {};
    final Map<String, List<TransactionItem>> days = {};

    for (final t in monthTx) {
      if (t.type == 'INCOME') {
        inc += t.amount;
      } else if (t.type == 'EXPENSE') {
        exp += t.amount;
        if (t.category != 'Loans') {
          catMap[t.category] = (catMap[t.category] ?? 0.0) + t.amount;
        }
      }
      days.putIfAbsent(t.date, () => []).add(t);
    }

    final catList = catMap.entries.map((e) => {
      'category': e.key,
      'amount': e.value,
    }).toList();
    catList.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));

    final loans = await db.getLoans();
    double lent = 0.0;
    double repaid = 0.0;
    double toReceive = 0.0;
    double toPay = 0.0;

    for (final l in loans) {
      if (l.type == 'GIVEN') {
        if (!l.isSettled) toReceive += l.amount;
        if (l.date.startsWith(monthPrefix)) lent += l.amount;
      } else if (l.type == 'TAKEN') {
        if (!l.isSettled) toPay += l.amount;
        if (l.date.startsWith(monthPrefix)) repaid += l.amount;
      }
    }

    if (mounted) {
      setState(() {
        _income = inc;
        _expense = exp;
        _lentMonth = lent;
        _repaidMonth = repaid;
        _totalToReceive = toReceive;
        _totalToPay = toPay;
        _categories = catList;
        _daysMap = days;
        _selectedDay = days.keys.isNotEmpty ? days.keys.first : null;
        _isLoading = false;
      });
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + delta, 1);
    });
    _loadMonthData();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat('#,##0.00');
    final monthLabel = DateFormat('MMMM yyyy').format(_currentMonth);
    final balance = _income - _expense;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Report'),
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
                  // Month Selector Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF2E3E56)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, color: AppColors.primaryLight),
                          onPressed: () => _changeMonth(-1),
                        ),
                        Text(
                          monthLabel,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, color: AppColors.primaryLight),
                          onPressed: () => _changeMonth(1),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Month Summary Card
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
                        const Text('Monthly Net Balance', style: TextStyle(color: Color(0xFFC7D2FE), fontSize: 13)),
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
                                  const Text('Total Received', style: TextStyle(color: Colors.white70, fontSize: 11)),
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
                                  const Text('Total Spent', style: TextStyle(color: Colors.white70, fontSize: 11)),
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

                  const SizedBox(height: 16),

                  // Loans Summary Box
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
                            Text('Loans Summary (This Month)', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Lent: ₹${currency.format(_lentMonth)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            Text('Repaid: ₹${currency.format(_repaidMonth)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ],
                        ),
                        const Divider(color: Color(0xFF2E3E56), height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Still to receive: ₹${currency.format(_totalToReceive)}',
                              style: const TextStyle(color: AppColors.incomeGreen, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            if (_totalToPay > 0)
                              Text(
                                'Still to pay: ₹${currency.format(_totalToPay)}',
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

                  // Days of the month list
                  const Text('Days of the Month (Tap day to view)', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_daysMap.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                      alignment: Alignment.center,
                      child: const Text('No transactions recorded in this month', style: TextStyle(color: AppColors.textSecondary)),
                    )
                  else ...[
                    SizedBox(
                      height: 52,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: _daysMap.keys.map((dayStr) {
                          final isSelected = dayStr == _selectedDay;
                          final parsedDate = DateTime.tryParse(dayStr);
                          final dayFormatted = parsedDate != null ? DateFormat('d MMM').format(parsedDate) : dayStr;

                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(dayFormatted),
                              selected: isSelected,
                              onSelected: (_) => setState(() => _selectedDay = dayStr),
                              selectedColor: AppColors.primary,
                              backgroundColor: AppColors.surface,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Transactions for selected day
                    if (_selectedDay != null && _daysMap.containsKey(_selectedDay))
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _daysMap[_selectedDay]!.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, idx) {
                          final tx = _daysMap[_selectedDay]![idx];
                          return TransactionRowHelper.buildTransactionRow(
                            context: context,
                            item: tx,
                          );
                        },
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
