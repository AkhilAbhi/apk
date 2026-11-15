import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../models/loan_model.dart';
import '../services/transaction_notifier.dart';
import '../theme/app_theme.dart';

class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<LoanItem> _loans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadLoans();
    TransactionUpdateNotifier.instance.updates.addListener(_onTransactionSaved);
  }

  @override
  void dispose() {
    TransactionUpdateNotifier.instance.updates.removeListener(_onTransactionSaved);
    _tabController.dispose();
    super.dispose();
  }

  void _onTransactionSaved() {
    if (mounted) {
      _loadLoans();
    }
  }

  Future<void> _loadLoans() async {
    setState(() => _isLoading = true);
    final items = await AppDatabase.instance.getLoans();
    setState(() {
      _loans = items;
      _isLoading = false;
    });
  }

  Future<void> _toggleSettled(LoanItem loan) async {
    await AppDatabase.instance.toggleLoanSettled(loan.id, !loan.isSettled);
    _loadLoans();
  }

  Future<void> _showAddLoanDialog(String type) async {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          type == 'GIVEN' ? 'Loan Given' : 'Loan Taken',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Person Name',
                labelStyle: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                labelStyle: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Notes (Optional)',
                labelStyle: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final amount = double.tryParse(amountCtrl.text.trim());
              if (name.isNotEmpty && amount != null && amount > 0) {
                final newLoan = LoanItem(
                  id: const Uuid().v4(),
                  personName: name,
                  amount: amount,
                  type: type,
                  date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                  note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                  createdAt: DateTime.now().millisecondsSinceEpoch,
                );
                await AppDatabase.instance.insertLoan(newLoan);
                if (ctx.mounted) Navigator.pop(ctx);
                _loadLoans();
              }
            },
            child: const Text('Save Loan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat('#,##0.00');
    final givenLoans = _loans.where((e) => e.type == 'GIVEN').toList();
    final takenLoans = _loans.where((e) => e.type == 'TAKEN').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loans & Debts'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryLight,
          labelColor: AppColors.primaryLight,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: [
            Tab(text: 'Given (${givenLoans.length})'),
            Tab(text: 'Taken (${takenLoans.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildLoanList(givenLoans, currency, 'GIVEN'),
                _buildLoanList(takenLoans, currency, 'TAKEN'),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () => _showAddLoanDialog(_tabController.index == 0 ? 'GIVEN' : 'TAKEN'),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Loan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildLoanList(List<LoanItem> list, NumberFormat currency, String type) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          type == 'GIVEN' ? 'No loans given yet' : 'No loans taken yet',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = list[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: item.isSettled ? AppColors.incomeGreen.withOpacity(0.3) : const Color(0xFF2E3E56),
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: item.isSettled,
                activeColor: AppColors.incomeGreen,
                onChanged: (_) => _toggleSettled(item),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.personName,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        decoration: item.isSettled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.date}${item.note != null ? ' • ${item.note}' : ''}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${currency.format(item.amount)}',
                    style: TextStyle(
                      color: item.isSettled
                          ? AppColors.textSecondary
                          : (type == 'GIVEN' ? AppColors.loanBlue : AppColors.accentAmber),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      decoration: item.isSettled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.isSettled
                          ? AppColors.incomeGreen.withOpacity(0.15)
                          : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.isSettled ? 'Settled' : 'Pending',
                      style: TextStyle(
                        color: item.isSettled ? AppColors.incomeGreen : AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
