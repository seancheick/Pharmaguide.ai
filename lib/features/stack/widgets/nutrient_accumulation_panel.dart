// NutrientAccumulationPanel — top-of-stack-screen card showing every
// nutrient summed across the user's stack against RDA/UL benchmarks.
//
// This is the visual surface for the M1 medical-grade gap fix:
// per-product UL checks miss accumulation across multiple products.
//
// States:
//   * loading       → small CircularProgressIndicator
//   * error         → an explicit "couldn't total" notice. NOT a silent
//                     shrink: this is the upper-limit surface, so an empty
//                     space reads as "no UL concerns" — the one thing a
//                     failed check cannot promise.
//   * partial       → totals render with a hedge; a skipped stack item makes
//                     the sum an under-report, so a UL comparison drawn from
//                     it can read "within limit" when the truth is unknown.
//   * empty stack   → hidden entirely (handled by SizedBox.shrink)
//   * UL benchmarks → expanded inline list, with warnings first
//   * intake targets without a UL → compact list
//   * no benchmark  → collapsed label-amount list
//
// Safety-limit rows are deliberately not collapsible. The whole point
// is that the most dangerous nutrient is visible the moment the user
// opens the screen. Lower-risk benchmark groups stay compact.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/widgets/nutrient_progress_bar.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

class NutrientAccumulationPanel extends ConsumerWidget {
  const NutrientAccumulationPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncStatuses = ref.watch(stackNutrientStatusesProvider);

    return asyncStatuses.when(
      loading: () => const _PanelShell(
        child: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (_, __) => const _PanelShell(child: _NutrientTotalsUnavailable()),
      data: (result) {
        // Nothing to total AND nothing was skipped — stay out of the way.
        if (result.isEmpty && !result.incomplete) {
          return const SizedBox.shrink();
        }
        if (result.isEmpty) {
          return const _PanelShell(child: _NutrientTotalsUnavailable());
        }
        return _PanelShell(
          child: _PanelBody(
            statuses: result.statuses,
            incomplete: result.incomplete,
          ),
        );
      },
    );
  }
}

/// Shown when the totals could not be built, or when every stack item was
/// skipped. Absence would read as "no upper-limit concerns"; this says what
/// actually happened instead.
class _NutrientTotalsUnavailable extends StatelessWidget {
  const _NutrientTotalsUnavailable();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('nutrient-totals-unavailable'),
      padding: const EdgeInsets.all(V2Spacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nutrient totals unavailable',
            style: V2Typography.titleSm(color: context.v2.fg),
          ),
          const SizedBox(height: V2Spacing.space4),
          Text(
            "We couldn't add up the nutrients in your stack right now. This "
            'is not an all-clear — upper-limit checks did not run.',
            style: V2Typography.bodySm(color: context.v2.fgMuted),
          ),
        ],
      ),
    );
  }
}

/// Shown above the totals when at least one stack item was skipped.
class _PartialTotalsNotice extends StatelessWidget {
  const _PartialTotalsNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('nutrient-totals-partial-notice'),
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space16,
        0,
        V2Spacing.space16,
        V2Spacing.space8,
      ),
      child: Text(
        'Some items in your stack could not be included, so these totals are '
        'lower than your full intake.',
        style: V2Typography.bodySm(color: context.v2.fgMuted),
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('nutrient-accumulation-card'),
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
      ),
      child: child,
    );
  }
}

class _PanelBody extends StatefulWidget {
  const _PanelBody({required this.statuses, this.incomplete = false});

  final List<NutrientStatus> statuses;

  /// True when a stack item was skipped, making [statuses] a partial sum.
  final bool incomplete;

  @override
  State<_PanelBody> createState() => _PanelBodyState();
}

class _PanelBodyState extends State<_PanelBody> {
  /// Keeps intake-target rows useful without letting the stack screen
  /// become needlessly long.
  static const _targetCollapsedLimit = 6;

  bool _targetsExpanded = false;
  bool _labelAmountsExpanded = false;

  /// Rank a nutrient by how close it is to its risk ceiling, so the
  /// panel surfaces the most clinically relevant totals first.
  ///
  /// Priority: %UL (strongest signal) → %RDA (if no UL) → 0 (no data).
  /// A nutrient at 150% UL ranks above one at 300% RDA because UL
  /// overages carry toxicity risk while RDA overages usually don't.
  static double _riskScore(NutrientStatus s) {
    final ul = s.pctOfUl;
    if (ul != null) return ul + 10000; // UL-based entries always first
    final rda = s.pctOfRda;
    if (rda != null) return rda;
    return -1; // unranked
  }

  static bool _hasUpperLimit(NutrientStatus status) =>
      status.ul != null || status.pctOfUl != null || status.shouldWarn;

  static int _compareSafetyLimits(NutrientStatus a, NutrientStatus b) {
    if (a.shouldWarn != b.shouldWarn) {
      return a.shouldWarn ? -1 : 1;
    }
    return _riskScore(b).compareTo(_riskScore(a));
  }

