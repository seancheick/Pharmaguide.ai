import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_verdict_reveal.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/scanner/manual_barcode_sheet.dart';
import 'package:pharmaguide/features/scanner/missing_product_submission_sheet.dart';
import 'package:pharmaguide/features/scanner/scanner_capture_overlay.dart';
import 'package:pharmaguide/features/scanner/scanner_not_found_sheet.dart';
import 'package:pharmaguide/services/pending_submission_intent.dart';
import 'package:pharmaguide/features/scanner/product_version_picker_sheet.dart';
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
    // noDuplicates suppresses repeat emissions of the same code at the
    // decoder level; the post-dismiss cooldown below handles re-arming
    // after a not-found sheet closes over the same bottle.
    detectionSpeed: DetectionSpeed.noDuplicates,
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

  // Ignore the just-missed code briefly after its not-found sheet closes,
  // or the resumed camera re-fires the same sheet before the user can
  // move the phone off the bottle.
  String? _cooldownCode;
  DateTime? _cooldownUntil;

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
    final cooldownUntil = _cooldownUntil;
    if (value == _cooldownCode &&
        cooldownUntil != null &&
        DateTime.now().isBefore(cooldownUntil)) {
      return;
    }

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
      final resolution = await db.resolveByUpc(upc);

      if (!mounted) return;

      setState(() => _isLookingUp = false);

      final product = switch (resolution) {
        UpcUnique(:final product) => product,
        UpcAmbiguous(:final candidates) => await showProductVersionPickerSheet(
          context,
          candidates: candidates,
        ),
        UpcNotFound() => null,
      };
      if (!mounted) return;

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
      } else if (resolution is UpcNotFound) {
        CrashReportingService().setScanResult('not_found');
        unawaited(_showProductNotFound(upc));
      } else {
        setState(() => _hasScanned = false);
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
      unawaited(_showProductNotFound(upc));
    }
  }

  /// S1/S2 — two-tone [PGVerdictReveal] with product name caption, then
  /// navigate to detail. Keeps production haptics + perf trace + reset.
  Future<void> _showVerdictFlashAndNavigate(ProductsCoreData product) async {
    // Severity-gated haptics stay on the production path; reveal plays
    // no second haptic (playHaptic: false).
    final safetyStatus = catalogProductSafetyStatusId(
      catalogProductSafetyStatus(product),
    );
    unawaited(PGHaptics.forVerdict(safetyStatus, context));

    setState(() {
      _revealKind = verdictRevealKind(safetyStatus);
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

  Future<void> _showProductNotFound(String upc) async {
    // Layer 4 missing-UPC sensor: persist the miss locally (UPC + count
    // only; no user identifier per the privacy contract in
    // failed_scans_table.dart) and breadcrumb to Sentry so it appears
    // near any crash that follows. Fire-and-forget — a transient DB
    // error must not block the user-facing not-found surface.
    unawaited(ref.read(userDatabaseProvider).recordFailedScan(upc));
    // Event name ONLY — never the barcode.
    CrashReportingService().log('scan_failed_missing_upc');

    // A live camera behind a decision sheet is noise — and worse, it
    // looks like it is still tracking whatever the user frames next
    // while the sheet's stored code never changes. Freeze it; every
    // path out of the sheet re-arms explicitly.
    unawaited(_scannerController.stop());
    final action = await showScannerNotFoundSheet(context, scannedCode: upc);
    if (!mounted) return;
    switch (action) {
      case ScannerNotFoundAction.searchByName:
        await context.push(Routes.search);
      case ScannerNotFoundAction.helpAddProduct:
        await _openMissingProductSubmission(upc);
      case ScannerNotFoundAction.addMedication:
        await context.push(Routes.medicationEntry);
      case ScannerNotFoundAction.scanAgain || null:
        break;
    }
    _resumeScanning(cooldownFor: upc);
  }

  /// Re-arms the camera after any overlay flow, briefly ignoring the
  /// code that just failed so the sheet cannot instantly re-fire.
  void _resumeScanning({String? cooldownFor}) {
    if (!mounted) return;
    if (cooldownFor != null) {
      _cooldownCode = cooldownFor;
      _cooldownUntil = DateTime.now().add(const Duration(seconds: 3));
    }
    setState(() => _hasScanned = false);
    unawaited(_scannerController.start());
  }

  Future<void> _openMissingProductSubmission(String upc) async {
    if (upc.isEmpty) return;
    if (ref.read(authStateProvider) != AuthMode.signedIn) {
      // The global auth listener lands users with router.go(...) after
      // sign-in (and a magic link may restart the app), so the sheet is
      // reopened from a persisted intent — never from this await.
      await PendingSubmissionIntent.save(upc);
      if (!mounted) return;
      await context.push(Routes.authInvitation);
      return;
    }

    await showMissingProductSubmissionSheet(context, upc: upc);
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layoutSize = constraints.biggest;
          return Stack(
            children: [
              // Camera — the decode window derives from the SAME layout box
              // as the drawn reticle, so the guide and the real detection
              // region cannot silently diverge.
              MobileScanner(
                controller: _scannerController,
                onDetect: _onDetect,
                scanWindow: ScannerReticleGeometry.scanWindow(layoutSize),
                errorBuilder: (_, _) => const ColoredBox(color: Colors.black),
              ),
              // Contrast chrome above the feed: cutout scrim, corner
              // brackets, and a pill-backed helper line — raw text over a
              // live camera is unreadable on bright scenes.
              const ScannerCaptureOverlay(helperText: 'Point at the barcode'),
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
                                  style: V2Typography.titleSm(
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.flash_on_rounded,
                                    color: Colors.white,
                                  ),
                                  onPressed: () =>
                                      _scannerController.toggleTorch(),
                                ),
                              ],
                            ),
                          ),
                          // The reticle, scrim, and helper pill live in
                          // ScannerCaptureOverlay behind this layer; this
                          // slot only surfaces the camera-unavailable card.
                          Expanded(
                            child: Center(
                              child: cameraUnavailable
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: V2Spacing.space24,
                                      ),
                                      child: _ScannerUnavailableCard(),
                                    )
                                  : const SizedBox.shrink(),
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
            ],
          );
        },
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
              color: context.v2.accentTint,
              borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            ),
            child: Icon(
              Icons.lock_open_rounded,
              color: context.v2.accent,
              size: 28,
            ),
          ),
          const SizedBox(height: V2Spacing.space16),
          Text(
            'Sign in to keep scanning',
            style: V2Typography.titleSm(color: context.v2.fg),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'Guest mode includes 3 scans per day. Early-access accounts get unlimited scans and can save a stack, profile, and history.',
            style: V2Typography.bodySm(color: context.v2.fgMuted),
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
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusSheet),
        border: Border.all(color: context.v2.outline),
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
                color: context.v2.accentTint,
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              ),
              child: Icon(
                Icons.qr_code_scanner_rounded,
                color: context.v2.accent,
              ),
            ),
            const SizedBox(height: V2Spacing.space12),
            Text(
              'Camera unavailable',
              textAlign: TextAlign.center,
              style: V2Typography.titleSm(color: context.v2.fg),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Enter the barcode manually to search the same on-device catalog.',
              textAlign: TextAlign.center,
              style: V2Typography.bodySm(color: context.v2.fgMuted),
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
            color: V2Palette.dark.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(V2Spacing.radiusSheet),
            border: Border.all(color: V2Palette.dark.outline),
            boxShadow: V2Shadows.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CupertinoActivityIndicator(color: Colors.white, radius: 14),
              const SizedBox(height: V2Spacing.space16),
              Text(
                'Checking this barcode',
                style: V2Typography.titleSm(color: V2Palette.dark.fg),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: V2Spacing.space8),
              Text(
                'Comparing it against PharmaGuide’s on-device product database.',
                style: V2Typography.bodySm(color: V2Palette.dark.fgMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
