import 'package:flutter/foundation.dart';

class TransactionUpdateNotifier {
  static final TransactionUpdateNotifier instance = TransactionUpdateNotifier._init();
  TransactionUpdateNotifier._init();

  final ValueNotifier<int> updates = ValueNotifier<int>(0);

  void notifyTransactionSaved() {
    updates.value = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[UI] refreshed');
  }
}

