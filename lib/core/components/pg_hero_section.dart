import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// What the hero renders in its score-line slot. Pure decision — the
/// clinical gating is unit-tested in
/// test/core/components/pg_hero_section_decision_test.dart without
/// pumping widgets.
enum HeroScoreDisplay {
  /// Real scored product with trustworthy coverage → tier-colored
  /// [PGScoreLine].
  tierScore,

  /// A real score with limited confidence. Keep the number available for
  /// comparison, but suppress the tier adjective and color treatment.
  limitedScore,

  /// A product quality score is unavailable. This is intentionally
  /// consumer-neutral: release diagnostics belong to the catalog gate.
  notScored,

  /// BLOCKED — the score slot stays empty; the bottom banner owns the
  /// verdict.
  none,
}

/// Decide what the hero's score slot renders. Precedence mirrors the
/// verdict enum (BLOCKED > NOT_SCORED > low coverage > scored): the
/// blocked banner beats everything, the not-scored hedge is more
/// specific than the coverage hedge, and a null score can NEVER
/// produce a tier line regardless of flags.
HeroScoreDisplay heroScoreDisplayFor({
  required int? score,
  required bool isBlocked,
  required bool isNotScored,
  required bool lowCoverage,
  bool limitedAssessment = false,
}) {
  if (isBlocked) return HeroScoreDisplay.none;
  if (isNotScored || score == null) return HeroScoreDisplay.notScored;
  if (lowCoverage) return HeroScoreDisplay.notScored;
  if (limitedAssessment) return HeroScoreDisplay.limitedScore;
  return HeroScoreDisplay.tierScore;
}

/// FIX 4 gate: positive trust/cert chips ("Third-Party Tested",
/// "Organic") must never render on a BLOCKED product — a green
/// verified badge above the does-not-recommend banner reads as an
/// endorsement.
bool heroShowsTrustChips({required bool isBlocked, required int tagCount}) =>
    !isBlocked && tagCount > 0;

/// Whether the hero paints a caution cue beside the tier score line.
///
/// The pipeline emits a dose-driven CAUTION verdict (safety signal
/// `DOSE_OVER_UL_CAUTION` / `DOSE_OVER_UL_CRITICAL`) when a product
/// exceeds an Upper Limit — and that can coincide with a high formulation
/// score. Deriving the tier from the number alone would then paint a
/// green "85/100 Excellent" hero with no caution cue, hiding the CAUTION
/// entirely.
///
/// The cue only rides alongside a real score. BLOCKED (no score slot),
/// NOT_SCORED, and low-coverage each render their own non-"Excellent"
/// affordance and are deliberately left untouched.
bool heroShowsCautionCue({
  required bool hasCatalogCaution,
  required HeroScoreDisplay scoreDisplay,
}) {
  final showsScore =
      scoreDisplay == HeroScoreDisplay.tierScore ||
      scoreDisplay == HeroScoreDisplay.limitedScore;
  return showsScore && hasCatalogCaution;
}

/// v2 mirror of `_HeaderSection` in
///
///
/// **Same structure preserved verbatim:**
/// - Identity row: 96pt product image + (name / subtitle / trust chips)
/// - Product name: max 3 lines, ellipsis on overflow
/// - Subtitle: `Brand · 60 Capsules · 1 capsule daily` (drops segments
///   cleanly when missing)
/// - Trust chips: outline pills (primary tone for certifications, green
///   for dietary tags), max 4 visible + `+N more` overflow chip
/// - ScoreLine (suppressed when `isBlocked` — banner replaces it; a neutral
///   score-unavailable fallback covers every unscored defensive state)
/// - 240ms entrance fade + 8pt translate (skipped under reduce-motion)
///
/// Wraps the whole hero in a v2 elevated card (cream surface + outline +
/// sm shadow).
///
/// **Image:** caller passes a pre-built widget (production composes
/// `ProductImage` with Hero tag + flightShuttleBuilder). Same contract.
class PGHeroSection extends StatelessWidget {
  /// Product image widget — caller composes with Hero, fallback, etc.
  final Widget imageWidget;

  final String productName;
  final String brandName;

  /// Servings × form segment ("60 Capsules"). Empty/null hides the
  /// segment cleanly.
  final String? servingsLabel;

  /// Number of label servings in the package ("45 servings"). This stays
  /// separate from the physical net-contents segment above.
  final String? servingCountLabel;

  /// User-facing dosing string ("1 capsule daily"). Empty/null hides.
  final String? dosingSummary;

  /// Trust signals — certifications (primary tone) + dietary tags
  /// (green tone). Max 4 visible inline, rest collapsed into `+N more`.
  final List<PGTrustTag> trustTags;

