import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// v2 mirror of `_HeaderSection` in
/// `lib/features/product_detail/product_detail_screen.dart:1250-1507`.
///
/// **Same structure preserved verbatim:**
/// - Identity row: 96pt product image + (name / subtitle / trust chips)
/// - Product name: max 3 lines, ellipsis on overflow
/// - Subtitle: `Brand · 60 Capsules · 1 capsule daily` (drops segments
///   cleanly when missing)
/// - Trust chips: outline pills (primary tone for certifications, green
///   for dietary tags), max 4 visible + `+N more` overflow chip
/// - ScoreLine (suppressed when `isBlocked` — banner replaces it; or
///   "Not enough verified data to score" when `isNotScored`)
/// - 240ms entrance fade + 8pt translate (skipped under reduce-motion)
///
/// Wraps the whole hero in a v2 elevated card (cream surface + outline +
/// sm shadow). Production used `PGCard(elevated)` — same intent, v2 token
/// values.
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

  /// User-facing dosing string ("1 capsule daily"). Empty/null hides.
  final String? dosingSummary;

  /// Trust signals — certifications (primary tone) + dietary tags
  /// (green tone). Max 4 visible inline, rest collapsed into `+N more`.
  final List<PGTrustTag> trustTags;

  /// 0–100 product score. Null when [isNotScored]. Drives the
  /// [PGScoreLine] underneath.
  final int? score;

  /// True when the product has insufficient verified data to score.
  /// Renders "Not enough verified data to score." in place of the
  /// score line.
  final bool isNotScored;

  /// True when the product is BLOCKED — suppresses the score line
  /// entirely. Production renders a separate banner; pass that as
  /// [bottomBanner] to keep the layout intact.
  final bool isBlocked;

  /// Banner widget rendered beneath the score line (used for the
  /// production Blocked / Avoid banners). Null skips the slot.
  final Widget? bottomBanner;

  const PGHeroSection({
    super.key,
    required this.imageWidget,
    required this.productName,
    required this.brandName,
    this.servingsLabel,
    this.dosingSummary,
    this.trustTags = const [],
    this.score,
    this.isNotScored = false,
    this.isBlocked = false,
    this.bottomBanner,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final body = Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity row: image + (name + subtitle + chips column)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 96, height: 96, child: imageWidget),
              const SizedBox(width: V2Spacing.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      productName,
                      style: V2Typography.titleSm(color: V2Colors.fg),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_hasSubtitle()) ...[
                      const SizedBox(height: 4),
                      _Subtitle(
                        brand: brandName,
                        servings: servingsLabel,
                        dose: dosingSummary,
                      ),
                    ],
                    if (trustTags.isNotEmpty) ...[
                      const SizedBox(height: V2Spacing.space8),
                      _TrustChipRow(tags: trustTags),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (score != null && !isBlocked && !isNotScored) ...[
            const SizedBox(height: V2Spacing.space16),
            PGScoreLine(score: score!),
          ] else if (isNotScored) ...[
            const SizedBox(height: V2Spacing.space12),
            Text(
              'Not enough verified data to score.',
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
          ],
          if (bottomBanner != null) ...[
            const SizedBox(height: V2Spacing.space16),
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
    final hasDose = dosingSummary != null && dosingSummary!.isNotEmpty;
    return hasBrand || hasServings || hasDose;
  }
}

/// Subtitle line: `Brand · Servings × Form · Dosing` with cleanly
/// dropped segments. Caller controls the inputs; this widget never
/// renders orphan dots.
class _Subtitle extends StatelessWidget {
  final String brand;
  final String? servings;
  final String? dose;

  const _Subtitle({required this.brand, this.servings, this.dose});

  @override
  Widget build(BuildContext context) {
    final hasBrand = brand.trim().isNotEmpty;
    final hasServings = servings != null && servings!.isNotEmpty;
    final hasDose = dose != null && dose!.isNotEmpty;
    if (!hasBrand && !hasServings && !hasDose) {
      return const SizedBox.shrink();
    }

    // Brand renders at medium weight (V2 caps at 500 — that's the
    // emphasis tier). Servings + dose stay at 400 muted. The result:
    // identity-first, metadata-second hierarchy.
    final spans = <InlineSpan>[];
    if (hasBrand) {
      spans.add(TextSpan(
        text: brand,
        style: V2Typography.bodyMedium(color: V2Colors.fg),
      ));
    }
    if (hasServings) {
      if (spans.isNotEmpty) {
        spans.add(_dotSpan());
      }
      spans.add(TextSpan(
        text: servings!,
        style: V2Typography.bodySm(color: V2Colors.fgMuted),
      ));
    }
    if (hasDose) {
      if (spans.isNotEmpty) {
        spans.add(_dotSpan());
      }
      spans.add(TextSpan(
        text: dose!,
        style: V2Typography.bodySm(color: V2Colors.fgMuted),
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  TextSpan _dotSpan() => TextSpan(
        text: ' · ',
        style: V2Typography.bodySm(color: V2Colors.fgSubtle),
      );
}

/// Trust tag — outline pill, primary tone for certifications, green
/// for dietary signals. Mirrors `_HeroTrustChipOutline` from
/// product_detail_screen.dart:1562.
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
    final visible = tags.take(4).toList(growable: false);
    final overflow = tags.length - visible.length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
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
    final tone = isCertification ? V2Colors.accent : V2Colors.safe;
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
