import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/app_database.dart';
import '../models/transaction_model.dart';
import '../services/transaction_notifier.dart';
import '../theme/app_theme.dart';

class TransactionRowHelper {
  /// Shows Delete confirmation dialog with Cancel / Delete.
  /// On Delete, removes from SQLite, calls TransactionNotifier, and shows snackbar with UNDO.
  static Future<void> confirmDelete({
    required BuildContext context,
    required TransactionItem item,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Transaction', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Delete "${item.description}" (₹${item.amount.toStringAsFixed(0)})?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.expenseRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      await AppDatabase.instance.deleteTransactionWithCascade(item);
      debugPrint('[DELETE] id=${item.id} removed with loan cascade');
      TransactionUpdateNotifier.instance.notifyTransactionSaved();

      messenger.showSnackBar(
        SnackBar(
          content: Text('Deleted ₹${item.amount.toStringAsFixed(0)}'),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: AppColors.primaryLight,
            onPressed: () async {
              await AppDatabase.instance.restoreTransactionWithCascade(item);
              debugPrint('[UNDO] id=${item.id} restored with loan sync');
              TransactionUpdateNotifier.instance.notifyTransactionSaved();
            },
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Opens Edit dialog/bottom-sheet with Amount, Type, Category, Description, and Date.
  static Future<void> showEditDialog({
    required BuildContext context,
    required TransactionItem item,
  }) async {
    final amountCtrl = TextEditingController(text: item.amount.toStringAsFixed(item.amount.truncateToDouble() == item.amount ? 0 : 2));
    final descCtrl = TextEditingController(text: item.description);
    String selectedType = item.type;
    String selectedCategory = item.category;
    String selectedDate = item.date;

    // Fetch existing categories from DB
    List<String> categories = [
      'Food', 'Fuel', 'Travel', 'Bills', 'Shopping', 'Salary', 'Healthcare',
      'Entertainment', 'Investment', 'Personal', 'Education', 'Expense', 'Income', 'Other'
    ];
    try {
      final db = await AppDatabase.instance.database;
      final res = await db.rawQuery('SELECT DISTINCT category FROM shared_word_list WHERE category IS NOT NULL');
      for (final r in res) {
        final c = r['category'] as String?;
        if (c != null && c.trim().isNotEmpty && !categories.contains(c.trim())) {
          categories.add(c.trim());
        }
      }
    } catch (_) {}

    if (!categories.contains(selectedCategory)) {
      categories.insert(0, selectedCategory);
    }

    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Edit Transaction',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.textSecondary),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Type Selector (Expense / Income / Loan)
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('EXPENSE'),
                        selected: selectedType == 'EXPENSE',
                        selectedColor: AppColors.expenseRed,
                        backgroundColor: AppColors.surface,
                        labelStyle: TextStyle(
                          color: selectedType == 'EXPENSE' ? Colors.white : AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (_) => setModalState(() => selectedType = 'EXPENSE'),
                      ),
                      ChoiceChip(
                        label: const Text('INCOME'),
                        selected: selectedType == 'INCOME',
                        selectedColor: AppColors.incomeGreen,
                        backgroundColor: AppColors.surface,
                        labelStyle: TextStyle(
                          color: selectedType == 'INCOME' ? Colors.white : AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (_) => setModalState(() => selectedType = 'INCOME'),
                      ),
                      ChoiceChip(
                        label: const Text('LOAN'),
                        selected: selectedType == 'LOAN',
                        selectedColor: AppColors.loanBlue,
                        backgroundColor: AppColors.surface,
                        labelStyle: TextStyle(
                          color: selectedType == 'LOAN' ? Colors.white : AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (_) => setModalState(() {
                          selectedType = 'LOAN';
                          selectedCategory = 'Loans';
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Amount
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'Amount (₹)',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      prefixText: '₹ ',
                      prefixStyle: TextStyle(color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Category Dropdown
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    dropdownColor: AppColors.surface,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                    ),
                    items: categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedCategory = val);
                    },
                  ),
                  const SizedBox(height: 14),

                  // English item word/description
                  TextField(
                    controller: descCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Item Name / Description',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Date Picker Row
                  InkWell(
                    onTap: () async {
                      final current = DateTime.tryParse(selectedDate) ?? DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: current,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setModalState(() {
                          selectedDate = DateFormat('yyyy-MM-dd').format(picked);
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2E3E56)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Date', style: TextStyle(color: AppColors.textSecondary)),
                          Text(selectedDate, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Save Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      final newAmt = double.tryParse(amountCtrl.text.trim());
                      if (newAmt == null || newAmt <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a valid positive amount')),
                        );
                        return;
                      }

                      final updated = TransactionItem(
                        id: item.id,
                        amount: newAmt,
                        type: selectedType,
                        category: selectedCategory,
                        description: descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : selectedCategory,
                        date: selectedDate,
                        time: item.time,
                        paymentMode: item.paymentMode,
                        isSynced: item.isSynced,
                        createdAt: item.createdAt,
                      );

                      await AppDatabase.instance.updateTransaction(updated);
                      debugPrint('[EDIT] id=${item.id} updated');
                      TransactionUpdateNotifier.instance.notifyTransactionSaved();

                      if (context.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Transaction updated')),
                        );
                      }
                    },
                    child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Builds a transaction card with Edit (pencil) and Delete (trash) action buttons
  static Widget buildTransactionRow({
    required BuildContext context,
    required TransactionItem item,
  }) {
    final currency = NumberFormat('#,##0.00');
    final isIncome = item.type == 'INCOME';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E3E56)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: (isIncome ? AppColors.incomeGreen : AppColors.expenseRed).withOpacity(0.15),
            child: Icon(
              isIncome ? Icons.arrow_downward : Icons.arrow_upward,
              color: isIncome ? AppColors.incomeGreen : AppColors.expenseRed,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.description.isNotEmpty ? item.description : item.category,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.category} • ${item.date}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Amount
          Text(
            '${isIncome ? '+' : '-'}₹${currency.format(item.amount)}',
            style: TextStyle(
              color: isIncome ? AppColors.incomeGreen : AppColors.expenseRed,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 4),
          // Edit Icon
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primaryLight),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            tooltip: 'Edit',
            onPressed: () => showEditDialog(context: context, item: item),
          ),
          const SizedBox(width: 4),
          // Delete Icon
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.expenseRed),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            tooltip: 'Delete',
            onPressed: () => confirmDelete(context: context, item: item),
          ),
        ],
      ),
    );
  }
}
