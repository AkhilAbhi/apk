class TransactionItem {
  final String id;
  final double amount;
  final String type; // 'EXPENSE', 'INCOME', 'LOAN'
  final String category;
  final String description;
  final String date; // YYYY-MM-DD
  final String time; // HH:mm
  final String paymentMode; // 'Cash', 'UPI', 'Card', 'Bank'
  final int isSynced;
  final int createdAt;

  TransactionItem({
    required this.id,
    required this.amount,
    required this.type,
    required this.category,
    required this.description,
    required this.date,
    required this.time,
    this.paymentMode = 'Cash',
    this.isSynced = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'type': type,
      'category': category,
      'description': description,
      'date': date,
      'time': time,
      'payment_mode': paymentMode,
      'is_synced': isSynced,
      'created_at': createdAt,
    };
  }

  factory TransactionItem.fromMap(Map<String, dynamic> map) {
    return TransactionItem(
      id: map['id'] as String,
      amount: (map['amount'] as num).toDouble(),
      type: map['type'] as String,
      category: map['category'] as String? ?? 'Other',
      description: map['description'] as String? ?? '',
      date: map['date'] as String,
      time: map['time'] as String? ?? '12:00',
      paymentMode: map['payment_mode'] as String? ?? 'Cash',
      isSynced: (map['is_synced'] as int?) ?? 0,
      createdAt: (map['created_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

