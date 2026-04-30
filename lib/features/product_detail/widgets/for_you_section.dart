// "For You" merged block — Section 2 of the Trust & IA product detail.
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.2.
//
// Consolidates four signals that were scattered across the pre-T1.x
// hero into a single Section-2 card:
//
//   1. Context chips         — what the personalization is keyed on
//                              (the user's goals + conditions + meds)
//   2. Verdict row           — ✅/🟡/❌ + headline ("Strong match for
//                              your sleep goal" / "Not recommended for
//                              your profile" / etc.)
//   3. 1-line key explanation — short subtitle expanding the verdict
//   4. Alerts                — priority-sorted contraindicated/avoid/
//                              caution warnings (monitor and below
//                              filtered out — they're too quiet for
//                              this section)
//   5. "Why this fits you"   — expandable 4-bullet deterministic
//                              explanation pulled from the FitScore
//                              reasons + matched goals
//
// Risk-gating is the hard rule: when the worst applicable severity is
// Avoid or Contraindicated, the Personal Fit number is hidden entirely
// (T1.3 returns FitHidden) — even if the underlying math came back
// high. "Avoid + 88/100" is the mixed-signal failure mode the whole
// initiative is designed to prevent.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';

/// Section 2 ("For You") of the product detail screen.
///
/// Self-contained widget: pulls the user's profile from
/// [profileProvider], applies risk-gated Fit display logic via
/// [computeFitDisplay], and consolidates personalization signals into
/// one card.
///
/// Caller responsibilities:
///   * Pass the resolved [fitResult] (null while async is in flight or
///     when profile is too sparse for a meaningful score)
///   * Pass the full personalized + profile-filtered [warnings] list;
///     this widget filters to the priority tiers it cares about
///   * Pass the worst applicable [maxSeverity] across the product
///     (stack interactions, banned/recall flags, etc.) — drives the
///     risk-gate
///   * Optionally pass [topGoalLabel] (e.g. `"sleep"`) for the
///     verdict headline copy. When null, the headline degrades to
///     "your profile" instead of naming the specific goal.
class ForYouSection extends ConsumerWidget {
  final FitScoreResult? fitResult;
  final List<InteractionWarning> warnings;
  final Severity maxSeverity;

  /// User-facing label of the matched top goal (e.g. `"sleep"`,
  /// `"energy"`, `"immunity"`). When non-null, the verdict headline
  /// reads "Strong match for your `<topGoalLabel>` goal" — the specific
  /// callout users react best to. When null, falls back to "your
  /// profile".
  final String? topGoalLabel;

  const ForYouSection({
    super.key,
    required this.fitResult,
    required this.warnings,
    required this.maxSeverity,
    this.topGoalLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    // Allergens count as a personalization signal — a peanut-allergic
    // user looking at a peanut-containing supplement gets a real
    // warning, even if no goals/conditions/meds are set. Without this,
    // an allergens-only profile would render the empty-state affordance
    // and miss the alerts list entirely.
    final hasProfile =
        profile.goals.isNotEmpty ||
        profile.conditions.isNotEmpty ||
        profile.drugClasses.isNotEmpty ||
        profile.allergens.isNotEmpty;

    // Empty-profile state — render the affordance, no other content.
    if (!hasProfile) {
      return _ForYouEmpty(onTap: () => _openProfile(context));
    }

    // Compute the Fit display state via T1.3 (risk-gated).
    final fitDisplay = fitResult != null
        ? computeFitDisplay(verdict: maxSeverity, fitResult: fitResult!)
        : const FitIncomplete();

    // Filter alerts to the tiers Section 2 surfaces. Monitor + safe +
    // informational + recommended are too quiet for this section —
    // they live in deeper sections (Section 7 / Section 8) when they
    // matter at all.
    final filteredWarnings = _filterPrioritized(warnings);

    return PGCard(
      variant: PGCardVariant.plain,
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(onEdit: () => _openProfile(context)),
          if (_buildContextChips(profile).isNotEmpty) ...[
            const SizedBox(height: AppTheme.space12),
            _ContextChips(chips: _buildContextChips(profile)),
          ],
          const SizedBox(height: AppTheme.space16),
          _VerdictRow(display: fitDisplay, topGoalLabel: topGoalLabel),
          if (filteredWarnings.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space12),
            _AlertsList(warnings: filteredWarnings),
          ],
          if (fitResult != null && fitResult!.reasons.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space12),
            _WhyThisFitsExpander(reasons: fitResult!.reasons),
          ],
        ],
      ),
    );
  }

  void _openProfile(BuildContext context) {
    // T2 (2026-04-29) — was `Routes.profile`, which is the SettingsScreen
    // shell-route tab inside the bottom nav. Pushing a shell-tab path
    // from a non-shell screen via `context.push` no-ops or throws
    // depending on the GoRouter version, hence the user-reported "edit
    // does nothing / crashes." Every other edit-profile call site in
    // the app (settings, home completeness card, fit-score sheet,
    // stack screen, product_detail's incomplete-profile CTA) routes to
    // `Routes.profileSetup` → `ProfileSetupScreen`. This was the lone
    // outlier with the wrong constant.
    context.push(Routes.profileSetup);
  }

  static List<String> _buildContextChips(ProfileState profile) {
    final chips = <String>[
      ...profile.goals.take(2),
      ...profile.conditions.take(2),
      ...profile.drugClasses.take(2),
    ];
    return chips.take(4).toList(growable: false);
  }

  /// Severity-priority sort: contraindicated > avoid > caution.
  /// Anything below caution (monitor, informational, safe) is dropped.
  static List<InteractionWarning> _filterPrioritized(
    List<InteractionWarning> all,
  ) {
    const allow = {Severity.contraindicated, Severity.avoid, Severity.caution};
    final filtered = all.where((w) => allow.contains(w.severity)).toList();
    filtered.sort((a, b) => b.severity.weight.compareTo(a.severity.weight));
    return filtered;
  }
}

