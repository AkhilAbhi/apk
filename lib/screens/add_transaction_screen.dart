import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../models/transaction_model.dart';
import '../theme/app_theme.dart';

class AddTransactionScreen extends StatefulWidget {
  final String initialType;
  const AddTransactionScreen({super.key, this.initialType = 'EXPENSE'});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  late String _type;
  String _category = 'Food';
  String _paymentMode = 'UPI';
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  String? _suggestedCategory;

  final List<String> _expenseCategories = [
    'Food', 'Water', 'Petrol', 'Travel', 'Bills',
    'Shopping', 'Healthcare', 'Tools', 'Personal', 'Other'
  ];

  final List<String> _incomeCategories = [
    'Work Income', 'Labour Income', 'Service Income', 'Other Income'
  ];

  final List<String> _paymentModes = ['UPI', 'Cash', 'Card', 'Bank'];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _category = _type == 'INCOME' ? _incomeCategories.first : _expenseCategories.first;
  }

  void _onDescriptionChanged(String text) async {
    if (text.trim().length >= 2) {
      final match = await AppDatabase.instance.matchCategoryForText(text);
      if (match != null && mounted) {
        setState(() {
          _suggestedCategory = match;
          _category = match;
        });
      }
    }
  }

  Future<void> _saveTransaction() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an amount')),
      );
      return;
    }

    final double? amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final timeStr = '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

    final tx = TransactionItem(
      id: const Uuid().v4(),
      amount: amount,
      type: _type,
      category: _category,
      description: _descController.text.trim().isEmpty ? _category : _descController.text.trim(),
      date: dateStr,
      time: timeStr,
      paymentMode: _paymentMode,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await AppDatabase.instance.insertTransaction(tx);

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentCategories = _type == 'INCOME' ? _incomeCategories : _expenseCategories;

    return Scaffold(
      appBar: AppBar(
        title: Text(_type == 'INCOME' ? 'Add Income' : 'Add Expense'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Type Selector (Expense / Income)
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _type = 'EXPENSE';
                          _category = _expenseCategories.first;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _type == 'EXPENSE' ? AppColors.expenseRed : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Expense',
                          style: TextStyle(
                            color: _type == 'EXPENSE' ? Colors.white : AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _type = 'INCOME';
                          _category = _incomeCategories.first;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _type == 'INCOME' ? AppColors.incomeGreen : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Income',
                          style: TextStyle(
                            color: _type == 'INCOME' ? Colors.white : AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Amount Input
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                prefixText: '₹ ',
                prefixStyle: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: _type == 'INCOME' ? AppColors.incomeGreen : AppColors.expenseRed,
                ),
                hintText: '0.00',
                hintStyle: const TextStyle(color: AppColors.surfaceLight),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),

            const SizedBox(height: 20),

            // Description with SQLite word list auto-category
            TextField(
              controller: _descController,
              onChanged: _onDescriptionChanged,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Description / Item',
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                hintText: 'e.g. thakkali, petrol, biryani...',
                hintStyle: const TextStyle(color: AppColors.surfaceLight),
                helperText: _suggestedCategory != null ? 'Auto-detected category: $_suggestedCategory (from SQLite)' : null,
                helperStyle: const TextStyle(color: AppColors.incomeGreen),
                prefixIcon: const Icon(Icons.edit_note, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),

            const SizedBox(height: 20),

            // Category Chips
            const Text('Category', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: currentCategories.map((cat) {
                final isSelected = _category == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _category = cat);
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Payment Mode
            const Text('Payment Mode', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: _paymentModes.map((mode) {
                final isSelected = _paymentMode == mode;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: isSelected ? AppColors.surfaceLight : AppColors.surface,
                        side: BorderSide(color: isSelected ? AppColors.primaryLight : Colors.transparent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => setState(() => _paymentMode = mode),
                      child: Text(
                        mode,
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Date & Time Picker Row
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) setState(() => _selectedDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Text(DateFormat('dd MMM yyyy').format(_selectedDate), style: const TextStyle(color: AppColors.textPrimary)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime,
                      );
                      if (picked != null) setState(() => _selectedTime = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time, size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Text(_selectedTime.format(context), style: const TextStyle(color: AppColors.textPrimary)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Submit Button
            ElevatedButton(
              onPressed: _saveTransaction,
              style: ElevatedButton.styleFrom(
                backgroundColor: _type == 'INCOME' ? AppColors.incomeGreen : AppColors.expenseRed,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                'Save ${_type == 'INCOME' ? 'Income' : 'Expense'}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