  /// 0–100 product score. Null when [isNotScored]. Drives the
  /// [PGScoreLine] underneath.
  final int? score;

  /// Pipeline-emitted catalog tier for [score].
  final String? qualityTier;

  /// True when no consumer product-quality score is available.
  final bool isNotScored;

  /// True when the product is BLOCKED — suppresses the score line
  /// entirely. Production renders a separate banner; pass that as
  /// [bottomBanner] to keep the layout intact. Also suppresses the
  /// positive trust-chip row (FIX 4) — certifications must not read
  /// as an endorsement above the does-not-recommend banner.
  final bool isBlocked;

  /// True when the product's mapped_coverage is below the 0.3 trust
  /// floor (core/scoring/coverage.dart). Suppresses the tier-colored
  /// score: a low-coverage product must never render a positive verdict.
  final bool lowCoverage;

  /// True when v4 confidence is low even though a score is available.
  final bool limitedAssessment;

  /// Pipeline confidence band for a completed product-quality score.
  final String? scoreConfidence;

  /// Up to two plain-language reasons for the confidence band.
  final List<String> scoreConfidenceDrivers;

  /// Banner widget rendered beneath the score line (used for the
  /// production Blocked / Avoid banners). Null skips the slot.
  final Widget? bottomBanner;

  /// Whether the independent catalog safety assessment is `caution`. When
  /// true — including dose-driven `DOSE_OVER_UL_*` caution — the
  /// hero paints a caution cue beside the tier score line so an over-UL
  /// product with a high formulation score does not read as "Excellent".
  /// Null (the default) means no cue; BLOCKED / NOT_SCORED still route
  /// through [isBlocked] / [isNotScored] as before.
  final bool hasCatalogCaution;

