import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// FLTR-4 — `product_status` soft signal chip.
///
/// Pipeline emits a structured block under `blob.product_status`:
///   { "type": "discontinued", "date": "2017-11-28",
///     "display": "Discontinued · 2017-11-28" }
///
/// The handoff contract:
///   * Use `display` verbatim (don't parse/reformat the date).
///   * Grey / subdued. Not alarming, not red, not a safe chip.
///   * Not in alerts. Not a warning. Not part of score math.
///
/// Future `type` values from the pipeline (off_market, reformulated,
/// limited_availability, seasonal) all render the same way — we just
/// trust `display`, so the UI is forward-compatible without edits.
class ProductStatusChip extends StatelessWidget {
  final Map<String, dynamic> productStatus;

  const ProductStatusChip({super.key, required this.productStatus});

  @override
  Widget build(BuildContext context) {
    final display = productStatus['display']?.toString().trim();
    if (display == null || display.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        0,
        AppTheme.space20,
        AppTheme.space8,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space12,
          vertical: AppTheme.space8,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppTheme.space8),
            Expanded(
              child: Text(
                display,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
