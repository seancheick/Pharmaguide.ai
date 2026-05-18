import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

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

  /// **Phase 11.7j.3 — Sean 2026-05-16 home polish.** When true,
  /// the footer renders center-aligned. Used on the Home screen
  /// where the surrounding content is centered around the search
  /// bar / scan CTA / cards. Product Detail keeps the default
  /// left-aligned layout because that page is left-aligned end to
  /// end.
  final bool center;

  const PGTransparencyFooter({
    super.key,
    this.freshnessLabel,
    this.sources = const ['NIH ODS', 'PubMed', 'FDA'],
    this.disclaimer =
        'PharmaGuide is for informational purposes only — talk to your '
        'doctor before changing your stack.',
    this.center = false,
  });

  @override
  Widget build(BuildContext context) {
    // Three stacked lines (Sean 2026-05-15):
    //   1. icon + "DATA SOURCES" eyebrow + sources inline (no ellipsis
    //      — they need to fully fit)
    //   2. Catalog freshness on its own quieter line
    //   3. Disclaimer
    // The previous one-row variant put sources, eyebrow, AND freshness
    // on the same line which forced truncation on narrow widths.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space8,
        vertical: V2Spacing.space12,
      ),
      child: Column(
        crossAxisAlignment: center
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1 — sources line. Eyebrow first, then sources fill the
          // remaining width without truncation.
          Row(
            mainAxisAlignment: center
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            mainAxisSize: center ? MainAxisSize.min : MainAxisSize.max,
            children: [
              const Icon(
                Icons.verified_outlined,
                size: 13,
                color: V2Colors.accent,
              ),
              const SizedBox(width: V2Spacing.space4),
              const PGEyebrow('Data sources'),
              const SizedBox(width: V2Spacing.space8),
              center
                  ? Text(
                      sources.join(' · '),
                      style: V2Typography.caption(color: V2Colors.fgMuted),
                      maxLines: 1,
                    )
                  : Expanded(
                      child: Text(
                        sources.join(' · '),
                        style: V2Typography.caption(color: V2Colors.fgMuted),
                        maxLines: 1,
                      ),
                    ),
            ],
          ),
          if (freshnessLabel != null) ...[
            const SizedBox(height: V2Spacing.space4),
            Padding(
              // Indent matches the icon + gap so the freshness aligns
              // visually under the eyebrow text. When centered, no
              // indent — the line sits flush with the centered group.
              padding: EdgeInsets.only(left: center ? 0 : 17),
              child: Text(
                freshnessLabel!,
                style: V2Typography.caption(color: V2Colors.fgSubtle),
              ),
            ),
          ],
          const SizedBox(height: V2Spacing.space8),
          Text(
            disclaimer,
            style: V2Typography.caption(color: V2Colors.fgSubtle),
            textAlign: center ? TextAlign.center : TextAlign.start,
          ),
        ],
      ),
    );
  }
}
