import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pharmaguide/core/components/pg_scan_not_found.dart';
import 'package:pharmaguide/core/components/pg_verdict_reveal.dart';
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

  group('scannerCameraPermissionDenied', () {
    test('returns true only for permissionDenied scanner errors', () {
      expect(
        scannerCameraPermissionDenied(
          const MobileScannerState.uninitialized().copyWith(
            error: const MobileScannerException(
              errorCode: MobileScannerErrorCode.permissionDenied,
            ),
          ),
        ),
        isTrue,
      );

      expect(
        scannerCameraPermissionDenied(
          const MobileScannerState.uninitialized().copyWith(
            error: const MobileScannerException(
              errorCode: MobileScannerErrorCode.controllerUninitialized,
            ),
          ),
        ),
        isFalse,
      );
      expect(
        scannerCameraPermissionDenied(const MobileScannerState.uninitialized()),
        isFalse,
      );
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
      expect(find.text('Search by name'), findsOneWidget);
      expect(find.text('Scan again'), findsOneWidget);
      expect(find.text('Help add this product'), findsNothing);
      expect(
        find.textContaining('Search by name or scan again'),
        findsOneWidget,
      );
    });

    testWidgets('can route a manual barcode miss into the same intake', (
      tester,
    ) async {
      var submitted = false;
      await tester.pumpWidget(
        wrap(
          ScannerNotFoundSheet(
            upc: '050428381397',
            onTryAgain: () {},
            onSearchByName: () {},
            onSubmitProduct: () => submitted = true,
          ),
        ),
      );

      expect(find.text('Help add this product'), findsOneWidget);
      await tester.tap(find.text('Help add this product'));
      expect(submitted, isTrue);
    });
  });

  group('PGScanNotFound', () {
    testWidgets('offers search-by-name fallback for missing catalog barcodes', (
      tester,
    ) async {
      var searched = false;

      await tester.pumpWidget(
        wrap(
          PGScanNotFound(
            scannedCode: '050428341902',
            onRetry: () {},
            onSearchByName: () => searched = true,
            onManualEntry: () {},
            onSubmitProduct: () {},
            onClose: () {},
          ),
        ),
      );

      expect(find.text("We couldn't find this product"), findsOneWidget);
      expect(find.text('050428341902'), findsOneWidget);
      expect(find.text('Search by name'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Enter code manually'), findsOneWidget);
      expect(find.text('Help add this product'), findsOneWidget);

      await tester.tap(find.text('Search by name'));

      expect(searched, isTrue);
    });

    testWidgets('opens the structured submission action for the scanned UPC', (
      tester,
    ) async {
      var submitted = false;
      await tester.pumpWidget(
        wrap(
          PGScanNotFound(
            scannedCode: '050428341902',
            onRetry: () {},
            onSearchByName: () {},
            onManualEntry: () {},
            onSubmitProduct: () => submitted = true,
            onClose: () {},
          ),
        ),
      );

      await tester.tap(find.text('Help add this product'));

      expect(submitted, isTrue);
    });

    testWidgets('blocks background semantics and exposes a 44pt close action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        wrap(
          PGScanNotFound(
            onRetry: () {},
            onSearchByName: () {},
            onManualEntry: () {},
            onClose: () {},
          ),
        ),
      );

      expect(find.bySemanticsLabel('Product not found'), findsOneWidget);
      final close = find.byTooltip('Close product not found');
      expect(close, findsOneWidget);
      expect(tester.getSize(close).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(close).height, greaterThanOrEqualTo(44));
      semantics.dispose();
    });

    testWidgets('remains scrollable on a small screen with large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: wrap(
            PGScanNotFound(
              scannedCode: '050428341902',
              onRetry: () {},
              onSearchByName: () {},
              onManualEntry: () {},
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Enter code manually'),
        120,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Enter code manually'), findsOneWidget);
    });
  });

  group('PGVerdictReveal', () {
    testWidgets('announces the recognized product as a live status', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        wrap(
          const PGVerdictReveal(
            kind: PGVerdictKind.success,
            caption: 'Magnesium Glycinate',
            autoDismissAfter: null,
            playHaptic: false,
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('Product found. Magnesium Glycinate'),
        findsOneWidget,
      );
      semantics.dispose();
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
