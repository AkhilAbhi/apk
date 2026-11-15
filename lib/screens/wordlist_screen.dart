import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../models/category_keyword_model.dart';
import '../services/word_list_sync_service.dart';
import '../theme/app_theme.dart';

class WordListScreen extends StatefulWidget {
  const WordListScreen({super.key});

  @override
  State<WordListScreen> createState() => _WordListScreenState();
}

class _WordListScreenState extends State<WordListScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<CategoryKeywords> _categories = [];
  int _totalKeywords = 0;
  bool _isLoading = true;
  bool _isSyncing = false;
  String _syncStatusText = 'Grouped Category Arrays in Phone SQLite';

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories({String? query}) async {
    setState(() => _isLoading = true);
    final categories = await AppDatabase.instance.getAllCategoryKeywords(query: query);
    int total = 0;
    for (final c in categories) {
      total += c.keywords.length;
    }
    setState(() {
      _categories = categories;
      _totalKeywords = total;
      _isLoading = false;
    });
  }

  Future<void> _triggerSync() async {
    setState(() {
      _isSyncing = true;
      _syncStatusText = 'Syncing category arrays from Firestore to SQLite...';
    });

    final result = await WordListSyncService.instance.syncOnStartup(forceRemote: true);

    setState(() {
      _isSyncing = false;
      _syncStatusText = result.message;
    });

    await _loadCategories();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppColors.incomeGreen,
        ),
      );
    }
  }

  Color _getCategoryColor(String category) {
    final lower = category.toLowerCase();
    if (lower == 'ignore') return const Color(0xFF757575);
    if (lower.contains('income') || lower == 'salary') return AppColors.incomeGreen;
    if (lower.contains('loan')) return const Color(0xFFFFB74D);
    if (lower == 'food') return const Color(0xFFFF7043);
    if (lower == 'fuel') return const Color(0xFF29B6F6);
    if (lower == 'bills') return const Color(0xFFAB47BC);
    return AppColors.primaryLight;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Category Keywords (SQL)'),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sync with Firestore',
            onPressed: _isSyncing ? null : _triggerSync,
          ),
        ],
      ),
      body: Column(
        children: [
          // Status Header
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.data_array_rounded, color: AppColors.primaryLight, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_categories.length} Categories ($_totalKeywords Words)',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _syncStatusText,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => _loadCategories(query: val),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search category or word (e.g. food, loan)...',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                        onPressed: () {
                          _searchController.clear();
                          _loadCategories();
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Categories List (ONE Card per Category)
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _categories.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isEmpty
                              ? 'No categories found in SQLite'
                              : 'No matches for "${_searchController.text}"',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _categories.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final cat = _categories[index];
                          final badgeColor = _getCategoryColor(cat.category);

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: badgeColor.withOpacity(0.25),
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title Row: Category Name + Word Count Badge
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: badgeColor.withOpacity(0.18),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: badgeColor.withOpacity(0.4),
                                            ),
                                          ),
                                          child: Text(
                                            cat.category,
                                            style: TextStyle(
                                              color: badgeColor,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceLight,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${cat.keywords.length} words',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Subtitle/Body: The joined array of words
                                Text(
                                  cat.keywords.isEmpty ? '(No words added yet)' : cat.keywords.join(', '),
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                    height: 1.5,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
