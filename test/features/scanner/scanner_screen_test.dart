import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pharmaguide/core/components/pg_scan_not_found.dart';
import 'package:pharmaguide/core/components/pg_verdict_reveal.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/scanner/manual_barcode_sheet.dart';
import 'package:pharmaguide/features/scanner/scanner_capture_overlay.dart';
import 'package:pharmaguide/features/scanner/scanner_not_found_sheet.dart';
import 'package:pharmaguide/features/scanner/scanner_screen.dart';
import 'package:pharmaguide/features/scanner/v2/camera_permission_v2_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('showScannerNotFoundSheet', () {
    Future<ValueNotifier<ScannerNotFoundAction?>> pumpSheet(
      WidgetTester tester, {
      bool manualEntry = false,
    }) async {
      final result = ValueNotifier<ScannerNotFoundAction?>(null);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result.value = await showScannerNotFoundSheet(
                    context,
                    scannedCode: '0123456789012',
                    manualEntry: manualEntry,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('one primary, one secondary, links — and the code shown', (
      tester,
    ) async {
      final result = await pumpSheet(tester);

      expect(find.text('Product not found'), findsOneWidget);
      expect(find.text('0123456789012'), findsOneWidget);
      expect(find.text('Search by name'), findsOneWidget);
      expect(find.text('Scan again'), findsOneWidget);
      expect(find.text('Help add this product'), findsOneWidget);
      expect(find.text('Add as medication'), findsOneWidget);
      // The code was READ — re-typing it is never offered here; manual
      // entry stays on the idle scanner chrome for the can't-read case.
      expect(find.text('Enter code manually'), findsNothing);

      await tester.tap(find.byKey(const Key('scanner-not-found-help-add')));
      await tester.pumpAndSettle();
      expect(result.value, ScannerNotFoundAction.helpAddProduct);
    });

    testWidgets('manual-entry flavor swaps copy and secondary label', (
      tester,
    ) async {
      final result = await pumpSheet(tester, manualEntry: true);

      expect(find.text('Re-enter code'), findsOneWidget);
      expect(find.text('Scan again'), findsNothing);
      expect(
        find.textContaining("isn't in your on-device catalog"),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('scanner-not-found-rescan')));
      await tester.pumpAndSettle();
      expect(result.value, ScannerNotFoundAction.scanAgain);
    });

    testWidgets('quiet actions do not overflow a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpSheet(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Help add this product'), findsOneWidget);
      expect(find.text('Add as medication'), findsOneWidget);
    });
  });

  group('ScannerReticleGeometry', () {
    test('scan window strictly contains the drawn reticle', () {
      const size = Size(390, 844);
      final reticle = ScannerReticleGeometry.reticleRect(size);
      final window = ScannerReticleGeometry.scanWindow(size);
      expect(
        window.contains(reticle.topLeft) &&
            window.contains(reticle.bottomRight),
        isTrue,
        reason:
            'the guide invites, the decode window forgives — a window '
            'smaller than the frame silently ignores well-framed codes',
      );
      expect(reticle.width / reticle.height, closeTo(2.2, 0.01));
    });
  });

  testWidgets('camera permission gate survives a visible keyboard', (
    tester,
  ) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
        home: CameraPermissionV2Screen(
          onPrimaryAction: () {},
          onManualEntry: () {},
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Enter code manually'), findsOneWidget);
  });

  testWidgets('a manual barcode miss keeps manual-entry recovery', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    final previousPlatform = MobileScannerPlatform.instance;
    MobileScannerPlatform.instance = _FakeMobileScannerPlatform();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
      MobileScannerPlatform.instance = previousPlatform;
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
        ],
        child: const MaterialApp(home: ScannerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter code manually'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '111111111111');
    await tester.pump();
    await tester.tap(find.text('Find Product'));
    await tester.pumpAndSettle();

    expect(
      find.text('Re-enter code'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | '),
    );
    expect(find.text('Scan again'), findsNothing);
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

class _FakeMobileScannerPlatform extends MobileScannerPlatform {
  final _barcodes = StreamController<BarcodeCapture>.broadcast();

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodes.stream;

  @override
  Stream<TorchState> get torchStateStream =>
      Stream.value(TorchState.unavailable);

  @override
  Stream<double> get zoomScaleStateStream => Stream.value(1);

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(320, 568),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Widget buildCameraView() => const SizedBox.expand();

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  @override
  Future<void> dispose() => _barcodes.close();
}
