import 'package:flutter/material.dart';
import '../services/voice_processor_service.dart';
import '../theme/app_theme.dart';

class VoiceConfirmationResult {
  final VoiceDraft draft;
  final bool wasEdited;
  final String? originalIntent;
  final String? originalCategory;

  VoiceConfirmationResult({
    required this.draft,
    required this.wasEdited,
    this.originalIntent,
    this.originalCategory,
  });
}

class VoiceConfirmationModal extends StatefulWidget {
  final VoiceDraft draft;

  const VoiceConfirmationModal({
    super.key,
    required this.draft,
  });

  @override
  State<VoiceConfirmationModal> createState() => _VoiceConfirmationModalState();
}

class _VoiceConfirmationModalState extends State<VoiceConfirmationModal> {
  bool _isEditing = false;

  late final TextEditingController _amountController;
  late final TextEditingController _titleController;
  late final TextEditingController _personController;

  late String _selectedIntent;
  late String _selectedCategory;
  late String _loanSubType; // 'given', 'taken', 'repaid'

  final List<String> _categories = const [
    'Food',
    'Fuel',
    'Travel',
    'Shopping',
    'Medical',
    'Bills',
    'Salary',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _selectedIntent = widget.draft.intent;
    _selectedCategory = widget.draft.category.isNotEmpty ? widget.draft.category : 'Other';

    if (_selectedIntent == 'loan_given') {
      _loanSubType = 'given';
    } else if (_selectedIntent == 'loan_taken') {
      _loanSubType = 'taken';
    } else if (_selectedIntent == 'loan_repaid_to_me' || _selectedIntent == 'loan_repaid_by_me') {
      _loanSubType = 'repaid';
    } else {
      _loanSubType = 'given';
    }

    _amountController = TextEditingController(
      text: widget.draft.amount % 1 == 0
          ? widget.draft.amount.toInt().toString()
          : widget.draft.amount.toString(),
    );
    _amountController.addListener(_onAmountChanged);
    _titleController = TextEditingController(text: widget.draft.title);
    _personController = TextEditingController(text: widget.draft.personName ?? '');
  }

