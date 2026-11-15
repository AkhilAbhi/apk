class LoanItem {
  final String id;
  final String personName;
  final double amount;
  final String type; // 'GIVEN' (Loan Given) or 'TAKEN' (Loan Taken)
  final String date; // YYYY-MM-DD
  final String? dueDate;
  final bool isSettled;
  final String? note;
  final int createdAt;

  LoanItem({
    required this.id,
    required this.personName,
    required this.amount,
    required this.type,
    required this.date,
    this.dueDate,
    this.isSettled = false,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'person_name': personName,
      'amount': amount,
      'type': type,
      'date': date,
      'due_date': dueDate,
      'is_settled': isSettled ? 1 : 0,
      'note': note,
      'created_at': createdAt,
    };
  }

  factory LoanItem.fromMap(Map<String, dynamic> map) {
    return LoanItem(
      id: map['id'] as String,
      personName: map['person_name'] as String,
      amount: (map['amount'] as num).toDouble(),
      type: map['type'] as String,
      date: map['date'] as String,
      dueDate: map['due_date'] as String?,
      isSettled: (map['is_settled'] as int?) == 1,
      note: map['note'] as String?,
      createdAt: (map['created_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