  @override
  Widget build(BuildContext context) {
    final safetyLimits = widget.statuses.where(_hasUpperLimit).toList()
      ..sort(_compareSafetyLimits);
    final intakeTargets =
        widget.statuses
            .where((s) => !_hasUpperLimit(s) && s.pctOfRda != null)
            .toList()
          ..sort((a, b) => (b.pctOfRda ?? -1).compareTo(a.pctOfRda ?? -1));
    final labelAmounts =
        widget.statuses
            .where((s) => !_hasUpperLimit(s) && s.pctOfRda == null)
            .toList()
          ..sort((a, b) => a.total.displayName.compareTo(b.total.displayName));

    final hasMoreTargets = intakeTargets.length > _targetCollapsedLimit;
    final shownTargets = _targetsExpanded
        ? intakeTargets
        : intakeTargets.take(_targetCollapsedLimit).toList();
    final warningCount = widget.statuses.where((s) => s.shouldWarn).length;

    return Padding(
      padding: const EdgeInsets.all(V2Spacing.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            totalNutrients: widget.statuses.length,
            warningCount: warningCount,
          ),
          Divider(height: 1, color: context.v2.outline),
          // Ahead of every number: a partial sum must be labeled partial
          // before it is read, not after.
          if (widget.incomplete) ...[
            const SizedBox(height: V2Spacing.space8),
            const _PartialTotalsNotice(),
          ],
          if (safetyLimits.isNotEmpty) ...[
            _SectionHeading(
              title: 'Safety limits',
              description:
                  'These nutrients have an established upper limit (UL).',
              count: safetyLimits.length,
            ),
            for (final status in safetyLimits)
              NutrientProgressBar(
                key: Key(
                  '${status.shouldWarn ? "warn" : "row"}-'
                  '${status.total.canonicalId}',
                ),
                status: status,
              ),
          ],
          if (safetyLimits.isNotEmpty && intakeTargets.isNotEmpty)
            const _SectionDivider(),
          if (intakeTargets.isNotEmpty) ...[
            _SectionHeading(
              title: 'Intake targets — no UL',
              description:
                  'These nutrients have an intake target but no established '
                  'UL. Above 100% of a target is not automatically unsafe.',
              count: intakeTargets.length,
            ),
            for (final status in shownTargets)
              NutrientProgressBar(
                key: Key('row-${status.total.canonicalId}'),
                status: status,
              ),
            if (hasMoreTargets)
              _SectionToggle(
                label: _targetsExpanded
                    ? 'Show fewer intake targets'
                    : 'Show all ${intakeTargets.length} intake targets',
                expanded: _targetsExpanded,
                onTap: () =>
                    setState(() => _targetsExpanded = !_targetsExpanded),
              ),
          ],
          if ((safetyLimits.isNotEmpty || intakeTargets.isNotEmpty) &&
              labelAmounts.isNotEmpty)
            const _SectionDivider(),
          if (labelAmounts.isNotEmpty) ...[
            _SectionHeading(
              title: 'Label amounts',
              description:
                  'No reliable intake target or UL is available, so only the '
                  'label amount is shown.',
              count: labelAmounts.length,
            ),
            if (_labelAmountsExpanded)
              for (final status in labelAmounts)
                NutrientProgressBar(
                  key: Key('row-${status.total.canonicalId}'),
                  status: status,
                ),
            _SectionToggle(
              label: _labelAmountsExpanded
                  ? 'Hide label amounts'
                  : 'Show ${labelAmounts.length} label '
                        '${labelAmounts.length == 1 ? "amount" : "amounts"}',
              expanded: _labelAmountsExpanded,
              onTap: () => setState(
                () => _labelAmountsExpanded = !_labelAmountsExpanded,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.description,
    required this.count,
  });

  final String title;
  final String description;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space12,
          V2Spacing.space16,
          V2Spacing.space12,
          V2Spacing.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: V2Typography.bodyMedium(color: context.v2.fg),
                  ),
                ),
                Text(
                  '$count ${count == 1 ? "nutrient" : "nutrients"}',
                  style: V2Typography.caption(color: context.v2.fgMuted),
                ),
              ],
            ),
            const SizedBox(height: V2Spacing.space4),
            Text(
              description,
              style: V2Typography.caption(color: context.v2.fgMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.space4),
      child: Divider(height: 1, color: context.v2.outline),
    );
  }
}

/// Accessible, full-width control for revealing a compact nutrient group.
class _SectionToggle extends StatelessWidget {
  const _SectionToggle({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: expanded,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: V2Spacing.space48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space12,
                vertical: V2Spacing.space8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: V2Typography.label(color: context.v2.accent),
                    ),
                  ),
                  const SizedBox(width: V2Spacing.space4),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: V2Motion.fast,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: context.v2.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.totalNutrients, required this.warningCount});

  final int totalNutrients;
  final int warningCount;

  @override
  Widget build(BuildContext context) {
    final alertStyle = context.v2.tintedLabel(
      context.v2.contraindicated,
      borderAlpha: 0.35,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(
        children: [
          Icon(
            Icons.health_and_safety_outlined,
            size: 20,
            color: context.v2.fgMuted,
          ),
          const SizedBox(width: V2Spacing.space8),
          Expanded(
            child: Text(
              'Stack Nutrient Totals',
              style: V2Typography.bodyMedium(color: context.v2.fg),
            ),
          ),
          if (warningCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: alertStyle.fill,
                borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                border: Border.all(color: alertStyle.border),
              ),
              child: Text(
                '$warningCount ${warningCount == 1 ? "alert" : "alerts"}',
                style: V2Typography.overline(color: alertStyle.foreground),
              ),
            )
          else
            Text(
              '$totalNutrients tracked',
              style: V2Typography.caption(color: context.v2.fgMuted),
            ),
        ],
      ),
    );
  }
}
