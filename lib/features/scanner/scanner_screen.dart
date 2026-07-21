import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_scan_not_found.dart';
import 'package:pharmaguide/core/components/pg_verdict_reveal.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/scanner/manual_barcode_sheet.dart';
import 'package:pharmaguide/features/scanner/scanner_logic.dart';
import 'package:pharmaguide/features/scanner/v2/camera_permission_v2_screen.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/perf_trace_service.dart';
import 'package:pharmaguide/services/scan_limit_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

bool scannerCameraPermissionDenied(MobileScannerState state) {
  return state.error?.errorCode == MobileScannerErrorCode.permissionDenied;
}

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  // Only product barcodes are accepted; QR/marketing codes are
  // intentionally ignored. Without this filter mobile_scanner triggers
  // onDetect for every barcode the camera sees — including the
  // marketing QR codes printed on the back of many supplement bottles —
  // which would produce a confusing "Product not found / UPC:
  // http://..." sheet for users who pointed at the wrong side of the
  // package. Restricting to UPC-A / UPC-E / EAN-13 / EAN-8 means the
  // camera silently passes over non-product symbologies; the user
  // sees nothing happen until they aim at the actual UPC, which
  // matches their expectation of "scan the barcode".
  final _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    formats: const [
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
    ],
  );
  bool _hasScanned = false;
  bool _isLookingUp = false;

  // S1 — v2 verdict reveal (2-tone) instead of a flat color wash.
  PGVerdictKind? _revealKind;
  String? _revealCaption;
  ProductsCoreData? _pendingRevealProduct;

  // S1 — full-screen not-found overlay (replaces bottom sheet only
  // for presentation; failed-scan sensor + actions unchanged).
  bool _showNotFound = false;
  String? _notFoundUpc;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return; // Prevent double-scan

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    final value = barcode.rawValue;
    if (value == null || value.isEmpty) return;

    setState(() => _hasScanned = true);
    // Decorative tap haptic — confirms barcode was captured. Suppressed
    // under reduce-motion via PGHaptics.tap.
    unawaited(PGHaptics.tap(context));
    _lookUpProduct(value);
  }

  Future<void> _lookUpProduct(String upc) async {
    final allowed = await _recordAllowedScan();
    if (!mounted) return;
    if (!allowed) {
      _showGuestScanLimitSheet();
      setState(() => _hasScanned = false);
      return;
    }

    setState(() => _isLookingUp = true);

    try {
      final db = ref.read(coreDatabaseProvider);
      final product = await db.findByUpc(upc);

      if (!mounted) return;

      setState(() => _isLookingUp = false);

      if (product != null) {
        CrashReportingService().setScanResult('found');
        // Persist the scan before we navigate so any mounted Home shell can
        // leave first-launch mode and refresh Recents immediately.
        await ref
            .read(userDatabaseProvider)
            .recordScanEvent(
              dsldId: product.dsldId,
              upcSku: product.upcSku,
              productName: product.productName,
            );
        CrashReportingService().log('scan_complete_camera');
        // Home v2 picks up new scans via its own
        // `_v2RecentScansProvider.autoDispose` on tab refocus + pull-
        // to-refresh; no external invalidation needed after the v1
        // home screen retirement.
        await _showVerdictFlashAndNavigate(product);
      } else {
        CrashReportingService().setScanResult('not_found');
        _showProductNotFound(upc);
      }
      // Bare catch is intentional: DB layer can throw Error subtypes
      // (e.g. StateError on corrupt data). Letting an Error propagate
      // leaves `_hasScanned = true`, permanently locking the scanner
      // until app restart — a hard failure mode for a medical-grade
      // lookup screen. Safer to swallow and show "not found".
      // ignore: avoid_catches_without_on_clauses
    } catch (e, st) {
      CrashReportingService().setScanResult('error');
      CrashReportingService().recordError(e, st, hint: 'scanner:db_error');
      if (!mounted) return;
      setState(() => _isLookingUp = false);
      _showProductNotFound(upc);
    }
  }

  /// S1/S2 — two-tone [PGVerdictReveal] with product name caption, then
  /// navigate to detail. Keeps production haptics + perf trace + reset.
  Future<void> _showVerdictFlashAndNavigate(ProductsCoreData product) async {
    // Severity-gated haptics stay on the production path; reveal plays
    // no second haptic (playHaptic: false).
    unawaited(PGHaptics.forVerdict(product.verdict, context));

    setState(() {
      _revealKind = verdictRevealKind(product.verdict);
      _revealCaption = product.productName.trim().isEmpty
          ? null
          : product.productName.trim();
      _pendingRevealProduct = product;
    });
  }

  Future<void> _completeRevealAndNavigate() async {
    final product = _pendingRevealProduct;
    if (!mounted) return;
    setState(() {
      _revealKind = null;
      _revealCaption = null;
      _pendingRevealProduct = null;
    });
    if (product == null) {
      setState(() => _hasScanned = false);
      return;
    }

    // Scan→verdict latency trace begins at the navigation handoff;
    // product detail finishes it when the hero verdict first renders.
    PerfTraceService().startScanToVerdict();
    // Land directly on the canonical product route. Scan analytics are
    // recorded before this handoff; do not append unused route state.
    await context.push(Routes.productDetail(product.dsldId));

    if (mounted) {
      setState(() => _hasScanned = false);
    }
  }

  void _showProductNotFound(String upc) {
    // Layer 4 missing-UPC sensor: persist the miss locally (UPC + count
    // only; no user identifier per the privacy contract in
    // failed_scans_table.dart) and breadcrumb to Sentry so it appears
    // near any crash that follows. Fire-and-forget — a transient DB
    // error must not block the user-facing not-found surface.
    unawaited(ref.read(userDatabaseProvider).recordFailedScan(upc));
    // Event name ONLY — never the barcode.
    CrashReportingService().log('scan_failed_missing_upc');

    setState(() {
      _showNotFound = true;
      _notFoundUpc = upc;
    });
  }

  void _dismissNotFound() {
    if (!mounted) return;
    setState(() {
      _showNotFound = false;
      _notFoundUpc = null;
      _hasScanned = false;
    });
  }

  /// Opens the manual barcode entry bottom sheet, then runs the same
  /// `_lookUpProduct` flow that the camera scan uses.
  Future<void> _openManualBarcodeSheet() async {
    if (_hasScanned) return;
    setState(() => _hasScanned = true);
    final barcode = await showManualBarcodeSheet(context);
    if (!mounted) return;
    if (barcode == null) {
      setState(() => _hasScanned = false);
      return;
    }
    await _lookUpProduct(barcode);
  }

  Future<void> _openAppSettings() {
    return launchUrl(
      Uri.parse('app-settings:'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<bool> _recordAllowedScan() async {
    final prefs = await SharedPreferences.getInstance();
    final authMode = ref.read(authStateProvider);
    final service = ScanLimitService(
      prefs: prefs,
      isSignedIn: authMode == AuthMode.signedIn,
    );
    return service.recordScan();
  }

  void _showGuestScanLimitSheet() {
    PGModal.bottomSheet<void>(
      context: context,
      builder: (ctx) => GuestScanLimitSheet(
        onSignIn: () {
          Navigator.pop(ctx);
          context.push(Routes.authInvitation);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Camera
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
            errorBuilder: (_, _) => const ColoredBox(color: Colors.black),
          ),
          // Overlay
          Positioned.fill(
            child: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _scannerController,
              builder: (context, scannerState, _) {
                if (scannerCameraPermissionDenied(scannerState)) {
                  return CameraPermissionV2Screen(
                    denied: true,
                    onPrimaryAction: () => unawaited(_openAppSettings()),
                    onManualEntry: _openManualBarcodeSheet,
                  );
                }
                final cameraUnavailable = scannerState.error != null;
                return SafeArea(
                  child: Column(
                    children: [
                      // Top bar
                      Padding(
                        padding: const EdgeInsets.all(V2Spacing.space16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Scan product',
                              style: V2Typography.titleSm(color: Colors.white),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.flash_on_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () => _scannerController.toggleTorch(),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: cameraUnavailable
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: V2Spacing.space24,
                                  ),
                                  child: _ScannerUnavailableCard(),
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 250,
                                        maxHeight: 250,
                                      ),
                                      child: AspectRatio(
                                        aspectRatio: 1,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Colors.white70,
                                              width: 2,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              V2Spacing.radiusCard,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: V2Spacing.space16),
                                    Text(
                                      'Center the barcode in the frame',
                                      style: V2Typography.bodyMedium(
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: V2Spacing.space8),
                                    Text(
                                      'We will match it against your on-device product catalog.',
                                      style: V2Typography.bodySm(
                                        color: Colors.white.withValues(
                                          alpha: 0.72,
                                        ),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      // Bottom actions
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          V2Spacing.space24,
                          V2Spacing.space16,
                          V2Spacing.space24,
                          V2Spacing.space24,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PGPillButton(
                              label: 'Enter code manually',
                              icon: Icons.keyboard_rounded,
                              variant: PGPillVariant.primary,
                              expand: true,
                              onPressed: _openManualBarcodeSheet,
                            ),
                            const SizedBox(height: V2Spacing.space12),
                            PGPillButton(
                              label: 'Add medication',
                              icon: Icons.medication_outlined,
                              variant: PGPillVariant.secondary,
                              expand: true,
                              onPressed: () =>
                                  context.push(Routes.medicationEntry),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: kPGNavBarHeight),
                    ],
                  ),
                );
              },
            ),
          ),
          // Loading overlay
          if (_isLookingUp) const ScannerLookupOverlay(),
          // S1 — v2 verdict reveal (success / attention).
          if (_revealKind != null)
            PGVerdictReveal(
              kind: _revealKind!,
              caption: _revealCaption,
              playHaptic: false,
              onDismiss: () => unawaited(_completeRevealAndNavigate()),
            ),
          // S1 — v2 not-found overlay.
          if (_showNotFound)
            PGScanNotFound(
              scannedCode: _notFoundUpc,
              onRetry: _dismissNotFound,
              onSearchByName: () {
                _dismissNotFound();
                context.push(Routes.search);
              },
              onManualEntry: () {
                _dismissNotFound();
                unawaited(_openManualBarcodeSheet());
              },
              onClose: _dismissNotFound,
            ),
        ],
      ),
    );
  }
}

class GuestScanLimitSheet extends StatelessWidget {
  final VoidCallback onSignIn;

  const GuestScanLimitSheet({super.key, required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: V2Colors.accentTint,
              borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            ),
            child: const Icon(
              Icons.lock_open_rounded,
              color: V2Colors.accent,
              size: 28,
            ),
          ),
          const SizedBox(height: V2Spacing.space16),
          Text(
            'Sign in to keep scanning',
            style: V2Typography.titleSm(color: V2Colors.fg),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'Guest mode includes 3 scans per day. Early-access accounts get unlimited scans and can save a stack, profile, and history.',
            style: V2Typography.bodySm(color: V2Colors.fgMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: V2Spacing.space24),
          PGPillButton(
            label: 'Sign in or create account',
            icon: Icons.person_rounded,
            expand: true,
            onPressed: onSignIn,
          ),
          const SizedBox(height: V2Spacing.space12),
          PGPillButton(
            label: 'Not now',
            icon: Icons.close_rounded,
            variant: PGPillVariant.secondary,
            expand: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _ScannerUnavailableCard extends StatelessWidget {
  const _ScannerUnavailableCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusSheet),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.lg,
      ),
      child: Padding(
        padding: const EdgeInsets.all(V2Spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: V2Colors.accentTint,
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                color: V2Colors.accent,
              ),
            ),
            const SizedBox(height: V2Spacing.space12),
            Text(
              'Camera unavailable',
              textAlign: TextAlign.center,
              style: V2Typography.titleSm(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Enter the barcode manually to search the same on-device catalog.',
              textAlign: TextAlign.center,
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class ScannerLookupOverlay extends StatelessWidget {
  const ScannerLookupOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: V2Spacing.space24),
          padding: const EdgeInsets.all(V2Spacing.space24),
          decoration: BoxDecoration(
            color: V2Colors.surfaceDark.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(V2Spacing.radiusSheet),
            border: Border.all(color: V2Colors.outlineDark),
            boxShadow: V2Shadows.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CupertinoActivityIndicator(color: Colors.white, radius: 14),
              const SizedBox(height: V2Spacing.space16),
              Text(
                'Checking this barcode',
                style: V2Typography.titleSm(color: V2Colors.fgDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: V2Spacing.space8),
              Text(
                'Comparing it against PharmaGuide’s on-device product database.',
                style: V2Typography.bodySm(color: V2Colors.fgMutedDark),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScannerNotFoundSheet extends StatelessWidget {
  final String upc;
  final VoidCallback onTryAgain;
  final VoidCallback onSearchByName;

  const ScannerNotFoundSheet({
    super.key,
    required this.upc,
    required this.onTryAgain,
    required this.onSearchByName,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `PGModal.bottomSheet` already wraps content in `SafeArea` so
      // adding `kPGNavBarHeight` here pushed the action row up above
      // the device's safe-area gutter — Sean called this out as the
      // "modal opens too high" bug on 1.0.0+4. Inside a modal there
      // is no nav bar to clear, only the safe-area inset which the
      // SafeArea wrapper already consumes.
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: V2Colors.cautionTint,
              borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            ),
            child: const Icon(
              Icons.search_off_rounded,
              color: V2Colors.caution,
              size: 28,
            ),
          ),
          const SizedBox(height: V2Spacing.space16),
          Text(
            'Product not found',
            style: V2Typography.titleSm(color: V2Colors.fg),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: V2Spacing.space8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.space12,
              vertical: V2Spacing.space8,
            ),
            decoration: BoxDecoration(
              color: V2Colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            ),
            child: Text(
              'UPC: $upc',
              style: V2Typography.monoData(color: V2Colors.fgMuted),
            ),
          ),
          const SizedBox(height: V2Spacing.space12),
          Text(
            "We couldn't match this barcode yet. Search by name or "
            'scan again to check the on-device catalog.',
            style: V2Typography.bodySm(color: V2Colors.fgMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: V2Spacing.space24),
          Row(
            children: [
              Expanded(
                child: PGPillButton(
                  onPressed: onSearchByName,
                  icon: Icons.search_rounded,
                  label: 'Search by name',
                  variant: PGPillVariant.secondary,
                  expand: true,
                ),
              ),
              const SizedBox(width: V2Spacing.space12),
              Expanded(
                child: PGPillButton(
                  onPressed: onTryAgain,
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Scan again',
                  variant: PGPillVariant.primary,
                  expand: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
