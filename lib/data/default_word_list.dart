import '../models/shared_word_model.dart';

class DefaultWordList {
  static const int baselineTimestamp = 1794667942537;

  // Exact 10 basic seed words (100% English-only, with type & category)
  static List<SharedWord> get initialWords => [
    SharedWord(word: "got", type: "income", category: "Income", aliases: ["got", "received", "credited"], updatedAt: baselineTimestamp),
    SharedWord(word: "received", type: "income", category: "Income", aliases: ["received", "got"], updatedAt: baselineTimestamp),
    SharedWord(word: "gave", type: "expense", category: "Expense", aliases: ["gave", "paid"], updatedAt: baselineTimestamp),
    SharedWord(word: "paid", type: "expense", category: "Expense", aliases: ["paid", "spent"], updatedAt: baselineTimestamp),
    SharedWord(word: "spent", type: "expense", category: "Expense", aliases: ["spent", "paid"], updatedAt: baselineTimestamp),
    SharedWord(word: "bought", type: "expense", category: "Expense", aliases: ["bought", "purchased"], updatedAt: baselineTimestamp),
    SharedWord(word: "petrol", type: "expense", category: "Fuel", aliases: ["petrol", "fuel", "gas"], updatedAt: baselineTimestamp),
    SharedWord(word: "food", type: "expense", category: "Food", aliases: ["food", "meal", "snack"], updatedAt: baselineTimestamp),
    SharedWord(word: "salary", type: "income", category: "Salary", aliases: ["salary", "wage", "wages"], updatedAt: baselineTimestamp),
    SharedWord(word: "recharge", type: "expense", category: "Bills", aliases: ["recharge", "bill"], updatedAt: baselineTimestamp),
    SharedWord(word: "bus", type: "expense", category: "Travel", aliases: ["bus", "fare", "travel"], updatedAt: baselineTimestamp),
    SharedWord(word: "tea", type: "expense", category: "Food", aliases: ["tea", "chai", "coffee"], updatedAt: baselineTimestamp),
  ];
}