  const PGHeroSection({
    super.key,
    required this.imageWidget,
    required this.productName,
    required this.brandName,
    this.servingsLabel,
    this.servingCountLabel,
    this.dosingSummary,
    this.trustTags = const [],
    this.score,
    this.qualityTier,
    this.isNotScored = false,
    this.isBlocked = false,
    this.lowCoverage = false,
    this.limitedAssessment = false,
    this.scoreConfidence,
    this.scoreConfidenceDrivers = const [],
    this.bottomBanner,
    this.hasCatalogCaution = false,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final parsedConfidenceLabel = catalogScoreConfidenceLabel(scoreConfidence);
    final confidenceLabel = limitedAssessment
        ? 'Limited'
        : parsedConfidenceLabel;
    final limitedAssessmentDetail = scoreConfidenceDrivers.isEmpty
        ? 'Limited assessment'
        : scoreConfidenceDrivers.join(' • ');
    final scoreDisplay = heroScoreDisplayFor(
      score: score,
      isBlocked: isBlocked,
      isNotScored: isNotScored,
      lowCoverage: lowCoverage,
      limitedAssessment: confidenceLabel == 'Limited',
    );
    final showTrustChips = heroShowsTrustChips(
      isBlocked: isBlocked,
      tagCount: trustTags.length,
    );
    final showCautionCue = heroShowsCautionCue(
      hasCatalogCaution: hasCatalogCaution,
      scoreDisplay: scoreDisplay,
    );

    // **Phase 11.7h.6 — Sean 2026-05-16 hero tightening.**
    // Reduce vertical real estate so verdict/fit/warning surface
    // faster. Changes:
    //   - Card padding 16 → 12 (saves ~8px top + bottom)
    //   - Image 96 → 80 (saves 16px row height)
    //   - Identity-row → score gap 16 → 12
    //   - PGScoreLine prominent=true (concise, decision-level score treatment)
    //   - bottomBanner gap 16 → 12
    final body = Container(
      padding: const EdgeInsets.all(V2Spacing.space12),
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity row: image + (name + subtitle + chips column).
          // Image dropped 96 → 80; saves a row of vertical space without
          // hurting product recognizability.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 80, height: 80, child: imageWidget),
              const SizedBox(width: V2Spacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      productName,
                      style: V2Typography.titleSm(color: context.v2.fg),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_hasSubtitle()) ...[
                      const SizedBox(height: 4),
                      _Subtitle(
                        brand: brandName,
                        servings: servingsLabel,
                        servingCount: servingCountLabel,
                        dose: dosingSummary,
                      ),
                    ],
                    if (showTrustChips) ...[
                      const SizedBox(height: V2Spacing.space8),
                      _TrustChipRow(tags: trustTags),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (scoreDisplay == HeroScoreDisplay.tierScore) ...[
            const SizedBox(height: V2Spacing.space12),
            // `compact: true` drops the verbose locked-tier description
            // line ("Well-formulated with good ingredient quality...") —
            // that copy was eating 2-3 lines of hero real estate. The
            // tier color + dot + "89/100 Excellent" headline carries
            // the verdict alone.
            //
            // A dose-driven CAUTION verdict can coincide with a high
            // formulation score, so a caution pill rides alongside the
            // tier line (see [heroShowsCautionCue]) — otherwise an over-UL
            // product reads as a plain "Excellent".
            // Frame the score as PRODUCT QUALITY — a distinct axis from the
            // personalized "for you" guidance in Profile Relevance below. The
            // dose-driven caution pill (product-level) rides alongside.
            Text(
              'Product quality',
              style: V2Typography.eyebrow(color: context.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space4),
            if (showCautionCue)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: PGScoreLine(
                      score: score!,
                      qualityTier: qualityTier,
                      prominent: true,
                    ),
                  ),
                  const SizedBox(width: V2Spacing.space8),
                  const _HeroCautionPill(),
                ],
              )
            else
              PGScoreLine(
                score: score!,
                qualityTier: qualityTier,
                prominent: true,
              ),
            // Routine confidence bands are internal diagnostics. Limited
            // assessments remain visible through the guarded branch below.
          ] else if (scoreDisplay == HeroScoreDisplay.limitedScore) ...[
            const SizedBox(height: V2Spacing.space12),
            Text(
              'Product quality',
              style: V2Typography.eyebrow(color: context.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '$score/100',
                  style: V2Typography.bodyMedium(color: context.v2.fg).copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (showCautionCue) ...[
                  const SizedBox(width: V2Spacing.space8),
                  const _HeroCautionPill(),
                ],
              ],
            ),
            const SizedBox(height: V2Spacing.space4),
            Text(
              limitedAssessmentDetail,
              style: V2Typography.caption(color: context.v2.fgMuted),
            ),
          ] else if (scoreDisplay == HeroScoreDisplay.notScored) ...[
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Product quality score unavailable.',
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
          ],
          if (bottomBanner != null) ...[
            const SizedBox(height: V2Spacing.space12),
            bottomBanner!,
          ],
        ],
      ),
    );

    if (disableAnimations) return body;

    return TweenAnimationBuilder<double>(
      duration: V2Motion.base,
      curve: V2Motion.smooth,
      tween: Tween<double>(begin: 0.0, end: 1.0),
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 8),
            child: child,
          ),
        );
      },
      child: body,
    );
  }

  bool _hasSubtitle() {
    final hasBrand = brandName.trim().isNotEmpty;
    final hasServings = servingsLabel != null && servingsLabel!.isNotEmpty;
    final hasServingCount =
        servingCountLabel != null && servingCountLabel!.isNotEmpty;
    final hasDose = dosingSummary != null && dosingSummary!.isNotEmpty;
    return hasBrand || hasServings || hasServingCount || hasDose;
  }
}

/// Subtitle line: `Brand · Servings × Form · Dosing` with cleanly
/// dropped segments. Caller controls the inputs; this widget never
/// renders orphan dots.
class _Subtitle extends StatelessWidget {
  final String brand;
  final String? servings;
  final String? servingCount;
  final String? dose;

  const _Subtitle({
    required this.brand,
    this.servings,
    this.servingCount,
    this.dose,
  });

