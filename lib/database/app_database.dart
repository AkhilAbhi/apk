import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction_model.dart';
import '../models/loan_model.dart';
import '../models/shared_word_model.dart';
import '../models/category_keyword_model.dart';
import '../data/default_word_list.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;

  AppDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('ai_money_manager.db');
    return _database!;
  }

  /// Strict pure alphabetical English words regex: NEVER match digits, numbers, or symbols
  static final RegExp englishWordRegex = RegExp(r'^[a-z]+$');

  /// Strict pre-save validator:
  /// - Minimum 2 characters
  /// - No numbers/digits allowed (blocks '1000', '500', '20kg')
  /// - Pure alphabetical English [a-z]+
  static bool isValidKeyword(String word) {
    final clean = word.trim().toLowerCase();
    if (clean.length < 2) return false;
    if (RegExp(r'\d').hasMatch(clean)) return false;
    if (double.tryParse(clean) != null) return false;
    return englishWordRegex.hasMatch(clean);
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 4) {
          try {
            // Forcefully drop old single-word tables
            await db.execute('DROP TABLE IF EXISTS word_list');
            await db.execute('DROP TABLE IF EXISTS shared_word_list');
            await db.execute('DROP TABLE IF EXISTS category_keywords');
            await db.execute('''
              CREATE TABLE category_keywords (
                category TEXT PRIMARY KEY,
                keywords TEXT,
                last_updated INTEGER
              )
            ''');
            final batch = db.batch();
            for (final cat in DefaultWordList.initialCategoryKeywords) {
              batch.insert(
                'category_keywords',
                cat.toMap(),
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
            await batch.commit(noResult: true);
            debugPrint('[DATABASE] Migrated to v4: Rebuilt category_keywords with Category -> Array schema');
          } catch (_) {}
        }
      },
      onOpen: (db) async {
        // Ensure old single-word tables are permanently dropped
        try {
          await db.execute('DROP TABLE IF EXISTS word_list');
          await db.execute('DROP TABLE IF EXISTS shared_word_list');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS category_keywords (
              category TEXT PRIMARY KEY,
              keywords TEXT,
              last_updated INTEGER
            )
          ''');

          // Seed default category keywords if empty
          final countRes = await db.rawQuery('SELECT COUNT(*) as cnt FROM category_keywords');
          final cnt = Sqflite.firstIntValue(countRes) ?? 0;
          if (cnt == 0) {
            final batch = db.batch();
            for (final cat in DefaultWordList.initialCategoryKeywords) {
              batch.insert(
                'category_keywords',
                cat.toMap(),
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
            await batch.commit(noResult: true);
            debugPrint('[DATABASE] Force seeded category_keywords with default category arrays');
          }

          await db.execute('''
            CREATE TABLE IF NOT EXISTS keyword_intent_map (
              intent_key TEXT PRIMARY KEY,
              ml_keywords TEXT NOT NULL,
              en_keywords TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS user_corrections (
              id TEXT PRIMARY KEY,
              original_text TEXT NOT NULL,
              corrected_intent TEXT NOT NULL,
              corrected_category TEXT NOT NULL,
              corrected_type TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');
        } catch (e) {
          debugPrint('[DATABASE_INIT_NOTE] $e');
        }
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Transactions Table
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        category TEXT NOT NULL,
        description TEXT NOT NULL,
        date TEXT NOT NULL,
        time TEXT NOT NULL,
        payment_mode TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    // 2. Loans Table
    await db.execute('''
      CREATE TABLE loans (
        id TEXT PRIMARY KEY,
        person_name TEXT NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        date TEXT NOT NULL,
        due_date TEXT,
        is_settled INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    // 3. Category Keywords Table (Category -> Array)
    await db.execute('''
      CREATE TABLE category_keywords (
        category TEXT PRIMARY KEY,
        keywords TEXT,
        last_updated INTEGER
      )
    ''');

    // 4. User Category Overrides Table
    await db.execute('''
      CREATE TABLE user_category_overrides (
        word TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 5. Local Meta Table (stores version and last_updated)
    await db.execute('''
      CREATE TABLE local_meta (
        key TEXT PRIMARY KEY,
        value_int INTEGER,
        value_text TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS keyword_intent_map (
        intent_key TEXT PRIMARY KEY,
        ml_keywords TEXT NOT NULL,
        en_keywords TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_corrections (
        keyword TEXT NOT NULL,
        corrected_intent TEXT NOT NULL,
        corrected_category TEXT NOT NULL,
        correction_count INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (keyword, corrected_intent)
      )
    ''');

    // Indexes
    await db.execute('CREATE INDEX idx_tx_date ON transactions(date)');
    await db.execute('CREATE INDEX idx_tx_category ON transactions(category)');
  }

  // --- Transactions DAO ---
  Future<int> insertTransaction(TransactionItem item) async {
    final db = await database;
    return await db.insert(
      'transactions',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<TransactionItem>> getAllTransactions({String? limitDate}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      orderBy: 'date DESC, time DESC, created_at DESC',
    );
    return maps.map((e) => TransactionItem.fromMap(e)).toList();
  }

  Future<List<TransactionItem>> getRecentTransactions({int limit = 20}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      orderBy: 'date DESC, time DESC, created_at DESC',
      limit: limit,
    );
    return maps.map((e) => TransactionItem.fromMap(e)).toList();
  }

  Future<int> deleteTransaction(String id) async {
    final db = await database;
    return await db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Extracts person name from loan transaction descriptions like "Loan given (Rahul)" or "Loan repaid by Rahul"
  static String? extractPersonFromLoanDescription(String desc) {
    final parenMatch = RegExp(r'\(([^)]+)\)').firstMatch(desc);
    if (parenMatch != null) return parenMatch.group(1)?.trim();

    final byMatch = RegExp(r'repaid by\s+(.+)', caseSensitive: false).firstMatch(desc);
    if (byMatch != null) return byMatch.group(1)?.trim();

    final toMatch = RegExp(r'repaid to\s+(.+)', caseSensitive: false).firstMatch(desc);
    if (toMatch != null) return toMatch.group(1)?.trim();

    return null;
  }

  /// Deletes a transaction and performs cascading removal or repayment reversal on the active loans table.
  Future<int> deleteTransactionWithCascade(TransactionItem item) async {
    final db = await database;
    final descLower = item.description.toLowerCase().trim();
    final isLoan = item.category == 'Loans' || descLower.contains('loan');

    if (isLoan) {
      debugPrint('[LOAN_CASCADE] Processing loan cascade for deleted transaction: "${item.description}" (₹${item.amount})');

      // 1. Direct ID match: check if a loan with the exact same ID exists
      final directMatches = await db.query('loans', where: 'id = ?', whereArgs: [item.id]);
      if (directMatches.isNotEmpty) {
        await db.delete('loans', where: 'id = ?', whereArgs: [item.id]);
        debugPrint('[LOAN_CASCADE] Direct loan match ${item.id} removed from loans table');
      } else {
        // 2. Cascade based on loan sub-intent
        final person = extractPersonFromLoanDescription(item.description);

        if (descLower.contains('repaid by') || (descLower.contains('repaid') && item.type == 'INCOME')) {
          // Repayment to me deleted -> Reverse repayment back to GIVEN loan
          await _reverseLoanRepayment(
            loanType: 'GIVEN',
            personName: person,
            repaymentAmount: item.amount,
          );
        } else if (descLower.contains('repaid to') || (descLower.contains('repaid') && item.type == 'EXPENSE')) {
          // Repayment by me deleted -> Reverse repayment back to TAKEN loan
          await _reverseLoanRepayment(
            loanType: 'TAKEN',
            personName: person,
            repaymentAmount: item.amount,
          );
        } else if (descLower.contains('loan given') || (item.type == 'EXPENSE' && !descLower.contains('repaid'))) {
          // Loan given deleted -> Completely remove active loan entry
          await _removeMatchingLoan(
            loanType: 'GIVEN',
            personName: person,
            amount: item.amount,
            date: item.date,
          );
        } else if (descLower.contains('loan taken') || (item.type == 'INCOME' && !descLower.contains('repaid'))) {
          // Loan taken deleted -> Completely remove active loan entry
          await _removeMatchingLoan(
            loanType: 'TAKEN',
            personName: person,
            amount: item.amount,
            date: item.date,
          );
        }
      }
    }

    final rows = await db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [item.id],
    );
    debugPrint('[DELETE] Transaction ${item.id} deleted from SQLite');
    return rows;
  }

  Future<void> _removeMatchingLoan({
    required String loanType,
    String? personName,
    required double amount,
    required String date,
  }) async {
    final db = await database;
    final allLoans = await getLoans();
    final candidateLoans = allLoans.where((l) => l.type == loanType).toList();

    LoanItem? target;

    // A. Match by person name and amount
    if (personName != null && personName.isNotEmpty && personName.toLowerCase() != 'someone') {
      final matches = candidateLoans.where(
        (l) => l.personName.toLowerCase().contains(personName.toLowerCase()) &&
            (l.amount - amount).abs() < 0.01,
      );
      if (matches.isNotEmpty) target = matches.first;
    }

    // B. Match by amount and date
    if (target == null) {
      final matches = candidateLoans.where(
        (l) => (l.amount - amount).abs() < 0.01 && l.date == date,
      );
      if (matches.isNotEmpty) target = matches.first;
    }

    // C. Match by amount alone among unsettled loans
    if (target == null) {
      final matches = candidateLoans.where(
        (l) => (l.amount - amount).abs() < 0.01 && !l.isSettled,
      );
      if (matches.isNotEmpty) target = matches.first;
    }

    if (target != null) {
      await db.delete('loans', where: 'id = ?', whereArgs: [target.id]);
      debugPrint('[LOAN_CASCADE] Removed active $loanType loan (id: ${target.id}, person: ${target.personName}, ₹${target.amount})');
    } else {
      debugPrint('[LOAN_CASCADE] Note: No corresponding $loanType loan found to delete for ₹$amount');
    }
  }

  Future<void> _reverseLoanRepayment({
    required String loanType,
    String? personName,
    required double repaymentAmount,
  }) async {
    final db = await database;
    final allLoans = await getLoans();
    final candidateLoans = allLoans.where((l) => l.type == loanType).toList();

    LoanItem? target;

    // A. Try matching by person name
    if (personName != null && personName.isNotEmpty && personName.toLowerCase() != 'someone') {
      final matches = candidateLoans.where(
        (l) => l.personName.toLowerCase().contains(personName.toLowerCase()),
      ).toList();
      if (matches.isNotEmpty) {
        final settled = matches.where((l) => l.isSettled).toList();
        target = settled.isNotEmpty ? settled.first : matches.first;
      }
    }

    // B. Target settled loan or first loan of that type
    target ??= candidateLoans.where((l) => l.isSettled).isNotEmpty
        ? candidateLoans.where((l) => l.isSettled).first
        : (candidateLoans.isNotEmpty ? candidateLoans.first : null);

    if (target != null) {
      final double newAmount = target.isSettled ? repaymentAmount : (target.amount + repaymentAmount);
      await db.update(
        'loans',
        {
          'amount': newAmount,
          'is_settled': 0,
          'note': '${target.note ?? ""} (Repayment of ₹$repaymentAmount reversed)'.trim(),
        },
        where: 'id = ?',
        whereArgs: [target.id],
      );
      debugPrint('[LOAN_CASCADE] Reversed repayment: Reopened loan (${target.personName}) with pending total ₹$newAmount');
    } else {
      // Recreate the active pending loan
      final newLoan = LoanItem(
        id: const Uuid().v4(),
        personName: (personName != null && personName.isNotEmpty) ? personName : 'Someone',
        amount: repaymentAmount,
        type: loanType,
        date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        isSettled: false,
        note: 'Restored from deleted repayment transaction',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await insertLoan(newLoan);
      debugPrint('[LOAN_CASCADE] Recreated pending $loanType loan of ₹$repaymentAmount for ${newLoan.personName}');
    }
  }

  /// Restores a deleted transaction and re-links its loan on UNDO
  Future<void> restoreTransactionWithCascade(TransactionItem item) async {
    await insertTransaction(item);
    final descLower = item.description.toLowerCase().trim();
    final isLoan = item.category == 'Loans' || descLower.contains('loan');

    if (isLoan) {
      final person = extractPersonFromLoanDescription(item.description) ?? 'Someone';
      if (descLower.contains('loan given') || (item.type == 'EXPENSE' && !descLower.contains('repaid'))) {
        await insertLoan(LoanItem(
          id: item.id,
          personName: person,
          amount: item.amount,
          type: 'GIVEN',
          date: item.date,
          isSettled: false,
          createdAt: item.createdAt,
        ));
      } else if (descLower.contains('loan taken') || (item.type == 'INCOME' && !descLower.contains('repaid'))) {
        await insertLoan(LoanItem(
          id: item.id,
          personName: person,
          amount: item.amount,
          type: 'TAKEN',
          date: item.date,
          isSettled: false,
          createdAt: item.createdAt,
        ));
      }
    }
  }

  Future<int> updateTransaction(TransactionItem item) async {
    final db = await database;
    return await db.update(
      'transactions',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<Map<String, double>> getSummaryForMonth(String yearMonth) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT 
        SUM(CASE WHEN type = 'INCOME' THEN amount ELSE 0 END) as total_income,
        SUM(CASE WHEN type = 'EXPENSE' THEN amount ELSE 0 END) as total_expense
      FROM transactions
      WHERE date LIKE '$yearMonth%'
    ''');

    double income = 0.0;
    double expense = 0.0;
    if (result.isNotEmpty) {
      income = (result.first['total_income'] as num?)?.toDouble() ?? 0.0;
      expense = (result.first['total_expense'] as num?)?.toDouble() ?? 0.0;
    }
    return {
      'income': income,
      'expense': expense,
      'balance': income - expense,
    };
  }

  Future<List<Map<String, dynamic>>> getCategoryBreakdown(String yearMonth) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT category, SUM(amount) as total_amount
      FROM transactions
      WHERE type = 'EXPENSE' AND category != 'Loans' AND date LIKE '$yearMonth%'
      GROUP BY category
      ORDER BY total_amount DESC
    ''');
    return result;
  }

  // --- Loans DAO ---
  Future<int> insertLoan(LoanItem loan) async {
    final db = await database;
    return await db.insert(
      'loans',
      loan.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateLoan(LoanItem loan) async {
    final db = await database;
    return await db.update(
      'loans',
      loan.toMap(),
      where: 'id = ?',
      whereArgs: [loan.id],
    );
  }

  Future<List<LoanItem>> getLoans() async {
    final db = await database;
    final maps = await db.query('loans', orderBy: 'date DESC, created_at DESC');
    return maps.map((e) => LoanItem.fromMap(e)).toList();
  }

  Future<int> toggleLoanSettled(String id, bool settled) async {
    final db = await database;
    return await db.update(
      'loans',
      {'is_settled': settled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteLoan(String id) async {
    final db = await database;
    return await db.delete('loans', where: 'id = ?', whereArgs: [id]);
  }

  // --- Wordlist DAO (Category Keywords Arrays) ---
  Future<int> getWordCount() async {
    final db = await database;
    final rows = await db.query('category_keywords');
    final Set<String> uniqueWords = {};
    for (final r in rows) {
      final cat = CategoryKeywords.fromMap(r);
      uniqueWords.addAll(cat.keywords);
    }
    return uniqueWords.length;
  }

  Future<int> getCategoryCount() async {
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) as count FROM category_keywords');
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<List<CategoryKeywords>> getAllCategoryKeywords({String? query}) async {
    final db = await database;
    final rows = await db.query('category_keywords', orderBy: 'category ASC');
    final all = rows.map((e) => CategoryKeywords.fromMap(e)).toList();
    if (query == null || query.trim().isEmpty) {
      return all;
    }
    final q = query.trim().toLowerCase();
    return all.where((cat) {
      final matchCat = cat.category.toLowerCase().contains(q);
      final matchKw = cat.keywords.any((k) => k.toLowerCase().contains(q));
      return matchCat || matchKw;
    }).toList();
  }

  Future<CategoryKeywords?> getCategoryKeywords(String category) async {
    final db = await database;
    final rows = await db.query(
      'category_keywords',
      where: 'category = ?',
      whereArgs: [category.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CategoryKeywords.fromMap(rows.first);
  }

  Future<void> clearAllLocalWords() async {
    final db = await database;
    await db.delete('category_keywords');
    await db.delete('user_category_overrides');
  }

  /// Appends a new keyword to an existing category array in SQLite, or creates category if not found
  Future<void> addKeywordToCategory({
    required String category,
    required String keyword,
    String type = 'expense',
  }) async {
    final cleanKw = keyword.trim().toLowerCase();
    if (!isValidKeyword(cleanKw)) {
      debugPrint('[GUARD] Blocked numeric/invalid keyword: "$cleanKw" from category "$category"');
      return;
    }

    final db = await database;
    final catClean = category.trim();
    final existing = await db.query(
      'category_keywords',
      where: 'category = ?',
      whereArgs: [catClean],
      limit: 1,
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    if (existing.isNotEmpty) {
      final catObj = CategoryKeywords.fromMap(existing.first);
      final keywords = List<String>.from(catObj.keywords);
      if (!keywords.contains(cleanKw)) {
        keywords.add(cleanKw);
        await db.update(
          'category_keywords',
          {
            'keywords': jsonEncode(keywords),
            'last_updated': now,
          },
          where: 'category = ?',
          whereArgs: [catClean],
        );
        debugPrint('[CATEGORY_KEYWORDS] Appended "$cleanKw" to category "$catClean" (Total: ${keywords.length})');
      }
    } else {
      await db.insert(
        'category_keywords',
        {
          'category': catClean,
          'keywords': jsonEncode([cleanKw]),
          'last_updated': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('[CATEGORY_KEYWORDS] Created category "$catClean" with keyword "$cleanKw"');
    }
  }

  Future<void> addLocalWordOnly(String word, {String category = 'Other', String type = 'expense'}) async {
    await addKeywordToCategory(category: category, keyword: word, type: type);
  }

  Future<void> removeKeywordFromCategory({required String category, required String keyword}) async {
    final cleanKw = keyword.trim().toLowerCase();
    final db = await database;
    final catClean = category.trim();
    final existing = await db.query('category_keywords', where: 'category = ?', whereArgs: [catClean], limit: 1);
    if (existing.isEmpty) return;
    final catObj = CategoryKeywords.fromMap(existing.first);
    final keywords = List<String>.from(catObj.keywords)..remove(cleanKw);
    await db.update(
      'category_keywords',
      {
        'keywords': jsonEncode(keywords),
        'last_updated': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'category = ?',
      whereArgs: [catClean],
    );
  }

  Future<void> clearAndSeedCategoryKeywords(List<CategoryKeywords> categories) async {
    final db = await database;
    await db.delete('category_keywords');
    final batch = db.batch();
    for (final cat in categories) {
      final validKeywords = cat.keywords.where((w) => isValidKeyword(w)).toSet().toList();
      batch.insert(
        'category_keywords',
        {
          'category': cat.category.trim(),
          'keywords': jsonEncode(validKeywords),
          'last_updated': cat.lastUpdated,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> clearAndSeedWords(List<SharedWord> words) async {
    final Map<String, Set<String>> grouped = {};
    for (final w in words) {
      final clean = w.word.trim().toLowerCase();
      if (!isValidKeyword(clean)) continue;
      final cat = w.category.trim();
      grouped.putIfAbsent(cat, () => <String>{}).add(clean);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final categories = grouped.entries.map((e) => CategoryKeywords(
      category: e.key,
      keywords: e.value.toList(),
      lastUpdated: now,
    )).toList();
    await clearAndSeedCategoryKeywords(categories);
  }

  Future<void> upsertWordsBatch(List<SharedWord> words) async {
    for (final w in words) {
      await addKeywordToCategory(category: w.category, keyword: w.word, type: w.type);
    }
  }

  Future<List<SharedWord>> getAllWords({String? query}) async {
    final db = await database;
    final rows = await db.query('category_keywords', orderBy: 'category ASC');
    final List<SharedWord> result = [];
    final q = query?.trim().toLowerCase();

    for (final r in rows) {
      final cat = CategoryKeywords.fromMap(r);
      for (final kw in cat.keywords) {
        if (q != null && q.isNotEmpty) {
          if (!kw.contains(q) && !cat.category.toLowerCase().contains(q)) continue;
        }
        result.add(SharedWord(
          word: kw,
          category: cat.category,
          type: 'expense',
          aliases: [kw],
          updatedAt: cat.lastUpdated,
        ));
      }
    }
    result.sort((a, b) => a.word.compareTo(b.word));
    return result;
  }

  /// Looks up a word in SQLite by checking user overrides and category_keywords arrays
  Future<SharedWord?> findWordInDatabase(String word) async {
    final clean = word.trim().toLowerCase();
    if (!isValidKeyword(clean)) return null;
    final db = await database;

    // 1. Check user category override
    final override = await db.query(
      'user_category_overrides',
      where: 'word = ?',
      whereArgs: [clean],
      limit: 1,
    );
    if (override.isNotEmpty) {
      return SharedWord(
        word: clean,
        category: override.first['category'] as String? ?? 'Other',
        type: 'expense',
        aliases: [clean],
        updatedAt: override.first['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );
    }

    // 2. Search category_keywords JSON arrays
    final rows = await db.query('category_keywords');
    for (final r in rows) {
      final cat = CategoryKeywords.fromMap(r);
      if (cat.keywords.contains(clean)) {
        return SharedWord(
          word: clean,
          category: cat.category,
          type: 'expense',
          aliases: [clean],
          updatedAt: cat.lastUpdated,
        );
      }
    }

    return null;
  }

  /// One-time startup migration: Purges any non-alphabetical or numeric keywords from SQLite
  Future<int> purgeNonEnglishWords() async {
    final db = await database;
    final rows = await db.query('category_keywords');
    int deletedCount = 0;
    for (final r in rows) {
      final cat = CategoryKeywords.fromMap(r);
      final cleanKeywords = cat.keywords.where((w) {
        final valid = isValidKeyword(w);
        if (!valid) deletedCount++;
        return valid;
      }).toSet().toList();

      if (cleanKeywords.length != cat.keywords.length) {
        await db.update(
          'category_keywords',
          {
            'keywords': jsonEncode(cleanKeywords),
            'last_updated': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'category = ?',
          whereArgs: [cat.category],
        );
      }
    }
    try {
      await db.execute("UPDATE keyword_intent_map SET ml_keywords = '[]'");
    } catch (_) {}
    if (deletedCount > 0) {
      debugPrint('[MIGRATION] Purged $deletedCount numeric/invalid keywords from category_keywords');
    }
    return deletedCount;
  }

  /// Records user correction in SQLite for self-learning
  Future<int> recordUserCorrection({
    required String keyword,
    required String correctedIntent,
    required String correctedCategory,
  }) async {
    final clean = keyword.trim().toLowerCase();
    if (!englishWordRegex.hasMatch(clean)) return 0;
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await db.query(
      'user_corrections',
      where: 'keyword = ? AND corrected_intent = ?',
      whereArgs: [clean, correctedIntent],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final curCount = (existing.first['correction_count'] as num?)?.toInt() ?? 1;
      final newCount = curCount + 1;
      await db.update(
        'user_corrections',
        {
          'corrected_category': correctedCategory,
          'correction_count': newCount,
          'updated_at': now,
        },
        where: 'keyword = ? AND corrected_intent = ?',
        whereArgs: [clean, correctedIntent],
      );
      return newCount;
    } else {
      await db.insert(
        'user_corrections',
        {
          'keyword': clean,
          'corrected_intent': correctedIntent,
          'corrected_category': correctedCategory,
          'correction_count': 1,
          'updated_at': now,
        },
      );
      return 1;
    }
  }

  Future<List<Map<String, dynamic>>> getActiveUserCorrections() async {
    final db = await database;
    return await db.query('user_corrections');
  }

  // --- Local Meta DAO (last_updated & version) ---
  Future<int> getLocalLastUpdated() async {
    final db = await database;
    final res = await db.query('local_meta', where: "key = 'last_updated'", limit: 1);
    if (res.isNotEmpty) {
      return (res.first['value_int'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  Future<int> getLocalVersion() async {
    final db = await database;
    final res = await db.query('local_meta', where: "key = 'version'", limit: 1);
    if (res.isNotEmpty) {
      return (res.first['value_int'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  Future<void> setLocalMeta(int version, int lastUpdated) async {
    final db = await database;
    await db.insert(
      'local_meta',
      {'key': 'version', 'value_int': version},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'local_meta',
      {'key': 'last_updated', 'value_int': lastUpdated},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Automatically matches an item/description to a Category using local SQLite category_keywords!
  Future<String?> matchCategoryForText(String text) async {
    if (text.trim().isEmpty) return null;
    final db = await database;
    final cleaned = text.trim().toLowerCase();

    // 1. Direct user override check
    final override = await db.query(
      'user_category_overrides',
      where: 'word = ?',
      whereArgs: [cleaned],
      limit: 1,
    );
    if (override.isNotEmpty) {
      return override.first['category'] as String?;
    }

    // 2. Search in category_keywords arrays
    final rows = await db.query('category_keywords');
    final tokens = cleaned.split(RegExp(r'[\s,.\-_]+')).where((t) => isValidKeyword(t)).toList();

    for (final r in rows) {
      final cat = CategoryKeywords.fromMap(r);
      // Direct whole-string match
      if (cat.keywords.contains(cleaned)) {
        return cat.category;
      }
      // Token match
      for (final token in tokens) {
        if (cat.keywords.contains(token)) {
          return cat.category;
        }
      }
    }

    return null;
  }
}
