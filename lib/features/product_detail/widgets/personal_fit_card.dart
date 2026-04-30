// "Personal Fit" card — Section 2 of the product detail page.
//
// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T12.
//
// Sean's locked design contract:
//
//   ┌──────────────────────────────────────┐
//   │ 🛡 Good match for your sleep goal  ✎ │
//   │                                      │
//   │ • Magnesium supports your blood      │
//   │   pressure goal                      │
//   │ • No conflicts with your medications │
//   └──────────────────────────────────────┘
//
//   Rules
//     - MUST be causal (no vague language)
//     - Max 2 bullet points
//     - Pencil icon → opens profile edit
//
// The card replaces the pre-T12 `ForYouSection` (which had context
// chips, an alert list, a verdict row, and a "Why this fits you"
// expander). The new card is much quieter: one icon + headline, two
// causal bullets, an edit affordance. Other functionality moved:
//   - Context chips → not surfaced (removed from IA per spec)
//   - Alerts list → T13 Alert Summary card (count + scroll-to)
//   - "Why this fits you" expander → bullets are inline, no expander
//
// Bullet generation priority:
//   1. Positive-profile bullets via T3 Path A's
//      `generatePositiveProfileBullets(...)`. These are causal by
//      construction ("Magnesium supports your blood pressure goal")
//      and reference the user's profile explicitly.
//   2. Fallback to FitScoreResult.reasons (engine-generated, e.g.
//      "Supports your sleep quality goal.")
//   3. Cap at 2.
// If neither produces any bullets the card renders the headline alone.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';
import 'package:pharmaguide/services/warnings/condition_thresholds.dart';

class PersonalFitCard extends ConsumerWidget {
  /// Risk-gated fit display state. Drives headline copy + tone +
  /// icon. Controlled by `computeFitDisplay(...)` upstream — see
  /// `lib/services/fit_score/fit_display.dart`.
  final FitDisplay fit;

  /// User-friendly active-ingredient names from the product's detail
  /// blob (e.g., `['Vitamin D', 'Magnesium', 'Folate']`). The bullet
  /// generator canonicalizes internally — caller passes raw names.
  final List<String> ingredientNames;

  /// FitScoreResult.reasons — engine-generated causal sentences used
  /// as bullet fallback when positive-profile bullets don't fill 2.
  /// Empty list is fine (card just shows the headline).
  final List<String> fitReasons;

  /// Goal label for the headline copy (e.g., `"sleep"` →
  /// `"Strong match for your sleep goal"`). Null falls back to
  /// `"your profile"`. Same convention as the prior `ForYouSection`.
  final String? topGoalLabel;

  /// Callback fired when the user taps the edit pencil. Caller
  /// wires to navigation (e.g., `context.push(Routes.profileSetup)`).
  /// T2 fix lives at the call site, not here.
  final VoidCallback onEditProfile;

  const PersonalFitCard({
    super.key,
    required this.fit,
    required this.ingredientNames,
    required this.fitReasons,
    required this.onEditProfile,
    this.topGoalLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = ref.watch(profileProvider);

    // T16.1 (2026-04-30) — dedup hero ↔ PersonalFit. FitHidden fires
    // EXACTLY when verdict is contraindicated/avoid (see
    // fit_display.dart:127-128). The hero card already surfaces a
    // BlockedBanner or "Avoid — relevant to your profile" banner for
    // those severities; rendering "Not recommended for your profile"
    // again here is redundant noise. Drop the card entirely; the hero
    // is the message. FitNotRecommended (low fit but safe) stays —
    // it's the only surface flagging a poor fit when the hero is
    // quiet.
    if (fit is FitHidden) return const SizedBox.shrink();

    final headlineCopy = _headlineFor(fit, topGoalLabel);
    final tone = _toneFor(fit);
    final icon = _iconFor(fit);
    final bullets = _bulletsFor(fit, profile.conditions);

    return PGCard(
      variant: PGCardVariant.elevated,
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Headline row: icon + headline + edit pencil
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: tone),
              const SizedBox(width: AppTheme.space8),
              Expanded(
                child: Text(
                  headlineCopy,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: scheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppTheme.space8),
              // Edit pencil — small icon button, calls onEditProfile.
              // T2 wired the navigation (Routes.profileSetup); the card
              // just fires the callback.
              PGPressable(
                onTap: onEditProfile,
                pressedScale: 0.92,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (bullets.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space12),
            for (final bullet in bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _CausalBullet(text: bullet),
              ),
          ],
        ],
      ),
    );
  }

  /// Build up to 2 causal bullets. Priority:
  ///   1. Positive-profile bullets (T3 Path A)
  ///   2. fitReasons fallback (FitScoreResult.reasons)
  /// Hidden / NotRecommended states deliberately render no positive
  /// bullets — saying "Magnesium supports your blood pressure goal"
  /// next to "Not recommended for your profile" is incoherent.
  List<String> _bulletsFor(FitDisplay fit, List<String> userConditions) {
    if (fit is FitHidden ||
        fit is FitNotRecommended ||
        fit is FitIncomplete) {
      // For these states, bullets would either be inappropriate
      // (Hidden/NotRecommended) or premature (Incomplete profile —
      // the math hasn't run). Headline alone communicates the state.
      return const [];
    }

    final positives = generatePositiveProfileBullets(
      ingredientNames: ingredientNames,
      userConditionIds: userConditions,
    );

    final bullets = <String>[];
    bullets.addAll(positives);
    if (bullets.length < 2) {
      // Top up from engine-generated reasons. The reasons are
      // already causal sentences (the FitScore engine produces them
      // by following the goal-cluster logic).
      for (final reason in fitReasons) {
        if (bullets.length >= 2) break;
        final clean = _cleanReason(reason);
        if (clean.isEmpty) continue;
        if (bullets.contains(clean)) continue; // dedupe
        bullets.add(clean);
      }
    }
    return bullets.take(2).toList(growable: false);
  }

  /// Strip a trailing period from engine-generated reasons so they
  /// match the no-trailing-period bullet style (mixing the two looks
  /// inconsistent). Returns empty string for reasons that should be
  /// dropped entirely (see [_isConditionWarningReason]).
  String _cleanReason(String reason) {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) return '';
    // T12.1 (2026-04-29 PM live walkthrough fix) — drop reasons that
    // duplicate condition-warning surfaces gated by T4. Sean caught
    // "Diabetes: monitor from Vitamin D" leaking through the fit
    // engine even though Vit D × Diabetes is positive (T3) and the
    // warnings list is suppressed (T4). The fit engine generates
    // reasons from the same source data via a separate code path; we
    // filter them at this surface.
    if (_isConditionWarningReason(trimmed)) return '';
    if (trimmed.endsWith('.')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}

