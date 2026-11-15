import 'dart:convert';

class SharedWord {
  final String word;
  final String category;
  final String type; // 'income' or 'expense'
  final List<String> aliases;
  final int updatedAt;

  SharedWord({
    required this.word,
    required this.category,
    this.type = 'expense',
    required this.aliases,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'word': word.trim().toLowerCase(),
      'category': category.trim(),
      'type': type.trim().toLowerCase(),
      'aliases': jsonEncode(aliases),
      'updated_at': updatedAt,
    };
  }

  factory SharedWord.fromMap(Map<String, dynamic> map) {
    List<String> parsedAliases = [];
    final rawAliases = map['aliases'];
    if (rawAliases is String) {
      try {
        final decoded = jsonDecode(rawAliases);
        if (decoded is List) {
          parsedAliases = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {
        parsedAliases = [rawAliases];
      }
    } else if (rawAliases is List) {
      parsedAliases = rawAliases.map((e) => e.toString()).toList();
    }

    return SharedWord(
      word: (map['word'] as String).toLowerCase(),
      category: map['category'] as String? ?? 'Other',
      type: (map['type'] as String?)?.toLowerCase() ?? 'expense',
      aliases: parsedAliases,
      updatedAt: (map['updated_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
