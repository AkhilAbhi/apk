import 'dart:convert';

class CategoryKeywords {
  final String category;
  final List<String> keywords;
  final int lastUpdated;

  CategoryKeywords({
    required this.category,
    required this.keywords,
    required this.lastUpdated,
  });

  Map<String, dynamic> toMap() {
    return {
      'category': category.trim(),
      'keywords': jsonEncode(keywords),
      'last_updated': lastUpdated,
    };
  }

  factory CategoryKeywords.fromMap(Map<String, dynamic> map) {
    List<String> parsed = [];
    final raw = map['keywords'];
    if (raw is String) {
      try {
        final dec = jsonDecode(raw);
        if (dec is List) {
          parsed = dec
              .map((e) => e.toString().trim().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList();
        }
      } catch (_) {}
    } else if (raw is List) {
      parsed = raw
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
    }

    return CategoryKeywords(
      category: (map['category'] as String?)?.trim() ?? 'Other',
      keywords: parsed,
      lastUpdated: (map['last_updated'] as int?) ??
          (map['updated_at'] as int?) ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}
