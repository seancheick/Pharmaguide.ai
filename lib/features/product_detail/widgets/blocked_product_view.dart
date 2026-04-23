import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';

/// FLTR-10 — BLOCKED MODE.
///
/// Rendered in place of the full product detail when a product's
/// verdict is BLOCKED. Safety overrides everything: no score, no
/// ingredients, no interaction cards, no stack action. Only the
/// banned-ingredient reason, a plain-English explanation, and a "do
/// not use" directive.
///
/// The view watches [detailBlobProvider] to surface the richer
/// [banned_substance_detail] block emitted by the pipeline —
/// substance name, a one-line verdict, and a paragraph-length
/// safety warning with regulatory/clinical context. When the blob
/// hasn't loaded yet or the product lacks the block, the view
/// falls back to the coarse `blockingReason` from products_core
/// (today an enum-like "banned_ingredient") plus the static
/// educational paragraph. Reason/warning text is [SelectableText]
/// so a user can copy the exact substance name to share with a
/// healthcare provider — FLTR-17 requires no truncation of banned
/// ingredients.
class BlockedProductView extends ConsumerWidget {
  final String dsldId;
  final String productName;
  final String brandName;
  final String verdict;
  final String blockingReason;
  final String? shareTitle;
  final String? shareDescription;
  final String? shareHighlights;

  const BlockedProductView({
    super.key,
    required this.dsldId,
    required this.productName,
    required this.brandName,
    required this.verdict,
    required this.blockingReason,
    this.shareTitle,
    this.shareDescription,
    this.shareHighlights,
  });

  bool get _canShare => shareTitle != null && shareTitle!.isNotEmpty;

  void _handleShare() {
    if (!_canShare) return;
    ShareService().shareProduct(
      shareTitle: shareTitle!,
      shareDescription: shareDescription ?? '',
      shareHighlights: shareHighlights,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const danger = AppTheme.severityContraindicated;

    // Pipeline-emitted detail. Absent while the blob is still being
    // fetched or when the product row carries no SHA (not-scored
    // edge case); we gracefully fall back to the coarse reason.
    final blobAsync = ref.watch(detailBlobProvider(dsldId));
    final bsd = blobAsync.asData?.value?['banned_substance_detail']
        as Map<String, dynamic>?;
    final substanceName = (bsd?['substance_name'] as String?)?.trim();
    final oneLiner =
        (bsd?['safety_warning_one_liner'] as String?)?.trim();
    final safetyWarning = (bsd?['safety_warning'] as String?)?.trim();

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          productName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_canShare)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
              onPressed: _handleShare,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space24,
          AppTheme.space16,
          AppTheme.space24,
          AppTheme.space32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Product identity — name + brand. No image to keep the
            // blocked surface minimal; we want the eye to land on the
            // red banner, not a product photo.
            Text(
              productName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                height: 1.22,
              ),
            ),
            if (brandName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                brandName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppTheme.space24),

            // BLOCKED banner — promote the one-liner verdict when the
            // pipeline provides it; otherwise stay on the generic line.
            Container(
              padding: const EdgeInsets.all(AppTheme.space20),
              decoration: BoxDecoration(
                color: danger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                border: Border.all(
                  color: danger.withValues(alpha: 0.45),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.block_rounded,
                        size: 26,
                        color: danger,
                      ),
                      const SizedBox(width: AppTheme.space12),
                      Text(
                        'BLOCKED',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: danger,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.space8),
                  Text(
                    (oneLiner != null && oneLiner.isNotEmpty)
                        ? oneLiner
                        : 'This product contains a banned or unsafe ingredient.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            // Why it's blocked — lead with the substance name when
            // the pipeline emits it (e.g. "Vinpocetine"). Fall back
            // to the coarse enum-style reason from products_core
            // while the blob is still loading.
            const SizedBox(height: AppTheme.space24),
            Text(
              "Why it's blocked",
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: AppTheme.space8),
            if (substanceName != null && substanceName.isNotEmpty)
              SelectableText(
                'Banned ingredient detected: $substanceName',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(height: 1.45, fontWeight: FontWeight.w600),
              )
            else if (blockingReason.isNotEmpty)
              SelectableText(
                blockingReason,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
              )
            else
              Text(
                'This product is flagged as unsafe.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),

            // What this means — replace the generic educational
            // paragraph with the pipeline's per-substance warning
            // when available. The warning includes the regulatory
            // source (FDA statement, EU classification, etc.) and
            // clinical mechanism, which is exactly what a user
            // needs to decide next steps.
            const SizedBox(height: AppTheme.space24),
            Text(
              'What this means',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: AppTheme.space8),
            SelectableText(
              (safetyWarning != null && safetyWarning.isNotEmpty)
                  ? safetyWarning
                  : 'Products flagged with banned or undisclosed '
                      'compounds are not considered safe for use. '
                      'These substances may disrupt hormones, affect '
                      'liver function, or be restricted by regulators '
                      'in some regions.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
                height: 1.45,
              ),
            ),

            // Do-not-use directive.
            const SizedBox(height: AppTheme.space24),
            Container(
              padding: const EdgeInsets.all(AppTheme.space16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius:
                    BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.do_not_disturb_on_outlined,
                        size: 20,
                        color: danger,
                      ),
                      const SizedBox(width: AppTheme.space8),
                      Expanded(
                        child: Text(
                          'Do not use this product',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.space8),
                  Text(
                    'Consult a healthcare professional if you have '
                    'already taken this product.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
