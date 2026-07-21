// Trust Receipts sheet — the single "How we score" surface.
//
// One reusable bottom sheet with two sections:
//   1. "How scoring works" — the six v4 pillars, one calm line each.
//   2. "Our sources" — every data source with LIVE counts + freshness
//      from [trustReceiptsProvider]. A count the provider couldn't read
//      is simply omitted (no invented or hardcoded numbers — they drift).
//
// Entry points (both open the SAME sheet):
//   • Product Detail footer row ("How we score")
//   • Score breakdown section link ("How scoring works")
//
// Copy rules: calm-advisory voice, no imperatives, no overclaiming. The
// privacy line is exactly truthful to the architecture — the health
// profile and medications never sync; only the supplement stack syncs,
// and only for signed-in users.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/scoring/v4_pillars.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/data/providers/trust_receipts_provider.dart';

/// One-line plain-language definition per v4 pillar key. Labels and max
/// points are NOT re-hardcoded here — they derive from [kV4PillarSpec]
/// (lib/core/scoring/v4_pillars.dart), the app's single source of truth
/// for the six-pillar shape, so the sheet can never drift from the spec.
const Map<String, String> _pillarDefinitions = {
  'formulation':
      'Ingredient forms we can identify and how well the body absorbs them. '
      'Undisclosed forms receive no form-quality rating.',
  'dose': 'Whether amounts match what studies actually used.',
  'evidence': 'Clinical research behind the ingredients.',
  'transparency': 'Label clarity — full amounts, no hidden blends.',
  'verification':
      'Third-party testing when available, plus brand and manufacturing signals.',
  'safety_hygiene': 'Flagged additives and contaminant signals.',
};

/// Opens the Trust Receipts sheet. Counts are read live from
/// [trustReceiptsProvider]; while loading (or on error) the sheet renders
/// with the static source lines and no numbers — never a placeholder count.
Future<void> showTrustReceiptsSheet(BuildContext context) {
  return PGModal.bottomSheet<void>(
    context: context,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final data = ref
            .watch(trustReceiptsProvider)
            .maybeWhen(data: (d) => d, orElse: () => null);
        return PGTrustReceiptsSheet(data: data);
      },
    ),
  );
}

/// Pure sheet body — testable without providers. Pass [data] with whatever
/// counts are available; null fields (or a null [data]) just omit the
/// numbers.
class PGTrustReceiptsSheet extends StatelessWidget {
  final TrustReceiptsData? data;

  const PGTrustReceiptsSheet({super.key, this.data});

  @override
  Widget build(BuildContext context) {
    final d = data;
    final numberFormat = NumberFormat.decimalPattern();
    String? count(int? n, String singular, String plural) {
      if (n == null) return null;
      return '${numberFormat.format(n)} ${n == 1 ? singular : plural}';
    }

    final catalogDate = d?.catalogGeneratedAt;
    final recallsFreshness = catalogDate == null
        ? null
        : 'Catalog updated ${DateFormat.yMMMd().format(catalogDate.toLocal())}';

    // SingleChildScrollView + Column (not a lazy ListView): the content is
    // a fixed, small set of rows, and eager build keeps the sheet height
    // stable while scrolling.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 640),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space16,
          0,
          V2Spacing.space16,
          V2Spacing.space24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const PGEyebrow('Trust receipts'),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'How we score',
              style: V2Typography.titleSm(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Where every number on this page comes from, and how the '
              'score is built.',
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),

            // ---- Section 1: How scoring works --------------------------
            const SizedBox(height: V2Spacing.space24),
            const PGEyebrow('How scoring works'),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Six pillars, each scored on its own scale. Together they add '
              'up to the score out of 100.',
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space12),
            for (final (key, label, max) in kV4PillarSpec) ...[
              _PillarRow(
                label: label,
                max: max,
                definition: _pillarDefinitions[key] ?? '',
              ),
              const SizedBox(height: V2Spacing.space8),
            ],

            // ---- Section 2: Our sources ---------------------------------
            const SizedBox(height: V2Spacing.space16),
            const PGEyebrow('Our sources'),
            const SizedBox(height: V2Spacing.space12),
            _SourceRow(
              icon: Icons.inventory_2_outlined,
              title: 'Product data',
              subtitle: 'NIH Dietary Supplement Label Database',
              detail: count(d?.productCount, 'product', 'products'),
            ),
            const _SourceGap(),
            const _SourceRow(
              icon: Icons.biotech_outlined,
              title: 'Clinical research',
              subtitle: 'PubMed — curated clinical study clusters',
            ),
            const _SourceGap(),
            _SourceRow(
              icon: Icons.fact_check_outlined,
              title: 'Interactions',
              subtitle: 'Hand-reviewed, evidence-graded',
              detail: count(d?.interactionCount, 'interaction', 'interactions'),
            ),
            const _SourceGap(),
            _SourceRow(
              icon: Icons.hub_outlined,
              title: 'Research pairs',
              subtitle: 'supp.ai PubMed co-occurrence',
              detail: count(d?.researchPairCount, 'pair', 'pairs'),
            ),
            const _SourceGap(),
            _SourceRow(
              icon: Icons.gavel_outlined,
              title: 'Recalls',
              subtitle: 'FDA — synced with each catalog update',
              detail: recallsFreshness,
            ),

            // ---- Closing block ------------------------------------------
            const SizedBox(height: V2Spacing.space24),
            Container(
              padding: const EdgeInsets.all(V2Spacing.space16),
              decoration: BoxDecoration(
                color: V2Colors.accentTint,
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              ),
              child: Text(
                "We don't sell supplements, and scores can't be bought. "
                'Your health profile and medications never leave your device.',
                style: V2Typography.bodySm(color: V2Colors.fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillarRow extends StatelessWidget {
  final String label;
  final int max;
  final String definition;

  const _PillarRow({
    required this.label,
    required this.max,
    required this.definition,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: V2Typography.bodySm(color: V2Colors.fg)),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '/$max',
            style: V2Typography.caption(color: V2Colors.fgMuted),
          ),
        ),
        Expanded(
          child: Text(
            definition,
            style: V2Typography.caption(color: V2Colors.fgMuted),
          ),
        ),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? detail;

  const _SourceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: V2Colors.accentTint,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: V2Colors.accent),
        ),
        const SizedBox(width: V2Spacing.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: V2Typography.bodyMedium(color: V2Colors.fg)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: V2Typography.caption(color: V2Colors.fgMuted),
              ),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(
                  detail!,
                  style: V2Typography.caption(color: V2Colors.fgSubtle),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SourceGap extends StatelessWidget {
  const _SourceGap();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: V2Spacing.space12);
  }
}