// ---------------------------------------------------------------------------
// Section header — title + edit chip affordance
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final VoidCallback onEdit;
  const _SectionHeader({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            'For You',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        PGPressable(
          onTap: onEdit,
          pressedScale: 0.94,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Edit',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Context chips — small outline pills naming the user's profile signals
// ---------------------------------------------------------------------------

class _ContextChips extends StatelessWidget {
  final List<String> chips;
  const _ContextChips({required this.chips});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips
          .map(
            (c) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                border: Border.all(color: scheme.outlineVariant, width: 0.8),
              ),
              child: Text(
                _humanize(c),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  /// snake_case → "Snake Case". Pipeline-shape-tolerant: passes
  /// through anything already title-cased.
  static String _humanize(String raw) {
    if (raw.isEmpty) return raw;
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

// ---------------------------------------------------------------------------
// Verdict row — emoji + headline (and Personal Fit number when shown)
// ---------------------------------------------------------------------------

class _VerdictRow extends StatelessWidget {
  final FitDisplay display;
  final String? topGoalLabel;

  const _VerdictRow({required this.display, this.topGoalLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (emoji, headline, tone) = _composeVerdict(display);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: AppTheme.space12),
        Expanded(
          child: Text(
            headline,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: tone,
            ),
          ),
        ),
      ],
    );
  }

  (String emoji, String headline, Color tone) _composeVerdict(
    FitDisplay display,
  ) {
    final goalSuffix = topGoalLabel != null && topGoalLabel!.trim().isNotEmpty
        ? 'your ${topGoalLabel!.trim()} goal'
        : 'your profile';
    return switch (display) {
      FitStrongMatch() => (
        '✅',
        'Strong match for $goalSuffix',
        AppTheme.scoreExceptional,
      ),
      FitGoodMatch() => (
        '✅',
        'Good match for $goalSuffix',
        AppTheme.scoreExcellent,
      ),
      FitLimitedFit() => (
        '🟡',
        'Limited fit for $goalSuffix',
        AppTheme.scoreFair,
      ),
      FitNotRecommended() => (
        '❌',
        'Not recommended for your profile',
        AppTheme.scoreLow,
      ),
      FitHidden() => (
        '❌',
        'Not recommended for your profile',
        AppTheme.scoreLow,
      ),
      FitIncomplete() => (
        'ℹ️',
        'Add more details to personalize',
        AppTheme.insufficientData,
      ),
    };
  }
}

// ---------------------------------------------------------------------------
// Alerts list — priority-sorted contraindicated/avoid/caution rows
// ---------------------------------------------------------------------------

class _AlertsList extends StatelessWidget {
  final List<InteractionWarning> warnings;
  const _AlertsList({required this.warnings});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final w in warnings) ...[
          _AlertRow(warning: w),
          if (w != warnings.last) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _AlertRow extends StatelessWidget {
  final InteractionWarning warning;
  const _AlertRow({required this.warning});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = warning.severity.color;
    final headline = (warning.alertHeadline?.trim().isNotEmpty ?? false)
        ? warning.alertHeadline!.trim()
        : warning.title;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space12,
        vertical: AppTheme.space8,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: tone.withValues(alpha: 0.2), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(_iconFor(warning.severity), size: 16, color: tone),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  warning.severity.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  headline,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(Severity s) => switch (s) {
    Severity.contraindicated => Icons.do_not_disturb_on_outlined,
    Severity.avoid => Icons.error_outline_rounded,
    Severity.caution => Icons.warning_amber_rounded,
    _ => Icons.info_outline_rounded,
  };
}

// ---------------------------------------------------------------------------
// "Why this fits you" expander — 4-bullet deterministic explanation
// ---------------------------------------------------------------------------

class _WhyThisFitsExpander extends StatefulWidget {
  final List<String> reasons;
  const _WhyThisFitsExpander({required this.reasons});

  @override
  State<_WhyThisFitsExpander> createState() => _WhyThisFitsExpanderState();
}

class _WhyThisFitsExpanderState extends State<_WhyThisFitsExpander> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Cap at 4 bullets per spec — the FitScore reasons list can carry
    // more from the various E1/E2a/E2b/E2c sub-signals; we surface the
    // top 4 to keep the section scannable.
    final bullets = widget.reasons.take(4).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PGPressable(
          onTap: () => setState(() => _expanded = !_expanded),
          pressedScale: 0.98,
          child: Row(
            children: [
              Text(
                'Why this fits you',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final b in bullets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: scheme.onSurfaceVariant,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  b,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurface,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty-profile state — single affordance pointing at profile setup
// ---------------------------------------------------------------------------

class _ForYouEmpty extends StatelessWidget {
  final VoidCallback onTap;
  const _ForYouEmpty({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PGCard(
      variant: PGCardVariant.plain,
      onTap: onTap,
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Row(
        children: [
          Icon(Icons.person_outline_rounded, size: 22, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'For You',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Add your profile to personalize',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: scheme.primary,
          ),
        ],
      ),
    );
  }
}
