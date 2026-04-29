// "What we don't know" section (Section 6).
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.7.
//
// Surfaces gaps in the data PharmaGuide has on a product, with
// deliberately soft visual treatment. The thesis: trust amplifies
// through admitted uncertainty. Most apps hide what they don't
// know; surfacing it differentiates from Yuka.
//
// The section is INTENTIONALLY quieter than every other section on
// the screen — outline-only card, onSurfaceVariant text colors,
// no severity icons. The unknowns are context, not warnings; users
// who care about heavy-metal testing or third-party COAs will scan
// for them, but the section never demands attention from users who
// don't.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';

/// Maximum number of bullets surfaced per spec. The section's job
/// is to be honest, not exhaustive — past 4 entries the eye glazes.
const int _maxUnknowns = 4;

/// Compute the unknowns list from the product's trust signals.
///
/// Pure function — no widget refs, no DB calls. Tests construct
/// inputs directly. Returns a list of human-readable bullets in
/// fixed display order; caller truncates and renders.
///
/// Display order is intentional — most actionable / least redundant
/// signals first:
///   1. Third-party testing (heavy metals are the contamination
///      users care about most)
///   2. Manufacturer COA / trust (whether the manufacturer publishes
///      proof of identity + potency)
///   3. Mapped coverage (how much of the product is even in our
///      database)
///   4. Evidence research (how much clinical data backs the actives)
List<String> buildUnknowns({
  required bool isTrustedManufacturer,
  required bool hasThirdPartyTesting,
  required double? mappedCoverage,
  required double? scoreEvidenceResearch,
  required double? scoreEvidenceResearchMax,
}) {
  final unknowns = <String>[];

  if (!hasThirdPartyTesting) {
    unknowns.add('No third-party heavy metal test available');
  }

  if (!isTrustedManufacturer) {
    // Spec calls for "AND no COA URL" — the pipeline doesn't ship a
    // COA URL field today, so we treat untrusted-manufacturer alone
    // as the trigger. When a coa_url field appears on the
    // certification blob, the trigger should tighten to: untrusted
    // AND no COA URL.
    unknowns.add('Manufacturer hasn\'t published recent COAs');
  }

  if (mappedCoverage != null && mappedCoverage < 0.5) {
    unknowns.add('Some ingredients couldn\'t be mapped to our database');
  }

  if (scoreEvidenceResearch != null &&
      scoreEvidenceResearchMax != null &&
      scoreEvidenceResearchMax > 0 &&
      scoreEvidenceResearch < scoreEvidenceResearchMax * 0.4) {
    unknowns.add('Limited clinical research data');
  }

  return unknowns;
}

/// "What we don't know" section widget. Hides entirely when there
/// are no unknowns — the absence of the section is itself a positive
/// signal (everything we usually flag is covered).
class UnknownsSection extends StatelessWidget {
  final bool isTrustedManufacturer;
  final bool hasThirdPartyTesting;
  final double? mappedCoverage;
  final double? scoreEvidenceResearch;
  final double? scoreEvidenceResearchMax;

  const UnknownsSection({
    super.key,
    required this.isTrustedManufacturer,
    required this.hasThirdPartyTesting,
    this.mappedCoverage,
    this.scoreEvidenceResearch,
    this.scoreEvidenceResearchMax,
  });

  @override
  Widget build(BuildContext context) {
    final unknowns = buildUnknowns(
      isTrustedManufacturer: isTrustedManufacturer,
      hasThirdPartyTesting: hasThirdPartyTesting,
      mappedCoverage: mappedCoverage,
      scoreEvidenceResearch: scoreEvidenceResearch,
      scoreEvidenceResearchMax: scoreEvidenceResearchMax,
    );

    if (unknowns.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = unknowns.take(_maxUnknowns).toList(growable: false);
    final overflow = unknowns.length - visible.length;

    return PGCard(
      // Plain (not elevated) so the section sits visually quiet
      // compared to the louder Tradeoffs / Quality cards above.
      variant: PGCardVariant.plain,
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.help_outline_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'What we don\'t know',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          for (final u in visible) _UnknownBullet(text: u),
          if (overflow > 0) ...[
            const SizedBox(height: 2),
            Text(
              '… and $overflow more',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Single unknown bullet — soft tone, no severity icon. The dot is
/// intentionally muted so the row reads as "context" rather than
/// "warning".
class _UnknownBullet extends StatelessWidget {
  final String text;
  const _UnknownBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