  @override
  Widget build(BuildContext context) {
    final hasBrand = brand.trim().isNotEmpty;
    final hasServings = servings != null && servings!.isNotEmpty;
    final hasServingCount = servingCount != null && servingCount!.isNotEmpty;
    final hasDose = dose != null && dose!.isNotEmpty;
    if (!hasBrand && !hasServings && !hasServingCount && !hasDose) {
      return const SizedBox.shrink();
    }

    // Brand renders at medium weight (V2 caps at 500 — that's the
    // emphasis tier). Servings + dose stay at 400 muted. The result:
    // identity-first, metadata-second hierarchy.
    final spans = <InlineSpan>[];
    if (hasBrand) {
      spans.add(
        TextSpan(
          text: brand,
          style: V2Typography.bodyMedium(color: context.v2.fg),
        ),
      );
    }
    if (hasServings) {
      if (spans.isNotEmpty) {
        spans.add(_dotSpan(context));
      }
      spans.add(
        TextSpan(
          text: servings!,
          style: V2Typography.bodySm(color: context.v2.fgMuted),
        ),
      );
    }
    if (hasServingCount) {
      if (spans.isNotEmpty) {
        spans.add(_dotSpan(context));
      }
      spans.add(
        TextSpan(
          text: servingCount!,
          style: V2Typography.bodySm(color: context.v2.fgMuted),
        ),
      );
    }
    if (hasDose) {
      if (spans.isNotEmpty) {
        spans.add(_dotSpan(context));
      }
      spans.add(
        TextSpan(
          text: dose!,
          style: V2Typography.bodySm(color: context.v2.fgMuted),
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  TextSpan _dotSpan(BuildContext context) => TextSpan(
    text: ' · ',
    style: V2Typography.bodySm(color: context.v2.fgSubtle),
  );
}

/// Trust tag — outline pill, primary tone for certifications, green
/// for dietary signals. Mirrors `_HeroTrustChipOutline` from
///.
class PGTrustTag {
  final String label;
  final bool isCertification;

  const PGTrustTag({required this.label, required this.isCertification});
}

class _TrustChipRow extends StatelessWidget {
  final List<PGTrustTag> tags;
  const _TrustChipRow({required this.tags});

  @override
  Widget build(BuildContext context) {
    // **Phase 11.7h.7 — Sean 2026-05-16 chip reorganization.**
    // Previously: single Wrap with all tags mixed, capped at 4 visible.
    // Long lists (6+ tags on Thorne products) wrapped to 3+ messy rows.
    //
    // New layout: split into two grouped rows by tag type.
    //   Row 1 — Certifications (Third-Party Tested, Trusted Manufacturer,
    //           Organic) with verified icon + accent tone.
    //   Row 2 — Dietary tags (Gluten-Free, Dairy-Free, Soy-Free, Vegan,
    //           Non-GMO) compact text-only, green tone.
    // Each row caps at 4 visible + "+N more" overflow.
    final certs = tags.where((t) => t.isCertification).toList(growable: false);
    final dietary = tags
        .where((t) => !t.isCertification)
        .toList(growable: false);

    final children = <Widget>[];
    if (certs.isNotEmpty) {
      children.add(_TrustChipGroup(tags: certs));
    }
    if (dietary.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 4));
      }
      children.add(_TrustChipGroup(tags: dietary));
    }
    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// One chip group (either certifications or dietary tags). Caps at 4
/// visible; the rest collapse to a "+N more" overflow chip. Tighter
/// spacing than the previous all-tags Wrap so each row stays compact.
class _TrustChipGroup extends StatelessWidget {
  final List<PGTrustTag> tags;
  const _TrustChipGroup({required this.tags});

  @override
  Widget build(BuildContext context) {
    final visible = tags.take(4).toList(growable: false);
    final overflow = tags.length - visible.length;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final t in visible)
          _TrustChip(label: t.label, isCertification: t.isCertification),
        if (overflow > 0)
          _TrustChip(label: '+$overflow more', isCertification: false),
      ],
    );
  }
}

class _TrustChip extends StatelessWidget {
  final String label;
  final bool isCertification;

  const _TrustChip({required this.label, required this.isCertification});

  @override
  Widget build(BuildContext context) {
    // Certifications use accent (calmer than scoreExcellent on cream bg);
    // dietary tags use scoreExcellent green. Same intent as production.
    //
    // Verified-by-a-third-party certifications also carry a small
    // `verified_rounded` icon (Sean's call 2026-05-15) — the icon's
    // "blue check" semantic is meaningful here because something
    // external actually inspected and confirmed it. Dietary claims
    // (gluten free / vegan etc.) stay text-only — those are usually
    // self-declared by the manufacturer, and adding a check there
    // would imply independent verification we can't promise.
    final tone = isCertification ? context.v2.accent : context.v2.safe;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: tone.withValues(alpha: 0.55), width: 0.7),
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCertification) ...[
            Icon(Icons.verified_rounded, size: 11, color: tone),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: V2Typography.caption(color: tone).copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.05,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small caution pill painted beside the tier score line when the
/// pipeline verdict is CAUTION (see [heroShowsCautionCue]). Caution-toned
/// (amber) with a warning glyph so a dose-driven CAUTION reads as caution
/// next to an otherwise-green "85/100 Excellent" headline. Copy matches
/// the app's `Severity.caution` label ("Use caution").
class _HeroCautionPill extends StatelessWidget {
  const _HeroCautionPill();

  @override
  Widget build(BuildContext context) {
    final style = context.v2.tintedLabel(context.v2.caution, borderAlpha: 0.55);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.fill,
        border: Border.all(color: style.border, width: 0.7),
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 11,
            color: context.v2.caution,
          ),
          const SizedBox(width: 4),
          Text(
            'Use caution',
            style: V2Typography.caption(color: style.foreground).copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.05,
            ),
          ),
        ],
      ),
    );
  }
}
