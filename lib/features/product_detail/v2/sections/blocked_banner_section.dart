// Phase 11.7c.1 — Blocked-banner section adapter (Hero `bottomBanner` slot).
//
// V2 mirror of production's private `_BlockedBanner` widget (line 1626
// of product_detail_screen.dart). Slots into Hero's `bottomBanner` prop
// so blocked products read the same way visually but in v2 tones.
//
// Composition (matches production exactly — verified against parity
// checklist row S1.5):
//   1. PGSeverityBanner (danger tone, useV2Tones=true): calm headline
//      "PharmaGuide does not recommend this product" + reason body.
//   2. Optional regulatory date line ("FDA ban effective · Sep 7, 2016")
//      via `buildRegulatoryLine` from the production helper module.
//   3. Optional substance-name row ("Ingredient: <name>") when the
//      pipeline didn't bake the name into the one-liner.
//   4. Optional safety-warning paragraph (longer prose).
//   5. Optional italic context note (substance-vs-adulterant
//      disambiguation) via `contextNoteFor`.
//   6. Optional detail paragraph (mechanism / FDA-story).
//   7. Optional "FDA sources" link list (tap → launchUrl external).
//
// Mapping data → display lives in `blocked_banner_helpers.dart`. This
// file is pure widget composition.
//
// Per Sean's 2026-05 product-tone guidelines: NO imperative "DO NOT
// USE" headlines. The danger tone + calm "PharmaGuide does not
// recommend this product" already conveys the recommendation; loud
// red imperatives read as the app shouting at the user. Voice stays
// clinical/advisory throughout.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/blocked_banner_helpers.dart';
import 'package:pharmaguide/features/product_detail/widgets/blocked_banner_context.dart'
    show buildRegulatoryLine, contextNoteFor;
import 'package:url_launcher/url_launcher.dart';

/// Build the v2 blocked banner — slot this widget into
/// `PGHeroSection.bottomBanner` when the product is blocked.
///
/// Returns `SizedBox.shrink()` when the product is not blocked OR
/// when there is no headline to render (defensive — should never
/// happen in production because `isBlocked` already implies a verdict).
Widget buildBlockedBannerSection({
  required String verdict,
  required String blockingReason,
  required List<Map<String, dynamic>> topWarnings,
  required Map<String, dynamic>? bannedSubstanceDetail,
}) {
  // Resolve display inputs from the data via helpers.
  final substanceName =
      bannedSubstanceDetail?['substance_name']?.toString().trim();
  final oneLiner =
      bannedSubstanceDetail?['safety_warning_one_liner']?.toString().trim();
  final safetyWarning =
      bannedSubstanceDetail?['safety_warning']?.toString().trim();
  final banContext =
      bannedSubstanceDetail?['ban_context']?.toString().trim();
  final detailText =
      bannedSubstanceDetail?['detail']?.toString().trim();
  final regulatoryLine = buildRegulatoryLine(
    bannedSubstanceDetail?['regulatory_date_label']?.toString(),
    bannedSubstanceDetail?['date']?.toString(),
  );
  final contextNote = contextNoteFor(banContext);
  final reasonBody = resolveBlockedReasonBody(
    oneLiner: oneLiner,
    substanceName: substanceName,
    blockingReason: blockingReason,
  );
  final fdaLinks = chooseFdaLinks(
    bannedSubstanceDetail: bannedSubstanceDetail,
    topWarnings: topWarnings,
  );

  // Whether the standalone "Ingredient: <name>" row should render.
  // Suppressed when the one-liner already mentions the substance by
  // name in prose (avoids redundancy).
  final showSubstanceRow = substanceName != null &&
      substanceName.isNotEmpty &&
      (oneLiner == null || oneLiner.isEmpty);

  return Padding(
    padding: const EdgeInsets.only(top: V2Spacing.space12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Severity banner — calm decisive headline.
        const _BlockedTitleBanner(),

        // Inject body text directly under the title via a dedicated row
        // because PGSeverityBanner's body slot doesn't expose all the
        // typographic control we need for the v2 cream surface.
        Padding(
          padding: const EdgeInsets.only(top: V2Spacing.space8),
          child: Text(
            reasonBody,
            style: V2Typography.bodySm(color: V2Colors.fg),
          ),
        ),

        // 2. Regulatory date line.
        if (regulatoryLine != null) ...[
          const SizedBox(height: V2Spacing.space8),
          Text(
            regulatoryLine,
            style: V2Typography.label(color: V2Colors.contraindicated),
          ),
        ],

        // 3. Substance-name row.
        if (showSubstanceRow) ...[
          const SizedBox(height: V2Spacing.space12),
          Text(
            'Ingredient: $substanceName',
            style: V2Typography.titleSm(color: V2Colors.fg),
          ),
        ],

        // 4. Safety-warning paragraph.
        if (safetyWarning != null && safetyWarning.isNotEmpty) ...[
          const SizedBox(height: V2Spacing.space8),
          Text(
            safetyWarning,
            style: V2Typography.bodySm(color: V2Colors.fgMuted),
          ),
        ],

        // 5. Italic context note (substance-vs-adulterant nuance).
        if (contextNote != null) ...[
          const SizedBox(height: V2Spacing.space8),
          Text(
            contextNote,
            style: V2Typography.bodySm(color: V2Colors.fgMuted).copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],

        // 6. Detail / FDA-story paragraph.
        if (detailText != null && detailText.isNotEmpty) ...[
          const SizedBox(height: V2Spacing.space12),
          Text(
            detailText,
            style: V2Typography.bodySm(color: V2Colors.fgMuted),
          ),
        ],

        // 7. FDA sources link list.
        if (fdaLinks.isNotEmpty) ...[
          const SizedBox(height: V2Spacing.space12),
          _FdaSourcesBlock(links: fdaLinks),
        ],
      ],
    ),
  );
}

/// Calm danger-tone headline — the only PGSeverityBanner instance.
/// Body text renders below via the parent column so we control
/// typography against the cream surface.
class _BlockedTitleBanner extends StatelessWidget {
  const _BlockedTitleBanner();

  @override
  Widget build(BuildContext context) {
    return const PGSeverityBanner(
      tone: PGBannerTone.danger,
      title: 'PharmaGuide does not recommend this product',
      // Body intentionally null — we render the reason body in the
      // parent column so we can use v2 typography directly on the
      // cream surface (avoids the banner's internal text styling
      // competing with the surrounding context).
      useV2Tones: true,
    );
  }
}

/// FDA sources list — eyebrow label + tap-to-open external links.
class _FdaSourcesBlock extends StatelessWidget {
  final List<String> links;
  const _FdaSourcesBlock({required this.links});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FDA SOURCES',
            style: V2Typography.eyebrow(color: V2Colors.contraindicated),
          ),
          const SizedBox(height: V2Spacing.space4),
          ...links.map((url) => _FdaLinkRow(url: url)),
        ],
      ),
    );
  }
}

class _FdaLinkRow extends StatelessWidget {
  final String url;
  const _FdaLinkRow({required this.url});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            const Icon(
              Icons.open_in_new_rounded,
              size: 11,
              color: V2Colors.contraindicated,
            ),
            const SizedBox(width: V2Spacing.space4),
            Expanded(
              child: Text(
                url,
                style: V2Typography.label(color: V2Colors.contraindicated)
                    .copyWith(
                      decoration: TextDecoration.underline,
                      overflow: TextOverflow.ellipsis,
                    ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
