import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/scanner/scanner_screen.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  group('ScannerLookupOverlay', () {
    testWidgets('renders premium lookup transition copy', (tester) async {
      await tester.pumpWidget(wrap(const ScannerLookupOverlay()));

      expect(find.text('Checking this barcode'), findsOneWidget);
      expect(
        find.textContaining('on-device product database'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
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

      expect(find.text("We couldn't match this barcode"), findsOneWidget);
      expect(find.text('UPC: 0123456789012'), findsOneWidget);
      expect(find.text('Scan again'), findsOneWidget);
      expect(find.text('Search by name'), findsOneWidget);
      expect(
        find.textContaining('new, reformulated, or private-label products'),
        findsOneWidget,
      );
    });
  });
}
