import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/scanner/manual_barcode_sheet.dart';
import 'package:pharmaguide/features/scanner/scanner_screen.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('ScannerLookupOverlay', () {
    testWidgets('renders premium lookup transition copy', (tester) async {
      await tester.pumpWidget(wrap(const ScannerLookupOverlay()));

      expect(find.text('Checking this barcode'), findsOneWidget);
      expect(find.textContaining('on-device product database'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    });
  });

  group('ScannerNotFoundSheet', () {
    testWidgets('renders barcode, guidance, and actions', (tester) async {
      await tester.pumpWidget(
        wrap(
          ScannerNotFoundSheet(
            upc: '0123456789012',
            onTryAgain: () {},
            onSearchByName: () {},
          ),
        ),
      );

      expect(find.text('Product not found'), findsOneWidget);
      expect(find.text('UPC: 0123456789012'), findsOneWidget);
      expect(find.text('Submit Product'), findsOneWidget);
      expect(find.text('Search by name'), findsOneWidget);
      expect(find.text('Scan again'), findsOneWidget);
      expect(find.textContaining('submit the label'), findsOneWidget);
    });
  });

  group('ManualBarcodeSheet', () {
    testWidgets('returns the normalized barcode string', (tester) async {
      String? submitted;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    submitted = await showManualBarcodeSheet(context);
                  },
                  child: const Text('Open manual entry'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open manual entry'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '048107058432');
      await tester.pump();
      await tester.tap(find.text('Find Product'));
      await tester.pumpAndSettle();

      expect(submitted, '048107058432');
    });
  });
}
