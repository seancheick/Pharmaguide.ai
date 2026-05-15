import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/theme/v2/v2.dart';

/// v2 component gallery — debug-only route at `/dev/v2`.
///
/// Phase 8.1.0 cleanup (2026-05-14): retired the Product Detail / Home /
/// Scanner / Stack / floating-shell prototypes that were built on
/// misbuilt primitives. Mirror-based rebuilds in Phase 8.1.1+ will
/// re-register their links here as they land.
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
            title: 'Shadows',
            children: [
              _ShadowChip('sm', V2Shadows.sm),
              _ShadowChip('md', V2Shadows.md),
              _ShadowChip('lg', V2Shadows.lg),
            ],
          ),
          _Section(
            title: 'Score line · production parity',
            children: [
              Text(
                'Mirror of lib/features/product_detail/widgets/score_line.dart. '
                'Uses ScoreTier directly — locked colors + labels + descriptions.',
                style: V2Typography.bodySm(color: V2Colors.fgMuted),
              ),
              const SizedBox(height: V2Spacing.space16),
              for (final s in const [95, 84, 75, 65, 55, 30])
                Padding(
                  padding: const EdgeInsets.only(bottom: V2Spacing.space16),
                  child: Container(
                    padding: const EdgeInsets.all(V2Spacing.space16),
                    decoration: BoxDecoration(
                      color: V2Colors.surface,
                      borderRadius:
                          BorderRadius.circular(V2Spacing.radiusCard),
                      border: Border.all(color: V2Colors.outline),
                    ),
                    child: PGScoreLine(score: s),
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
          const _Section(
            title: 'Settings',
            children: [
              _PrototypeLink(
                label: 'Settings',
                subtitle: 'Avatar hero · hairline groups · calm controls',
                routePath: '/dev/v2/settings',
              ),
              _PrototypeLink(
                label: 'Settings (signed-in)',
                subtitle: 'Signed-in account variant',
                routePath: '/dev/v2/settings?signedIn=1',
              ),
            ],
          ),
          const _Section(
            title: 'In progress — Phase 8.1',
            children: [
              _GalleryNote(
                text:
                    'Product Detail, Home, Scanner, Stack v2 are being '
                    'rebuilt as visual mirrors of production widgets. '
                    'Routes will return here as each lands.',
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

class _GalleryNote extends StatelessWidget {
  final String text;
  const _GalleryNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.accentTint.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      ),
      child: Text(text, style: V2Typography.bodySm(color: V2Colors.fg)),
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
