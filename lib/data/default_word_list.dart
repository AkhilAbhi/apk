import '../models/category_keyword_model.dart';
import '../models/shared_word_model.dart';

class DefaultWordList {
  static const int baselineTimestamp = 1794667942537;

  /// Pure alphabetical English keywords strictly grouped by Category -> Array
  /// NO numbers, NO digits, NO single characters.
  static const Map<String, List<String>> initialCategoryMap = {
    "Food": [
      "food", "meal", "snack", "tea", "chai", "coffee", "lunch", "dinner",
      "breakfast", "hotel", "restaurant", "biriyani", "snacks", "bakery", "cafe", "juice"
    ],
    "Fuel": [
      "petrol", "fuel", "gas", "diesel"
    ],
    "Salary": [
      "salary", "wage", "wages", "bonus", "stipend", "paycheck"
    ],
    "Bills": [
      "recharge", "bill", "electricity", "wifi", "water", "current", "rent", "broadband"
    ],
    "Travel": [
      "bus", "fare", "travel", "auto", "train", "ticket", "taxi", "cab", "uber", "ola", "toll"
    ],
    "Income": [
      "got", "received", "credited", "income", "profit", "earned", "gift", "cashback", "reward", "interest"
    ],
    "Expense": [
      "gave", "paid", "spent", "bought", "purchased", "expense", "cost", "fee", "loss"
    ],
    "Shopping": [
      "dress", "shirt", "pant", "clothes", "shoes", "bag", "groceries",
      "supermarket", "vegetables", "fruits", "meat", "fish"
    ],
    "Health": [
      "medicine", "hospital", "doctor", "tablet", "pharmacy", "clinic", "medical"
    ],
    "Entertainment": [
      "movie", "cinema", "theatre", "game", "ott", "netflix", "show"
    ],
    "loan_given": [
      "loan", "debt", "lent", "lend", "credit"
    ],
    "loan_taken": [
      "loan", "debt", "borrow", "borrowed", "owe", "owed"
    ],
    "loan_repaid_to_me": [
      "repay", "repaid", "returned", "return", "refund", "back"
    ],
    "loan_repaid_by_me": [
      "repay", "repaid", "returned", "return", "cleared", "settled", "back"
    ],
    "ignore": [
      "even", "just", "only", "also", "too", "very", "really", "actually", "basically",
      "hand", "hands", "pocket", "pockets", "time", "day", "days", "thing", "things",
      "way", "ways", "went", "came", "gone", "rupee", "rupees", "rs", "inr", "buck", "bucks"
    ],
  };

  /// Converts initialCategoryMap to CategoryKeywords model instances
  static List<CategoryKeywords> get initialCategoryKeywords {
    return initialCategoryMap.entries.map((e) {
      return CategoryKeywords(
        category: e.key,
        keywords: List<String>.from(e.value),
        lastUpdated: baselineTimestamp,
      );
    }).toList();
  }

  /// Backward-compatibility adapter: returns flattened list of SharedWord
  static List<SharedWord> get initialWords {
    final List<SharedWord> words = [];
    for (final entry in initialCategoryMap.entries) {
      for (final kw in entry.value) {
        words.add(SharedWord(
          word: kw,
          category: entry.key,
          type: entry.key.contains('income') || entry.key == 'Salary' ? 'income' : 'expense',
          aliases: [kw],
          updatedAt: baselineTimestamp,
        ));
      }
    }
    return words;
  }
}
