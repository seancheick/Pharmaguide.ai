import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/home/home_screen.dart';
import 'package:pharmaguide/features/scanner/manual_barcode_sheet.dart';
import 'package:pharmaguide/features/scanner/scanner_logic.dart';

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

  // Verdict flash overlay state
  Color? _flashColor;
  bool _showFlash = false;

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
    setState(() => _isLookingUp = true);

    try {
      final db = ref.read(coreDatabaseProvider);
      final product = await db.findByUpc(upc);

      if (!mounted) return;

      setState(() => _isLookingUp = false);

      if (product != null) {
        // Persist the scan before we navigate so any mounted Home shell can
        // leave first-launch mode and refresh Recents immediately.
        await ref
            .read(userDatabaseProvider)
            .recordScanEvent(
              dsldId: product.dsldId,
              upcSku: product.upcSku,
              productName: product.productName,
            );
        if (mounted) {
          refreshHomeSurface(ref);
        }
        await _showVerdictFlashAndNavigate(product);
      } else {
        _showProductNotFound(upc);
      }
      // Bare catch is intentional: DB layer can throw Error subtypes
      // (e.g. StateError on corrupt data). Letting an Error propagate
      // leaves `_hasScanned = true`, permanently locking the scanner
      // until app restart — a hard failure mode for a medical-grade
      // lookup screen. Safer to swallow and show "not found".
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLookingUp = false);
      _showProductNotFound(upc);
    }
  }

  /// Flash the verdict color briefly, trigger haptic feedback, then navigate.
  Future<void> _showVerdictFlashAndNavigate(ProductsCoreData product) async {
    // Verdict-result haptic — severity-gated via PGHaptics.forVerdict so
    // the user feels the outcome before reading the screen:
    //   RECOMMENDED / GOOD  → di-DUP (Apple Pay success pattern)
    //   MODERATE / REVIEW   → medium (warning)
    //   UNSAFE              → heavy (danger)
    //   BLOCKED             → di-da-DUP (error pattern)
    // Safety-critical tiers always fire even under reduce-motion;
    // success patterns suppress under reduce-motion (passes context).
    unawaited(PGHaptics.forVerdict(product.verdict, context));

    final color = verdictFlashColor(product.verdict);
    setState(() {
      _flashColor = color;
      _showFlash = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    setState(() => _showFlash = false);
    await context.push('/product/${product.dsldId}');

    // Reset after returning from product detail so scanner can detect again.
    if (mounted) {
      setState(() => _hasScanned = false);
    }
  }

  void _showProductNotFound(String upc) {
    PGModal.bottomSheet<void>(
      context: context,
      builder: (ctx) => ScannerNotFoundSheet(
        upc: upc,
        onTryAgain: () {
          Navigator.pop(ctx);
          setState(() => _hasScanned = false);
        },
        onSearchByName: () {
          Navigator.pop(ctx);
          context.push('/search');
        },
      ),
    ).whenComplete(() {
      // If bottom sheet is dismissed (e.g. swipe down), allow re-scan
      if (mounted) {
        setState(() => _hasScanned = false);
      }
    });
  }

  /// Opens the manual barcode entry bottom sheet, then runs the same
  /// `_lookUpProduct` flow that the camera scan uses.
  Future<void> _openManualBarcodeSheet() async {
    final barcode = await showManualBarcodeSheet(context);
    if (!mounted || barcode == null) return;
    unawaited(_lookUpProduct(barcode));
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
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _scannerController,
            builder: (context, scannerState, _) {
              final cameraUnavailable = scannerState.error != null;
              final chromeColor = cameraUnavailable
                  ? AppTheme.lightTextPrimary
                  : Colors.white;
              final actionColor = cameraUnavailable
                  ? AppTheme.brandTeal
                  : Colors.white;
              final actionBorderColor = cameraUnavailable
                  ? AppTheme.brandTeal.withValues(alpha: 0.35)
                  : Colors.white70;
              return SafeArea(
                child: Column(
                  children: [
                    // Top bar
                    Padding(
                      padding: const EdgeInsets.all(AppTheme.space16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Scan Product',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: chromeColor,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.flash_on, color: chromeColor),
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
                                  horizontal: AppTheme.space24,
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
                                            AppTheme.radiusLarge,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AppTheme.space16),
                                  const Text(
                                    'Center the barcode in the frame',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: AppTheme.space6),
                                  const Text(
                                    'We will match it against your on-device product catalog.',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
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
                        AppTheme.space24,
                        AppTheme.space16,
                        AppTheme.space24,
                        AppTheme.space24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: Icon(Icons.keyboard, color: actionColor),
                              label: Text(
                                'Enter code manually',
                                style: TextStyle(color: actionColor),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: actionBorderColor),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              onPressed: _openManualBarcodeSheet,
                            ),
                          ),
                          const SizedBox(height: AppTheme.space12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: Icon(
                                Icons.medication_outlined,
                                color: actionColor,
                              ),
                              label: Text(
                                'Add medication',
                                style: TextStyle(color: actionColor),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: actionBorderColor),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              onPressed: () =>
                                  context.push(Routes.medicationEntry),
                            ),
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
          // Loading overlay
          if (_isLookingUp) const ScannerLookupOverlay(),
          // Verdict flash
          if (_showFlash && _flashColor != null)
            AnimatedOpacity(
              opacity: _showFlash ? 0.35 : 0.0,
              duration: AppMotion.fast,
              child: Container(color: _flashColor),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.brandTeal.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                color: AppTheme.brandTeal,
              ),
            ),
            const SizedBox(height: AppTheme.space12),
            Text(
              'Camera unavailable',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppTheme.space6),
            Text(
              'Enter the barcode manually to search the same on-device catalog.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.lightTextSecondary,
                height: 1.35,
              ),
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
          margin: const EdgeInsets.symmetric(horizontal: AppTheme.space24),
          padding: const EdgeInsets.all(AppTheme.space20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(color: Colors.white12),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoActivityIndicator(color: Colors.white, radius: 14),
              SizedBox(height: AppTheme.space16),
              Text(
                'Checking this barcode',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppTheme.space6),
              Text(
                'Comparing it against PharmaGuide’s on-device product database.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      // `PGModal.bottomSheet` already wraps content in `SafeArea` so
      // adding `kPGNavBarHeight` here pushed the action row up above
      // the device's safe-area gutter — Sean called this out as the
      // "modal opens too high" bug on 1.0.0+4. Inside a modal there
      // is no nav bar to clear, only the safe-area inset which the
      // SafeArea wrapper already consumes.
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space24,
        AppTheme.space8,
        AppTheme.space24,
        AppTheme.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.severityCaution.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
            child: const Icon(
              Icons.search_off_rounded,
              color: AppTheme.severityCaution,
              size: 28,
            ),
          ),
          const SizedBox(height: AppTheme.space16),
          Text(
            'Product not found',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.space8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space12,
              vertical: AppTheme.space8,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
            child: Text(
              'UPC: $upc',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: AppTheme.space12),
          Text(
            "We couldn't match this barcode yet. You can submit the "
            'label so PharmaGuide can review and add it.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.space24),
          // Primary: Submit Product (placeholder — submission flow TBD)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Product submission coming soon.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.upload_rounded),
              label: const Text('Submit Product'),
            ),
          ),
          const SizedBox(height: AppTheme.space12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSearchByName,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Search by name'),
                ),
              ),
              const SizedBox(width: AppTheme.space12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onTryAgain,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan again'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
