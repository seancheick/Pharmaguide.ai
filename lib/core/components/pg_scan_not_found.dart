import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Full-screen "we couldn't find this product" overlay.
///
/// Light amber wash (cautionTint over surface) — calm, not alarming.
/// Three actions: search by name, retry scan, enter code manually, or close.
/// Mirrors the production `ScannerNotFoundSheet` intent
/// (lib/features/scanner/scanner_screen.dart) but as a full overlay layered
/// above the camera surface instead of a bottom sheet.
class PGScanNotFound extends StatelessWidget {
  /// Optional barcode text the user just scanned — shown in mono caps
  /// for technical context. Null hides the line.
  final String? scannedCode;

  final VoidCallback onRetry;
  final VoidCallback onSearchByName;
  final VoidCallback onManualEntry;
  final VoidCallback onClose;

  const PGScanNotFound({
    super.key,
    this.scannedCode,
    required this.onRetry,
    required this.onSearchByName,
    required this.onManualEntry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return BlockSemantics(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Product not found',
        child: ColoredBox(
          // Solid amber wash. cautionTint is already 10% opacity over
          // the system bg, so we layer it on a fuller surface so the
          // overlay reads as a single calm material.
          color: V2Colors.caution.withValues(alpha: 0.08),
          child: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      V2Spacing.space24,
                      V2Spacing.space16,
                      V2Spacing.space24,
                      V2Spacing.space24,
                    ),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: _CloseChip(onTap: onClose),
                        ),
                        const Spacer(),
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: V2Colors.caution.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(
                              V2Spacing.radiusCard,
                            ),
                            border: Border.all(
                              color: V2Colors.caution.withValues(alpha: 0.22),
                              width: 0.8,
                            ),
                            boxShadow: V2Shadows.sm,
                          ),
                          child: const Icon(
                            Icons.search_off_rounded,
                            color: V2Colors.caution,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: V2Spacing.space24),
                        Text(
                          "We couldn't find this product",
                          textAlign: TextAlign.center,
                          style: V2Typography.titleSm(color: V2Colors.fg),
                        ),
                        const SizedBox(height: V2Spacing.space8),
                        Text(
                          "The barcode didn't match your on-device catalog. Search "
                          'by name for nearby matches, try again, or enter the code '
                          'by hand.',
                          textAlign: TextAlign.center,
                          style: V2Typography.body(color: V2Colors.fgMuted),
                        ),
                        if (scannedCode != null) ...[
                          const SizedBox(height: V2Spacing.space16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: V2Spacing.space12,
                              vertical: V2Spacing.space4,
                            ),
                            decoration: BoxDecoration(
                              color: V2Colors.surface,
                              borderRadius: BorderRadius.circular(
                                V2Spacing.radiusPill,
                              ),
                              border: Border.all(color: V2Colors.outline),
                            ),
                            child: Text(
                              scannedCode!,
                              style: V2Typography.overline(
                                color: V2Colors.fgMuted,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(flex: 2),
                        PGPillButton(
                          label: 'Search by name',
                          icon: Icons.search_rounded,
                          expand: true,
                          onPressed: onSearchByName,
                        ),
                        const SizedBox(height: V2Spacing.space12),
                        PGPillButton(
                          label: 'Try again',
                          icon: Icons.qr_code_scanner_rounded,
                          variant: PGPillVariant.secondary,
                          expand: true,
                          onPressed: onRetry,
                        ),
                        const SizedBox(height: V2Spacing.space8),
                        PGPillButton(
                          label: 'Enter code manually',
                          icon: Icons.keyboard_rounded,
                          variant: PGPillVariant.ghost,
                          expand: true,
                          onPressed: onManualEntry,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseChip extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Colors.surface,
      shape: const CircleBorder(side: BorderSide(color: V2Colors.outline)),
      elevation: 0,
      child: IconButton(
        tooltip: 'Close product not found',
        onPressed: onTap,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.close_rounded, color: V2Colors.fg, size: 20),
      ),
    );
  }
}
