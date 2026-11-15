import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/ai_summary_service.dart';
import '../theme/app_theme.dart';

class AllSummarySheet extends StatefulWidget {
  final double received;
  final double spent;
  final double remaining;
  final double toReceive;
  final double toPay;

  const AllSummarySheet({
    super.key,
    required this.received,
    required this.spent,
    required this.remaining,
    required this.toReceive,
    required this.toPay,
  });

  @override
  State<AllSummarySheet> createState() => _AllSummarySheetState();
}

class _AllSummarySheetState extends State<AllSummarySheet> {
  bool _isLoading = true;
  String _summaryText = '';

  @override
  void initState() {
    super.initState();
    _fetchSummary();
  }

  Future<void> _fetchSummary() async {
    final text = await AiSummaryService.instance.generateFinancialSummaryMl(
      received: widget.received,
      spent: widget.spent,
      remaining: widget.remaining,
      toReceive: widget.toReceive,
      toPay: widget.toPay,
    );

    if (mounted) {
      setState(() {
        _summaryText = text;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat('#,##0');

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
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
          const SizedBox(height: 18),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, color: AppColors.primaryLight, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'All-Time AI Summary',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 4 Small Cards Grid (Received, Spent, Remaining, To receive)
          Row(
            children: [
              Expanded(
                child: _statCard('Received', '₹${currency.format(widget.received)}', AppColors.incomeGreen),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statCard('Spent', '₹${currency.format(widget.spent)}', AppColors.expenseRed),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _statCard('Remaining', '₹${currency.format(widget.remaining)}', AppColors.primaryLight),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statCard('To Receive', '₹${currency.format(widget.toReceive)}', AppColors.loanBlue),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // AI Text Box
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.psychology, size: 18, color: AppColors.primaryLight),
                    SizedBox(width: 8),
                    Text(
                      'AI സാമ്പത്തിക വിലയിരുത്തൽ (Malayalam)',
                      style: TextStyle(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('AI ചിന്തിക്കുന്നു...', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ),
                  )
                else
                  Text(
                    _summaryText,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      height: 1.55,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E3E56)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

