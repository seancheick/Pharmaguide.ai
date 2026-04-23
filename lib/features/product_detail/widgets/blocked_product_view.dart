import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';

/// FLTR-10 — BLOCKED MODE.
///
/// Rendered in place of the full product detail when a product's
/// verdict is BLOCKED or UNSAFE. Safety overrides everything: no
/// score, no ingredients, no interaction cards, no stack action.
/// Only the banned-ingredient reason, a plain-English explanation,
/// and a "do not use" directive.
///
/// The reason text is [SelectableText] so a user can copy the full
/// ingredient name to share with a healthcare provider — FLTR-17
/// requires no truncation of banned ingredients.
class BlockedProductView extends StatelessWidget {
  final String productName;
  final String brandName;
  final String verdict;
  final String blockingReason;
  final String? shareTitle;
  final String? shareDescription;
  final String? shareHighlights;

  const BlockedProductView({
    super.key,
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const danger = AppTheme.severityContraindicated;

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

            // BLOCKED banner.
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
                    'This product contains a banned or unsafe ingredient.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            // Reason — FLTR-17: full text, selectable, never truncated.
            if (blockingReason.isNotEmpty) ...[
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
              SelectableText(
                blockingReason,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
              ),
            ],

            // Plain-language educational context.
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
            Text(
              'Products flagged with banned or undisclosed compounds '
              'are not considered safe for use. These substances may '
              'disrupt hormones, affect liver function, or be '
              'restricted by regulators in some regions.',
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
