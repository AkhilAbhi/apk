import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_money_manager/database/app_database.dart';
import 'package:ai_money_manager/screens/splash_screen.dart';
import 'package:ai_money_manager/services/amount_parser.dart';
import 'package:ai_money_manager/services/app_update_service.dart';

void main() {
  test('Zero-maintenance Storage filename parsing works for major and minor', () {
    final f1 = AppUpdateService.parseUpdateFilename('money_minor_v1.0.2.apk');
    expect(f1, isNotNull);
    expect(f1!.type, UpdateType.minor);
    expect(f1.version, '1.0.2');

    final f2 = AppUpdateService.parseUpdateFilename('money_major_v2.0.0.apk');
    expect(f2, isNotNull);
    expect(f2!.type, UpdateType.major);
    expect(f2.version, '2.0.0');

    final f3 = AppUpdateService.parseUpdateFilename('aimoneymanager_minor_v1.0.10.apk');
    expect(f3, isNotNull);
    expect(f3!.type, UpdateType.minor);
    expect(f3.version, '1.0.10');

    // Invalid filenames should gracefully return null
    expect(AppUpdateService.parseUpdateFilename('invalid_file.txt'), isNull);
    expect(AppUpdateService.parseUpdateFilename('random.apk'), isNull);
    expect(AppUpdateService.parseUpdateFilename('money_unknown_v1.0.0.apk'), isNull);
  });

  test('Semantic versioning comparison works correctly', () {
    expect(AppUpdateService.compareVersions('1.0.10', '1.0.2'), 1);
    expect(AppUpdateService.compareVersions('1.0.2', '1.0.10'), -1);
    expect(AppUpdateService.isNewerVersion('1.0.10', '1.0.2'), true);
    expect(AppUpdateService.isNewerVersion('1.0.2', '1.0.0'), true);
    expect(AppUpdateService.isNewerVersion('1.1.0', '1.0.5'), true);
    expect(AppUpdateService.isNewerVersion('2.0.0', '1.9.9'), true);
    expect(AppUpdateService.isNewerVersion('1.0.0', '1.0.0'), false);
    expect(AppUpdateService.isNewerVersion('1.0.0', '1.0.2'), false);
    expect(AppUpdateService.isNewerVersion('1.0.2+3', '1.0.2+1'), false);
  });

  test('Person name extraction from loan descriptions', () {
    expect(AppDatabase.extractPersonFromLoanDescription('Loan given (Rahul)'), 'Rahul');
    expect(AppDatabase.extractPersonFromLoanDescription('Loan taken (Sneha)'), 'Sneha');
    expect(AppDatabase.extractPersonFromLoanDescription('Loan repaid by John'), 'John');
    expect(AppDatabase.extractPersonFromLoanDescription('Loan repaid to Mary'), 'Mary');
  });
  test('Amount extraction prioritizes original text over mangled translation', () {
    // 1. Spoken text contains 1500, but mangled translation has 150
    final a1 = AmountParser.parseAmount(
      englishText: 'gave 150 rupees',
      malayalamText: '1500 രൂപ കൊടുത്തു',
    );
    expect(a1, 1500.0);

    // 2. Comma separated number 1,500
    final a2 = AmountParser.parseAmount(
      englishText: 'paid 150',
      malayalamText: '1,500 രൂപ',
    );
    expect(a2, 1500.0);

    // 3. Just digits 1500 without currency word
    final a3 = AmountParser.parseAmount(
      englishText: '150',
      malayalamText: '1500',
    );
    expect(a3, 1500.0);

    // 4. Decimal amount
    final a4 = AmountParser.parseAmount(
      englishText: '150.5',
      malayalamText: '1500.50 രൂപ',
    );
    expect(a4, 1500.50);
  });

  testWidgets('Splash Screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AnimatedSplashScreen(),
      ),
    );
    expect(find.text('AI Money Manager'), findsOneWidget);
    expect(find.text('Voice AI • Smart Finances'), findsOneWidget);
  });
}


