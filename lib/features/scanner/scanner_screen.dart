import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/scanner/scanner_logic.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
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
    unawaited(HapticFeedback.lightImpact());
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
        // Record scan in history (fire-and-forget, non-blocking).
        unawaited(ref.read(userDatabaseProvider).recordScanEvent(
              dsldId: product.dsldId,
              upcSku: product.upcSku,
              productName: product.productName,
            ));
        await _showVerdictFlashAndNavigate(product);
      } else {
        _showProductNotFound(upc);
      }
      // Bare catch is intentional: DB layer can throw Error subtypes
      // (e.g. StateError on corrupt data). Letting an Error propagate
      // leaves `_hasScanned = true`, permanently locking the scanner
      // until app restart — a hard failure mode for a medical-grade
      // lookup screen. Safer to swallow and show "not found".
    } catch (_) { // ignore: avoid_catches_without_on_clauses
      if (!mounted) return;
      setState(() => _isLookingUp = false);
      _showProductNotFound(upc);
    }
  }

  /// Flash the verdict color briefly, trigger haptic feedback, then navigate.
  Future<void> _showVerdictFlashAndNavigate(ProductsCoreData product) async {
    unawaited(HapticFeedback.mediumImpact());

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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Camera
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),
          // Overlay
          SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Scan Product',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      IconButton(
                        icon: const Icon(Icons.flash_on, color: Colors.white),
                        onPressed: () => _scannerController.toggleTorch(),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Scan guide
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white70, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Center the barcode in the frame',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 6),
                const Text(
                  'We will match it against your on-device product catalog.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                // Manual entry
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.keyboard, color: Colors.white),
                      label: const Text('Enter code manually',
                          style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => context.push('/search'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Loading indicator
          if (_isLookingUp)
            const ScannerLookupOverlay(),
          // Verdict flash overlay — always in tree so AnimatedOpacity can animate
          IgnorePointer(
            ignoring: !_showFlash,
            child: AnimatedOpacity(
              opacity: _showFlash ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                color: (_flashColor ?? Colors.transparent).withAlpha(180),
                child: Center(
                  child: Icon(
                    _flashColor == AppTheme.severityContraindicated
                        ? Icons.warning_rounded
                        : Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 80,
                  ),
                ),
              ),
            ),
          ),
        ],
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
              CircularProgressIndicator(color: Colors.white),
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
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space24,
        AppTheme.space8,
        AppTheme.space24,
        AppTheme.space24 + kPGNavBarHeight,
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
            "We couldn't match this barcode",
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
            'This can happen with new, reformulated, or private-label products. '
            'Try searching by product name, brand, or a key ingredient.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.space24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onTryAgain,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan again'),
                ),
              ),
              const SizedBox(width: AppTheme.space12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSearchByName,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Search by name'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          Text(
            'Missing-product reporting stays deferred to the future submission flow.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
