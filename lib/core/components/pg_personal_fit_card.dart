import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';

/// Personal fit card.
///
/// Structure:
/// - Headline row: tone-colored shield/lock icon + headline copy + edit
///   pencil (round surfaceContainer button)
/// - 0–2 causal bullet points beneath when bullets are non-empty
/// - `FitHidden` returns `SizedBox.shrink()` — hero already carries the
///   message, rendering this would be noise (dedup rule from T16.1)
///
/// This widget is pure presentation. The screen composes positive-
/// profile bullets and fitReasons fallback, then passes the final list.
class PGPersonalFitCard extends StatelessWidget {
  /// Risk-gated fit display state from
  /// `lib/services/fit_score/fit_display.dart`. Drives icon, tone,
  /// headline copy.
  final FitDisplay fit;

  /// Headline string composed at the screen level using the same
  /// Personal-fit headline composed by the section helper.
  final String headline;

  /// 0–2 causal bullet sentences. Caller composes from emitted beneficial
  /// profile warnings plus fitReasons fallback. Empty = headline-only card.
  final List<String> bullets;

  /// Fired when the user taps the edit pencil.
  final VoidCallback onEditProfile;

  const PGPersonalFitCard({
    super.key,
    required this.fit,
    required this.headline,
    required this.bullets,
    required this.onEditProfile,
  });

  @override
  Widget build(BuildContext context) {
    // T16.1 dedup rule from production: FitHidden = hero is the message,
    // this card would be noise. Skip entirely.
    if (fit is FitHidden) return const SizedBox.shrink();

    final tone = _toneFor(fit);
    final icon = _iconFor(fit);

    return Container(
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
          // v2 editorial eyebrow — anchors the card as a personalization
          // section. Production renders the card with no label (icon +
          // headline carry the identity). v2 adds the mono-caps eyebrow
          // for consistency with the Review Before Use card title and
          // the website's editorial pattern. Pure visual addition — no
          // semantic change.
          const PGEyebrow('Profile Relevance'),
          const SizedBox(height: V2Spacing.space8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: tone),
              const SizedBox(width: V2Spacing.space8),
              Expanded(
                child: Text(
                  headline,
                  // 18pt (bodyXl) — drop from titleSm (20pt) per Sean's
                  // feedback: 20pt was too loud with the icon + edit
                  // pencil eating horizontal room. 18pt lets the 2-line
                  // wrap actually breathe.
                  style: V2Typography.bodyXl(
                    color: V2Colors.fg,
                  ).copyWith(fontWeight: FontWeight.w500, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: V2Spacing.space8),
              _EditPencil(onTap: onEditProfile),
            ],
          ),
          if (bullets.isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space12),
            for (final b in bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _CausalBullet(text: b),
              ),
          ],
        ],
      ),
    );
  }

  /// Tone color per fit state. Mirrors production `_toneFor(fit)`.
  static Color _toneFor(FitDisplay fit) {
    return switch (fit) {
      FitStrongMatch() => V2Colors.safe,
      FitGoodMatch() => V2Colors.safe,
      FitLimitedFit() => V2Colors.monitor,
      FitNotRecommended() => V2Colors.avoid,
      FitHidden() => V2Colors.contraindicated,
      FitIncomplete() => V2Colors.accent,
    };
  }

  /// Icon per fit state. Strong/good → shield; limited → info; not
  /// recommended → exclamation; incomplete → person-add.
  static IconData _iconFor(FitDisplay fit) {
    return switch (fit) {
      FitStrongMatch() => Icons.shield_outlined,
      FitGoodMatch() => Icons.shield_outlined,
      FitLimitedFit() => Icons.info_outline_rounded,
      FitNotRecommended() => Icons.warning_amber_rounded,
      FitHidden() => Icons.block_rounded,
      FitIncomplete() => Icons.person_add_alt_1_outlined,
    };
  }
}

class _EditPencil extends StatelessWidget {
  final VoidCallback onTap;
  const _EditPencil({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(
            color: V2Colors.accentTint,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.edit_outlined,
            size: 16,
            color: V2Colors.accent,
          ),
        ),
      ),
    );
  }
}

class _CausalBullet extends StatelessWidget {
  final String text;
  const _CausalBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // 5pt top inset aligns the bullet with the cap-height of the
          // smaller 14pt body text.
          padding: const EdgeInsets.only(top: 5, right: V2Spacing.space8),
          child: Container(
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: V2Colors.fgMuted,
              shape: BoxShape.circle,
            ),
          ),
        ),
        Expanded(
          child: Text(
            // 14pt (bodySm) — Sean's feedback: 16pt body wrapped to two
            // lines on a short bullet. 14pt fits typical causal bullets
            // ("Magnesium supports your sleep goal") on a single line
            // without sacrificing legibility.
            text,
            style: V2Typography.bodySm(color: V2Colors.fg),
          ),
        ),
      ],
    );
  }
}

/// Helper to keep callers from importing severity directly when they
/// just need the verdict-to-tone routing for a FitHidden — the
/// `FitHidden.verdict` is a [Severity], and production callers may
/// want it in their banner copy.
extension PGFitDisplayHidden on FitDisplay {
  /// True when this fit is in the hidden state. Convenience for
  /// callers composing the screen ("if hidden, skip the card").
  bool get isHidden => this is FitHidden;

  /// The severity that triggered the hide. Null for non-FitHidden.
  Severity? get hideVerdict {
    final f = this;
    return f is FitHidden ? f.verdict : null;
  }
}
