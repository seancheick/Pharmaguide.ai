import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// v2 mirror of `TransparencyFooter`
/// (lib/features/product_detail/widgets/transparency_footer.dart).
///
/// Always-visible footer at the bottom of the Product Detail screen.
/// Lists data sources, catalog freshness, and the educational
/// disclaimer. Calm muted tone — never competes with the page content.
class PGTransparencyFooter extends StatelessWidget {
  /// Freshness label ("Updated 3 days ago" / "Updated today" /
  /// "Updated Apr 2025"). Production composes via
  /// `formatRelativeUpdate(last_updated, nowOverride)`.
  final String? freshnessLabel;

  /// Source institutions — typically ["NIH ODS", "PubMed", "FDA"].
  final List<String> sources;

  /// Educational disclaimer copy. Production uses a single locked
  /// constant `kTransparencyDisclaimer`.
  final String disclaimer;

  const PGTransparencyFooter({
    super.key,
    this.freshnessLabel,
    this.sources = const ['NIH ODS', 'PubMed', 'FDA'],
    this.disclaimer =
        'PharmaGuide is for informational purposes only — talk to your '
        'doctor before changing your stack.',
  });

  @override
  Widget build(BuildContext context) {
    // Centered footer: sources render as a single inline "NIH ODS · PubMed
    // · FDA" line (Sean's call 2026-05-15 — never wrap to multiple rows),
    // freshness sits below in a quieter tone, then the locked disclaimer
    // sits centered and capped to two lines.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space8,
        vertical: V2Spacing.space16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const PGEyebrow('Data sources', textAlign: TextAlign.center),
          const SizedBox(height: V2Spacing.space8),
          Text(
            sources.join(' · '),
            style: V2Typography.caption(color: V2Colors.fgMuted),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (freshnessLabel != null) ...[
            const SizedBox(height: V2Spacing.space8),
            Text(
              freshnessLabel!,
              style: V2Typography.caption(color: V2Colors.fgSubtle),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: V2Spacing.space16),
          Text(
            disclaimer,
            style: V2Typography.caption(color: V2Colors.fgSubtle),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
