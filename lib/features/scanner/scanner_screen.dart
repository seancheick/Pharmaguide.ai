import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

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
        await _showVerdictFlashAndNavigate(product);
      } else {
        _showProductNotFound(upc);
      }
    } on Exception {
      if (!mounted) return;
      setState(() => _isLookingUp = false);
      _showProductNotFound(upc);
    }
  }

  /// Returns the verdict flash color based on the product verdict string.
  /// All tokens come from [AppTheme] so a future theme tweak propagates.
  Color _verdictColor(String? verdict) {
    switch (verdict?.toUpperCase()) {
      case 'RECOMMENDED':
        return AppTheme.scoreExceptional;
      case 'GOOD':
        return AppTheme.scoreExcellent;
      case 'REVIEW':
      case 'MODERATE':
        return AppTheme.severityCaution;
      case 'BLOCKED':
      case 'UNSAFE':
        return AppTheme.severityContraindicated;
      default:
        return AppTheme.scoreExcellent; // Default to green
    }
  }

  /// Flash the verdict color briefly, trigger haptic feedback, then navigate.
  Future<void> _showVerdictFlashAndNavigate(ProductsCoreData product) async {
    unawaited(HapticFeedback.mediumImpact());

    final color = _verdictColor(product.verdict);
    setState(() {
      _flashColor = color;
      _showFlash = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    setState(() => _showFlash = false);
    unawaited(context.push('/product/${product.dsldId}'));
  }

  void _showProductNotFound(String upc) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final scheme = theme.colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space24,
            AppTheme.space16,
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
              ),
              const SizedBox(height: AppTheme.space8),
              Text(
                'UPC: $upc',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: AppTheme.space8),
              Text(
                "This product isn't in our database yet.",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.space24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() => _hasScanned = false);
                      },
                      child: const Text('Scan another'),
                    ),
                  ),
                  const SizedBox(width: AppTheme.space12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.push('/search');
                      },
                      child: const Text('Search instead'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.space16),
            ],
          ),
        );
      },
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
                const Text('Point camera at barcode',
                    style: TextStyle(color: Colors.white70, fontSize: 16)),
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
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Looking up product...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
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
