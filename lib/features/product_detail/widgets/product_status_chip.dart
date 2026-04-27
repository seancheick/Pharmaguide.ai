import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// FLTR-4 / FLTR-19 — `product_status` soft signal row.
///
/// Pipeline emits a structured block under `blob.product_status`:
///   { "type": "discontinued", "date": "2017-11-28",
///     "display": "Discontinued · 2017-11-28" }
///
/// FLTR-19 polish vs the FLTR-4 baseline:
///   * Removed the leading info-icon (it looked tappable but wasn't —
///     a hidden affordance). The whole row is now tappable instead.
///   * Humanize the date: "Nov 28, 2017" instead of the raw ISO
///     "2017-11-28". The `display` string stays as a fallback when
///     `type` is absent or `date` can't be parsed.
///   * Tap → bottom sheet with a plain-language explanation, giving
///     the row the affordance its earlier icon implied.
///
/// Placement contract (handoff §5.13): belongs in the Concerns
/// section. Never in Alerts, Interactions, or the header banner
/// row. The product detail sliver ordering keeps it below the
/// header and above the interaction warnings section.
///
/// Forward-compat: the label branches on `type` for the lead-in
/// word (Discontinued / Off-market / Reformulated / etc.) and trusts
/// the pipeline for anything outside the known set by falling back
/// to `display`.
class ProductStatusChip extends StatelessWidget {
  final Map<String, dynamic> productStatus;

  const ProductStatusChip({super.key, required this.productStatus});

  /// Map of known pipeline `type` values → human lead-in word.
  /// Used only to construct the humanized label; anything outside
  /// this set falls through to `display`.
  static const _typeLabels = <String, String>{
    'discontinued': 'Product discontinued',
    'off_market': 'Off market',
    'reformulated': 'Reformulated',
    'limited_availability': 'Limited availability',
    'seasonal': 'Seasonal product',
  };

  /// Build the visible label — "{lead-in} · {humanized date}" when
  /// the blob carries a parseable ISO date and a recognized type;
  /// otherwise the pipeline's verbatim `display` string.
  String? _buildLabel() {
    final display = productStatus['display']?.toString().trim();
    final type = productStatus['type']?.toString().trim().toLowerCase();
    final rawDate = productStatus['date']?.toString().trim();

    final leadIn = type == null ? null : _typeLabels[type];
    if (leadIn != null && rawDate != null && rawDate.isNotEmpty) {
      final parsed = DateTime.tryParse(rawDate);
      if (parsed != null) {
        return '$leadIn · ${DateFormat.yMMMd().format(parsed)}';
      }
    }
    // Fallback: pipeline `display` verbatim (may include raw ISO date).
    if (display != null && display.isNotEmpty) return display;
    return null;
  }

  void _openExplanation(BuildContext context) {
    final type = productStatus['type']?.toString().trim().toLowerCase();
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => _ProductStatusExplanationSheet(type: type),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = _buildLabel();
    if (label == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        0,
        AppTheme.space20,
        AppTheme.space8,
      ),
      child: InkWell(
        onTap: () => _openExplanation(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space12,
            vertical: AppTheme.space8,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius:
                BorderRadius.circular(AppTheme.radiusMedium),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plain-language bottom sheet explaining what a discontinued /
/// off-market / reformulated status means. Kept short so it stands
/// on its own without requiring a back-and-forth — the user sees
/// the state, taps for context, returns.
class _ProductStatusExplanationSheet extends StatelessWidget {
  final String? type;

  const _ProductStatusExplanationSheet({this.type});

  String _bodyCopy() {
    switch (type) {
      case 'reformulated':
        return 'This product has been reformulated. Ingredients, doses, or '
            'inactive components may differ from older bottles, so rescan '
            'the exact version you have in hand.';
      case 'off_market':
        return 'This product appears to be off market or no longer broadly '
            'available. That does not automatically mean it is unsafe, but '
            'availability and listing details may be outdated.';
      case 'limited_availability':
        return 'This product has limited availability. Listing, stock, or '
            'distribution details may change faster than usual.';
      case 'seasonal':
        return 'This product appears to be seasonal. Availability may vary '
            'throughout the year, and newer lots may differ from older ones.';
      case 'discontinued':
      default:
        return 'This product is no longer manufactured. Formulas may have '
            'changed or been replaced in newer versions.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        AppTheme.space16,
        AppTheme.space20,
        AppTheme.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About this product status',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.space12),
          Text(
            _bodyCopy(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
