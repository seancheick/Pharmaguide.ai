import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_score_chip.dart';
import 'package:pharmaguide/core/components/pg_score_ring.dart';
import 'package:pharmaguide/core/theme/v2/v2.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_fixtures.dart';

/// v2 component gallery — debug-only route at `/dev/v2`.
///
/// This page exists to preview v2 design tokens and components as they're
/// built. It is NOT part of the production navigation. Reach it during
/// development via `context.go('/dev/v2')`.
class V2Gallery extends StatelessWidget {
  const V2Gallery({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Colors.bg,
      appBar: AppBar(
        title: Text('v2 gallery', style: V2Typography.titleSm()),
        backgroundColor: V2Colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(V2Spacing.space24),
        children: [
          _Section(
            title: 'Typography',
            children: [
              Text('Display 40pt serif', style: V2Typography.display()),
              const SizedBox(height: V2Spacing.space12),
              Text('Display Sm 32pt serif', style: V2Typography.displaySm()),
              const SizedBox(height: V2Spacing.space12),
              Text('Title 24pt sans 500', style: V2Typography.title()),
              const SizedBox(height: V2Spacing.space8),
              Text('Body 16pt sans 400', style: V2Typography.body()),
              const SizedBox(height: V2Spacing.space8),
              Text(
                'ACTIVE INGREDIENTS',
                style: V2Typography.eyebrow(color: V2Colors.accent),
              ),
              const SizedBox(height: V2Spacing.space4),
              Text(
                'ESTABLISHED',
                style: V2Typography.overline(color: V2Colors.fgMuted),
              ),
            ],
          ),
          const _Section(
            title: 'Color',
            children: [
              _ColorSwatch('bg', V2Colors.bg),
              _ColorSwatch('surface', V2Colors.surface),
              _ColorSwatch('accent', V2Colors.accent),
              _ColorSwatch('accentStrong', V2Colors.accentStrong),
            ],
          ),
          const _Section(
            title: 'Severity tiers',
            children: [
              _SeverityRow(
                'Contraindicated',
                V2Colors.contraindicated,
                V2Colors.contraindicatedTint,
              ),
              _SeverityRow('Avoid', V2Colors.avoid, V2Colors.avoidTint),
              _SeverityRow('Caution', V2Colors.caution, V2Colors.cautionTint),
              _SeverityRow('Monitor', V2Colors.monitor, V2Colors.monitorTint),
              _SeverityRow('Safe', V2Colors.safe, V2Colors.safeTint),
            ],
          ),
          const _Section(
            title: 'Shadows',
            children: [
              _ShadowChip('sm', V2Shadows.sm),
              _ShadowChip('md', V2Shadows.md),
              _ShadowChip('lg', V2Shadows.lg),
            ],
          ),
          _Section(
            title: 'Score visualizations',
            children: [
              Text(
                'Two takes — pick per surface. Ring for emotional moments '
                '(post-scan reveal). Chip for clinical surfaces where '
                'verdict should anchor (Product Detail, Stack, Recents).',
                style: V2Typography.bodySm(color: V2Colors.fgMuted),
              ),
              const SizedBox(height: V2Spacing.space16),
              for (final s in const [88.0, 74.0, 52.0, 32.0])
                Padding(
                  padding: const EdgeInsets.only(bottom: V2Spacing.space16),
                  child: Container(
                    padding: const EdgeInsets.all(V2Spacing.space16),
                    decoration: BoxDecoration(
                      color: V2Colors.surface,
                      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                      border: Border.all(color: V2Colors.outline),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        PGScoreRing(score: s, size: 80, caption: 'PG Score'),
                        PGScoreChip(score: s),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const _Section(
            title: 'First-impression moments',
            children: [
              _PrototypeLink(
                label: 'Splash',
                subtitle: 'Editorial brand-moment entrance',
                routePath: '/dev/v2/splash',
              ),
              _PrototypeLink(
                label: 'Onboarding',
                subtitle: '4-step intro with serif headlines + celebration',
                routePath: '/dev/v2/onboarding',
              ),
            ],
          ),
          _Section(
            title: 'Product Detail prototypes',
            children: [
              for (final f in ProductDetailFixtures.all)
                _PrototypeLink(
                  label: f.id,
                  subtitle: f.productName,
                  routePath: '/dev/v2/product-detail/${f.id}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrototypeLink extends StatelessWidget {
  final String label;
  final String subtitle;
  final String routePath;

  const _PrototypeLink({
    required this.label,
    required this.subtitle,
    required this.routePath,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space8),
      child: Material(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: InkWell(
          onTap: () => context.go(routePath),
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: Container(
            padding: const EdgeInsets.all(V2Spacing.space16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: V2Colors.outline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: V2Typography.eyebrow(color: V2Colors.accent),
                      ),
                      const SizedBox(height: V2Spacing.space4),
                      Text(
                        subtitle,
                        style: V2Typography.body(color: V2Colors.fg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: V2Colors.fgMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: V2Typography.eyebrow(color: V2Colors.accent),
          ),
          const SizedBox(height: V2Spacing.space12),
          ...children,
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final String name;
  final Color color;
  const _ColorSwatch(this.name, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: V2Colors.outline),
            ),
          ),
          const SizedBox(width: V2Spacing.space16),
          Text(name, style: V2Typography.body()),
        ],
      ),
    );
  }
}

class _SeverityRow extends StatelessWidget {
  final String label;
  final Color color;
  final Color tint;
  const _SeverityRow(this.label, this.color, this.tint);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space8),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.space12,
          vertical: V2Spacing.space8,
        ),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: V2Spacing.space8),
            Text(label, style: V2Typography.bodyMedium(color: color)),
          ],
        ),
      ),
    );
  }
}

class _ShadowChip extends StatelessWidget {
  final String label;
  final List<BoxShadow> shadow;
  const _ShadowChip(this.label, this.shadow);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space16),
      child: Container(
        padding: const EdgeInsets.all(V2Spacing.space16),
        decoration: BoxDecoration(
          color: V2Colors.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          boxShadow: shadow,
        ),
        child: Text(label, style: V2Typography.body()),
      ),
    );
  }
}