/// Lowercase user-friendly condition labels — used to identify reason
/// strings that start with a condition prefix (e.g., `"Diabetes:
/// monitor from Vitamin D"`). When these prefixes appear, the reason
/// is a per-condition warning leak and should be suppressed —
/// reflecting the same T4 + T3 gating that filtered the warnings list.
const Set<String> _conditionLabelPrefixes = {
  'pregnancy',
  'lactation',
  'breastfeeding',
  'ttc',
  'trying to conceive',
  'pre-conception',
  'diabetes',
  'hypertension',
  'high blood pressure',
  'kidney disease',
  'liver disease',
  'thyroid',
  'thyroid disorder',
  'autoimmune',
  'seizure',
  'seizure disorder',
  'high cholesterol',
  'bleeding disorders',
  'heart disease',
  'surgery',
  'upcoming surgery',
};

/// Returns true when [reason] is a per-condition warning leak from
/// the fit engine — pattern: `"<Condition Label>: <warning text>"`.
/// Filters fitReasons fallback to drop these so the Personal Fit
/// card doesn't surface the false positives we suppressed at T4.
bool _isConditionWarningReason(String reason) {
  final colonIdx = reason.indexOf(':');
  if (colonIdx <= 0 || colonIdx > 30) return false;
  final prefix = reason.substring(0, colonIdx).trim().toLowerCase();
  return _conditionLabelPrefixes.contains(prefix);
}

// ─── Headline copy / tone / icon mapping ─────────────────────────────

String _headlineFor(FitDisplay fit, String? topGoalLabel) {
  final goalSuffix = (topGoalLabel != null && topGoalLabel.trim().isNotEmpty)
      ? 'your ${topGoalLabel.trim()} goal'
      : 'your profile';
  return switch (fit) {
    FitStrongMatch() => 'Strong match for $goalSuffix',
    FitGoodMatch() => 'Good match for $goalSuffix',
    FitLimitedFit() => 'Limited fit for $goalSuffix',
    FitNotRecommended() || FitHidden() => 'Not recommended for your profile',
    FitIncomplete() => 'Add your profile to personalize',
  };
}

Color _toneFor(FitDisplay fit) => switch (fit) {
  FitStrongMatch() => AppTheme.scoreExceptional,
  FitGoodMatch() => AppTheme.scoreExcellent,
  FitLimitedFit() => AppTheme.scoreFair,
  FitNotRecommended() || FitHidden() => AppTheme.scoreLow,
  FitIncomplete() => AppTheme.insufficientData,
};

IconData _iconFor(FitDisplay fit) => switch (fit) {
  // Shield icon for positive-leaning states — matches Sean's reference.
  FitStrongMatch() || FitGoodMatch() => Icons.shield_outlined,
  // Caution chevron for limited fit — softer than ⚠ which we reserve
  // for the alert summary card (T13).
  FitLimitedFit() => Icons.error_outline_rounded,
  // Block icon for risk-gated / not-recommended states.
  FitNotRecommended() || FitHidden() => Icons.do_not_disturb_alt_outlined,
  // Profile icon for incomplete state — the affordance is "complete
  // your profile to get a real assessment."
  FitIncomplete() => Icons.person_outline_rounded,
};

/// Single causal bullet. Visually quiet — the dot is muted so the
/// row reads as a supporting line, not a callout.
class _CausalBullet extends StatelessWidget {
  final String text;
  const _CausalBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
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
        const SizedBox(width: AppTheme.space8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