  void _onAmountChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _titleController.dispose();
    _personController.dispose();
    super.dispose();
  }

  String get _topLevelType {
    if (_selectedIntent.startsWith('loan_')) return 'Loan';
    if (_selectedIntent == 'income') return 'Income';
    return 'Expense';
  }

  void _onTopLevelTypeChanged(String type) {
    setState(() {
      if (type == 'Expense') {
        _selectedIntent = 'expense';
      } else if (type == 'Income') {
        _selectedIntent = 'income';
      } else {
        if (_loanSubType == 'given') {
          _selectedIntent = 'loan_given';
        } else if (_loanSubType == 'taken') {
          _selectedIntent = 'loan_taken';
        } else {
          _selectedIntent = 'loan_repaid_to_me';
        }
      }
    });
  }

  void _onLoanSubTypeChanged(String sub) {
    setState(() {
      _loanSubType = sub;
      if (sub == 'given') {
        _selectedIntent = 'loan_given';
      } else if (sub == 'taken') {
        _selectedIntent = 'loan_taken';
      } else {
        _selectedIntent = 'loan_repaid_to_me';
      }
    });
  }

  void _handleSave({required bool wasEdited}) {
    final parsedAmount = double.tryParse(_amountController.text.trim()) ?? widget.draft.amount;
    final finalTitle = _titleController.text.trim().isNotEmpty ? _titleController.text.trim() : widget.draft.title;
    final finalPerson = _personController.text.trim().isNotEmpty ? _personController.text.trim() : widget.draft.personName;

    final updatedDraft = widget.draft.copyWith(
      amount: parsedAmount > 0 ? parsedAmount : widget.draft.amount,
      intent: _selectedIntent,
      category: _topLevelType == 'Loan' ? 'Loans' : _selectedCategory,
      title: finalTitle,
      personName: _topLevelType == 'Loan' ? finalPerson : null,
    );

    Navigator.pop(
      context,
      VoiceConfirmationResult(
        draft: updatedDraft,
        wasEdited: wasEdited,
        originalIntent: widget.draft.intent,
        originalCategory: widget.draft.category,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF12131A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Color(0xFF6C63FF), width: 1.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.record_voice_over_rounded,
                      color: Color(0xFF6C63FF),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Confirm Voice Entry',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context, null),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Spoken Text Display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E3E56), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '"${widget.draft.originalMalayalam}"',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.draft.title,
                      style: const TextStyle(
                        color: AppColors.primaryLight,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Main Summary / Editable Content
              if (!_isEditing) ...[
                _buildSummaryCard(),
              ] else ...[
                _buildEditForm(),
              ],

              const SizedBox(height: 24),

              // Action Buttons
              if (!_isEditing) ...[
                Row(
                  children: [
                    // Delete Button
                    Expanded(
                      flex: 1,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.expenseRed,
                          side: const BorderSide(color: AppColors.expenseRed, width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => Navigator.pop(context, null),
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                        label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Edit Button
                    Expanded(
                      flex: 1,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF818CF8),
                          side: const BorderSide(color: Color(0xFF6C63FF), width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => setState(() => _isEditing = true),
                        icon: const Icon(Icons.edit_rounded, size: 20),
                        label: const Text('Edit', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Save / Confirm Button
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                        ),
                        onPressed: () => _handleSave(wasEdited: false),
                        icon: const Icon(Icons.check_circle_rounded, size: 20),
                        label: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    // Cancel Edit
                    Expanded(
                      flex: 1,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: Color(0xFF334155), width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => setState(() => _isEditing = false),
                        child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Update & Save
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                        ),
                        onPressed: () => _handleSave(wasEdited: true),
                        icon: const Icon(Icons.save_rounded, size: 20),
                        label: const Text('Update & Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final isLoan = _topLevelType == 'Loan';
    final currentAmount = double.tryParse(_amountController.text.trim()) ?? widget.draft.amount;
    final amountFormatted = currentAmount % 1 == 0
        ? currentAmount.toInt().toString()
        : currentAmount.toStringAsFixed(1);

    Color typeColor;
    String typeLabel;
    IconData typeIcon;

    switch (_selectedIntent) {
      case 'loan_given':
        typeColor = AppColors.accentAmber;
        typeLabel = 'Loan Given';
        typeIcon = Icons.arrow_outward_rounded;
        break;
      case 'loan_taken':
        typeColor = const Color(0xFF6C63FF);
        typeLabel = 'Loan Taken';
        typeIcon = Icons.arrow_downward_rounded;
        break;
      case 'loan_repaid_to_me':
      case 'loan_repaid_by_me':
        typeColor = const Color(0xFF06B6D4);
        typeLabel = 'Loan Repaid';
        typeIcon = Icons.published_with_changes_rounded;
        break;
      case 'income':
        typeColor = AppColors.incomeGreen;
        typeLabel = 'Income';
        typeIcon = Icons.arrow_downward_rounded;
        break;
      case 'expense':
      default:
        typeColor = AppColors.expenseRed;
        typeLabel = 'Expense';
        typeIcon = Icons.arrow_upward_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2E3E56), width: 1),
      ),
      child: Column(
        children: [
          // Amount Display
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                '₹',
                style: TextStyle(
                  color: Color(0xFF818CF8),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                amountFormatted,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Badges Row
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              // Type Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: typeColor.withOpacity(0.5), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(typeIcon, color: typeColor, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      typeLabel,
                      style: TextStyle(
                        color: typeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              // Category / Person Badge
              if (isLoan) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_outline_rounded, color: Colors.white70, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        widget.draft.personName != null && widget.draft.personName!.isNotEmpty
                            ? widget.draft.personName!
                            : 'Someone',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.category_outlined, color: Colors.white70, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        _selectedCategory,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Amount Field
        const Text('Amount (₹)', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            prefixText: '₹ ',
            prefixStyle: const TextStyle(color: Color(0xFF818CF8), fontSize: 20, fontWeight: FontWeight.bold),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2E3E56))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5)),
          ),
        ),
        const SizedBox(height: 14),

        // Title Field
        const Text('Title / Description', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: _titleController,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2E3E56))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5)),
          ),
        ),
        const SizedBox(height: 14),

        // Type Segmented Selector
        const Text('Transaction Type', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: ['Expense', 'Income', 'Loan'].map((t) {
            final isSel = _topLevelType == t;
            return Expanded(
              child: GestureDetector(
                onTap: () => _onTopLevelTypeChanged(t),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSel ? const Color(0xFF6C63FF) : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSel ? const Color(0xFF818CF8) : const Color(0xFF2E3E56),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      t,
                      style: TextStyle(
                        color: isSel ? Colors.white : AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),

        // Sub-controls based on Type
        if (_topLevelType == 'Loan') ...[
          const Text('Loan Direction', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildLoanSubChip('Given', 'given'),
              _buildLoanSubChip('Taken', 'taken'),
              _buildLoanSubChip('Repayment', 'repaid'),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Person Name', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _personController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'e.g. Rahul, Mother',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2E3E56))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5)),
            ),
          ),
        ] else ...[
          const Text('Category', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories.map((c) {
              final isSel = _selectedCategory == c;
              return ChoiceChip(
                label: Text(c),
                selected: isSel,
                onSelected: (val) {
                  if (val) setState(() => _selectedCategory = c);
                },
                selectedColor: const Color(0xFF6C63FF),
                backgroundColor: AppColors.surface,
                labelStyle: TextStyle(
                  color: isSel ? Colors.white : AppColors.textSecondary,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: isSel ? const Color(0xFF818CF8) : const Color(0xFF2E3E56)),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildLoanSubChip(String label, String subType) {
    final isSel = _loanSubType == subType;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onLoanSubTypeChanged(subType),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSel ? const Color(0xFF3B82F6).withOpacity(0.25) : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSel ? const Color(0xFF3B82F6) : const Color(0xFF2E3E56),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSel ? const Color(0xFF93C5FD) : AppColors.textSecondary,
                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
