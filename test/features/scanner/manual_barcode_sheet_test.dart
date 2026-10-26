import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/features/scanner/manual_barcode_sheet.dart';
import 'package:pharmaguide/services/gtin.dart';

void main() {
  for (final raw in ['X036000291452', '036000291452X', 'X002FLZ3X7']) {
    testWidgets('manual paste preserves and rejects $raw', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: V2Theme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showManualBarcodeSheet(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), raw);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        raw,
      );
      expect(find.text(invalidGtinMessage), findsOneWidget);
      expect(
        tester.widget<PGPillButton>(find.byType(PGPillButton)).onPressed,
        isNull,
      );
    });
  }

  testWidgets('formatted numeric GTIN preserves leading zeroes', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: V2Theme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showManualBarcodeSheet(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0 36000 29145 2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find Product'));
    await tester.pumpAndSettle();
    expect(result, '036000291452');
  });
}
