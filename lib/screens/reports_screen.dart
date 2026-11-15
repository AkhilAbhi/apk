import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/app_database.dart';
import '../services/transaction_notifier.dart';
import '../theme/app_theme.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _currentMonth = DateTime.now();
  double _totalIncome = 0.0;
  double _totalExpense = 0.0;
  List<Map<String, dynamic>> _categoryBreakdown = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReportData();
    TransactionUpdateNotifier.instance.updates.addListener(_onTransactionUpdated);
  }

  @override
  void dispose() {
    TransactionUpdateNotifier.instance.updates.removeListener(_onTransactionUpdated);
    super.dispose();
  }

  void _onTransactionUpdated() {
    if (mounted) {
      _loadReportData();
    }
  }

  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);
    final monthStr = DateFormat('yyyy-MM').format(_currentMonth);

    final summary = await AppDatabase.instance.getSummaryForMonth(monthStr);
    final breakdown = await AppDatabase.instance.getCategoryBreakdown(monthStr);

    setState(() {
      _totalIncome = summary['income'] ?? 0.0;
      _totalExpense = summary['expense'] ?? 0.0;
      _categoryBreakdown = breakdown;
      _isLoading = false;
    });
  }

  void _changeMonth(int offset) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + offset, 1);
    });
    _loadReportData();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analysis'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Month Navigator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left, color: AppColors.textPrimary),
                        onPressed: () => _changeMonth(-1),
                      ),
                      Text(
                        DateFormat('MMMM yyyy').format(_currentMonth),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, color: AppColors.textPrimary),
                        onPressed: () => _changeMonth(1),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Overview Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF2E3E56)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _statItem('Income', '₹${currency.format(_totalIncome)}', AppColors.incomeGreen),
                            _statItem('Expense', '₹${currency.format(_totalExpense)}', AppColors.expenseRed),
                            _statItem(
                              'Savings',
                              '₹${currency.format(_totalIncome - _totalExpense)}',
                              (_totalIncome - _totalExpense) >= 0 ? AppColors.incomeGreen : AppColors.expenseRed,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Ratio Bar
                        if (_totalIncome + _totalExpense > 0)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              height: 8,
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: (_totalIncome * 100).toInt().clamp(1, 1000000),
                                    child: Container(color: AppColors.incomeGreen),
                                  ),
                                  Expanded(
                                    flex: (_totalExpense * 100).toInt().clamp(1, 1000000),
                                    child: Container(color: AppColors.expenseRed),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'Category-wise Expenses',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),

                  const SizedBox(height: 12),

                  if (_categoryBreakdown.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      alignment: Alignment.center,
                      child: const Text('No expenses recorded for this month', style: TextStyle(color: AppColors.textSecondary)),
                    )
                  else
                    ..._categoryBreakdown.map((row) {
                      final category = row['category'] as String? ?? 'Other';
                      final amount = (row['total_amount'] as num?)?.toDouble() ?? 0.0;
                      final percent = _totalExpense > 0 ? (amount / _totalExpense) : 0.0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  category,
                                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                Text(
                                  '₹${currency.format(amount)} (${(percent * 100).toStringAsFixed(1)}%)',
                                  style: const TextStyle(color: AppColors.expenseRed, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percent.clamp(0.0, 1.0),
                                backgroundColor: AppColors.surfaceLight,
                                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryLight),
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
