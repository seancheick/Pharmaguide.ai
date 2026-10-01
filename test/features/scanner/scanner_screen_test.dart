import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
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
import 'package:pharmaguide/services/gtin.dart';
import 'package:pharmaguide/services/scan_limit_service.dart';
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

  test('scanner symbology is preserved for eight-digit barcodes', () {
    expect(
      gtinSymbologyForBarcodeFormat(BarcodeFormat.upcE),
      GtinSymbology.upcE,
    );
    expect(
      gtinSymbologyForBarcodeFormat(BarcodeFormat.ean8),
      GtinSymbology.ean8,
    );
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

    testWidgets('search leads; adding the product is a full button, not a '
        'footnote — and the code is shown', (tester) async {
      final result = await pumpSheet(tester);

      expect(find.text('Not in your catalog yet'), findsOneWidget);
      expect(find.text('0123456789012'), findsOneWidget);
      expect(find.textContaining('help add it'), findsOneWidget);
      expect(find.text('Add as medication'), findsOneWidget);
      // The code was READ — re-typing it is never offered here; manual
      // entry stays on the idle scanner chrome for the can't-read case.
      expect(find.text('Enter code manually'), findsNothing);

      // One primary, then two equal secondaries in this order.
      final pills = tester
          .widgetList<PGPillButton>(find.byType(PGPillButton))
          .toList();
      expect(pills.map((pill) => pill.label), [
        'Search by name',
        'Help add this product',
        'Scan again',
      ]);
      expect(pills.map((pill) => pill.variant), [
        PGPillVariant.primary,
        PGPillVariant.secondary,
        PGPillVariant.secondary,
      ]);
      final help = tester.getSize(
        find.byKey(const Key('scanner-not-found-help-add')),
      );
      final rescan = tester.getSize(
        find.byKey(const Key('scanner-not-found-rescan')),
      );
      expect(help, rescan);

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
        find.textContaining('That code isn’t in your on-device catalog'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('scanner-not-found-rescan')));
      await tester.pumpAndSettle();
      expect(result.value, ScannerNotFoundAction.scanAgain);
    });

    testWidgets('every action stays reachable on a narrow phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final result = await pumpSheet(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Help add this product'), findsOneWidget);
      expect(find.text('Add as medication'), findsOneWidget);
      // Three stacked buttons at 2x text outgrow the screen; the sheet
      // scrolls rather than clipping the last action.
      await tester.ensureVisible(
        find.byKey(const Key('scanner-not-found-add-medication')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('scanner-not-found-add-medication')),
      );
      await tester.pumpAndSettle();
      expect(result.value, ScannerNotFoundAction.addMedication);
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
    await tester.enterText(find.byType(TextField), '050428381397');
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

  // A guest out of scans still sees a blocked product: the cap may gate
  // convenience, never a recall or banned-ingredient finding (roadmap 1.2).
  group('guest scan cap never hides a safety finding', () {
    const upc = '050428381397';
    String today() => DateTime.now().toUtc().toIso8601String().split('T').first;

    Future<void> scanAtCap(
      WidgetTester tester, {
      required String safetyStatus,
    }) async {
      SharedPreferences.setMockInitialValues({
        'guest_daily_scan_count': 3,
        'guest_daily_scan_date': today(),
      });
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      await coreDb
          .into(coreDb.productsCore)
          .insert(
            ProductsCoreCompanion.insert(
              dsldId: '500',
              productName: 'Scanned product',
              exportVersion: 'test',
              exportedAt: '2026-10-01T00:00:00Z',
              upcSku: const Value(upc),
              productSafetyStatus: Value(safetyStatus),
            ),
          );
      final previousPlatform = MobileScannerPlatform.instance;
      MobileScannerPlatform.instance = _FakeMobileScannerPlatform();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
        MobileScannerPlatform.instance = previousPlatform;
      });

      final router = GoRouter(
        initialLocation: '/scan',
        routes: [
          GoRoute(path: '/scan', builder: (_, __) => const ScannerScreen()),
          GoRoute(
            path: '/product/:id',
            builder: (_, state) =>
                Scaffold(body: Text('Product page ${state.pathParameters['id']}')),
          ),
          GoRoute(
            path: '/auth',
            builder: (_, __) => const Scaffold(body: Text('Sign in')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter code manually'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), upc);
      await tester.pump();
      await tester.tap(find.text('Find Product'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    testWidgets('a blocked product opens and is not charged', (tester) async {
      await scanAtCap(tester, safetyStatus: 'blocked');

      expect(find.text('Product page 500'), findsOneWidget);
      expect(find.byType(GuestScanLimitSheet), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(
        ScanLimitService(prefs: prefs, isSignedIn: false).guestScansUsed,
        3,
      );
    });

    testWidgets('an ordinary product still meets the cap', (tester) async {
      await scanAtCap(tester, safetyStatus: 'no_known_catalog_concern');

      expect(find.byType(GuestScanLimitSheet), findsOneWidget);
      expect(find.text('Product page 500'), findsNothing);
    });
  });

  testWidgets('both camera fallbacks are solid, readable over the feed', (
    tester,
  ) async {
    // An outline button over a live camera shows the video through it; the
    // two fallbacks share the one filled style so both stay legible.
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

    PGPillVariant variantOf(String label) => tester
        .widget<PGPillButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(PGPillButton),
          ),
        )
        .variant;
    expect(variantOf('Enter code manually'), PGPillVariant.primary);
    expect(variantOf('Add medication'), PGPillVariant.primary);
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
            kind: PGVerdictKind.found,
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

    testWidgets('rejects a nine-digit entry with one inline explanation', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => showManualBarcodeSheet(context),
                child: const Text('Open manual entry'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open manual entry'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456789');
      await tester.pump();

      expect(find.text(invalidGtinMessage), findsOneWidget);
      expect(
        tester
            .widget<PGPillButton>(
              find.widgetWithText(PGPillButton, 'Find Product'),
            )
            .onPressed,
        isNull,
      );
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
