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
    // Compact one-row sources strip + disclaimer beneath. Mirrors the
    // production PGCitationStrip layout: verified glyph + "Data sources"
    // label + inline source list on a single row (with freshness on the
    // right), then the educational disclaimer below. Sean's call
    // 2026-05-15 — the previous stacked variant ate too much vertical
    // space at the bottom of every screen.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space8,
        vertical: V2Spacing.space12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: icon + "DATA SOURCES" eyebrow + sources inline +
          // freshness label aligned right. All on one line.
          Row(
            children: [
              const Icon(
                Icons.verified_outlined,
                size: 13,
                color: V2Colors.accent,
              ),
              const SizedBox(width: V2Spacing.space4),
              const PGEyebrow('Data sources'),
              const SizedBox(width: V2Spacing.space8),
              Expanded(
                child: Text(
                  sources.join(' · '),
                  style: V2Typography.caption(color: V2Colors.fgMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (freshnessLabel != null) ...[
                const SizedBox(width: V2Spacing.space8),
                Text(
                  freshnessLabel!,
                  style: V2Typography.caption(color: V2Colors.fgSubtle),
                ),
              ],
            ],
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            disclaimer,
            style: V2Typography.caption(color: V2Colors.fgSubtle),
          ),
        ],
      ),
    );
  }
}
