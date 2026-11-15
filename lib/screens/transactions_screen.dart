import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../models/transaction_model.dart';
import '../services/transaction_notifier.dart';
import '../theme/app_theme.dart';
import 'transaction_row_helper.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<TransactionItem> _allTransactions = [];
  String _filterType = 'ALL';
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
    TransactionUpdateNotifier.instance.updates.addListener(_onTransactionUpdated);
  }

  @override
  void dispose() {
    TransactionUpdateNotifier.instance.updates.removeListener(_onTransactionUpdated);
    super.dispose();
  }

  void _onTransactionUpdated() {
    if (mounted) {
      _loadTransactions();
    }
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);
    final items = await AppDatabase.instance.getAllTransactions();
    setState(() {
      _allTransactions = items;
      _isLoading = false;
    });
  }

  List<TransactionItem> get _filteredList {
    return _allTransactions.where((item) {
      final matchesType = _filterType == 'ALL' || item.type == _filterType;
      final matchesSearch = _searchQuery.isEmpty ||
          item.description.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.category.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesType && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
      ),
      body: Column(
        children: [
          // Filter Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _filterButton('ALL', 'All'),
                const SizedBox(width: 8),
                _filterButton('EXPENSE', 'Expenses'),
                const SizedBox(width: 8),
                _filterButton('INCOME', 'Income'),
              ],
            ),
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search transactions...',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredList.isEmpty
                    ? const Center(
                        child: Text('No transactions found', style: TextStyle(color: AppColors.textSecondary)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _filteredList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _filteredList[index];
                          return TransactionRowHelper.buildTransactionRow(
                            context: context,
                            item: item,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterButton(String key, String label) {
    final isSelected = _filterType == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filterType = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.textSecondary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

