// StackCoverageCard — "is my stack working?" gap-analysis card for the
// v2 Stack screen. Renders a [CoverageReport] (built by
// coverageReportProvider) as three expandable buckets:
//
//   Supported   — goals the stack serves, with the products serving them.
//   Underdosed  — nutrients present but below an adequate dose.
//   Unaddressed — goals nothing supports + depletions nothing replenishes.
//
// Like [StackSafetyBanner], the widget is pure — no Riverpod hooks, no
// I/O. Tests drive it directly with synthetic reports. The provider
// wiring lives in the stack screen's coverage slot.
//
// Voice contract: calm-advisory only. No imperatives, no product
// recommendations — nutrient/ingredient classes only, with the
// "worth a conversation with your doctor" pattern on depletion gaps.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/scoring/coverage.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/services/stack/coverage_analyzer.dart';

class StackCoverageCard extends StatelessWidget {
  const StackCoverageCard({
    super.key,
    required this.report,
    this.onAddGoals,
    this.margin = EdgeInsets.zero,
  });

  /// Coverage report driving the card. Build once per stack/profile
  /// mutation and pass in — the widget is pure w.r.t. [report].
  final CoverageReport report;

  /// Optional tap target for the no-goals invitation (usually the
  /// profile setup route). When null the invitation renders as plain
  /// text with no action.
  final VoidCallback? onAddGoals;

  /// Outer margin so the caller can match the surrounding layout.
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    // Empty stack → no card at all.
    if (report.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: margin,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: V2Colors.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: V2Colors.outline),
          boxShadow: V2Shadows.sm,
        ),
        padding: const EdgeInsets.all(V2Spacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PGEyebrow('Coverage'),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Is your stack working?',
              style: V2Typography.titleSm(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space12),
            // Goals invitation renders ALONGSIDE the goal-independent
            // sections (not instead of them) — depletion/underdosed gaps
            // exist regardless of goals. Users who explicitly opted out
            // of goals (GOAL_NONE) are not nagged.
            if (!report.hasGoals && !report.goalsOptedOut) ...[
              _noGoalsInvitation(),
              const SizedBox(height: V2Spacing.space12),
            ],
            if (report.hasGoals) ...[
              _CoverageSection(
                key: const Key('coverage-supported'),
                title: 'Supported',
                count: report.supported.length,
                tone: V2Colors.safe,
                emptyLine:
                    'None of your goals are currently matched by products '
                    'in your stack.',
                rows: [
                  for (final g in report.supported)
                    _CoverageRow(
                      title: g.goalLabel,
                      detail: _supportedDetail(g),
                    ),
                ],
              ),
              const SizedBox(height: V2Spacing.space8),
              // Present-but-underdosed goals: the right ingredient is in the
              // stack, just below its effective dose for this goal. The honest
              // middle state between Supported and Unaddressed.
              _CoverageSection(
                key: const Key('coverage-partial'),
                title: 'Partially supported',
                count: report.partiallySupported.length,
                tone: V2Colors.monitor,
                emptyLine:
                    'No goals are partly covered — matched goals are either '
                    'fully supported or not yet addressed.',
                rows: [
                  for (final g in report.partiallySupported)
                    _CoverageRow(title: g.goalLabel, detail: _partialDetail(g)),
                ],
              ),
              const SizedBox(height: V2Spacing.space8),
            ],
            _CoverageSection(
              key: const Key('coverage-underdosed'),
              title: 'Underdosed',
              count: report.underdosed.length,
              tone: V2Colors.monitor,
              emptyLine: 'No below-target doses detected in your stack.',
              rows: [
                for (final n in report.underdosed)
                  _CoverageRow(title: n.nutrientName, detail: n.detail),
              ],
            ),
            const SizedBox(height: V2Spacing.space8),
            _CoverageSection(
              key: const Key('coverage-unaddressed'),
              title: 'Unaddressed',
              count: report.unaddressedCount,
              tone: V2Colors.caution,
              emptyLine:
                  'Every goal and known nutrient gap has something in '
                  'your stack working on it.',
              rows: [
                for (final g in report.unaddressedGoals)
                  _CoverageRow(title: g.goalLabel, detail: g.message),
                for (final d in report.unreplenishedDepletions)
                  _CoverageRow(title: d.nutrientName, detail: d.message),
              ],
            ),
            if (report.coverageIncomplete) ...[
              const SizedBox(height: V2Spacing.space12),
              Text(
                coverageHedge('coverage may be incomplete'),
                key: const Key('coverage-hedge-line'),
                style: V2Typography.caption(color: V2Colors.fgSubtle),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Calm single-line invitation when no goals are set — no fake
  /// analysis, just a pointer to the profile.
  Widget _noGoalsInvitation() {
    final text = Text(
      'Add goals to your profile to see what your stack covers.',
      key: const Key('coverage-no-goals'),
      style: V2Typography.bodySm(color: V2Colors.fgMuted),
    );
    if (onAddGoals == null) return text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        text,
        const SizedBox(height: V2Spacing.space8),
        InkWell(
          onTap: onAddGoals,
          borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.space12,
              vertical: V2Spacing.space4,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
              border: Border.all(
                color: V2Colors.accent.withValues(alpha: 0.32),
              ),
            ),
            child: Text(
              'Add goals',
              style: V2Typography.label(color: V2Colors.accent),
            ),
          ),
        ),
      ],
    );
  }

  static String _supportedDetail(SupportedGoal g) {
    final names = g.productNames;
    if (names.length == 1) {
      return 'Covered by ${names.first}.';
    }
    return 'Covered by ${names.length} products: ${names.join(", ")}.';
  }

  static String _partialDetail(SupportedGoal g) {
    final names = g.productNames;
    final who = names.length == 1 ? names.first : '${names.length} products';
    return 'Present via $who, but likely below an effective dose for '
        'this goal.';
  }
}

// =============================================================================
// Expandable section — header row (dot + title + count pill + chevron)
// that toggles its rows open/closed. Mirrors the v2 expandable-row
// language used by the score breakdown card without depending on it.
// =============================================================================

class _CoverageSection extends StatefulWidget {
  const _CoverageSection({
    super.key,
    required this.title,
    required this.count,
    required this.tone,
    required this.emptyLine,
    required this.rows,
  });

  final String title;
  final int count;
  final Color tone;

  /// Calm one-liner rendered inside the expanded body when [rows] is
  /// empty — sections never disappear, so the user always sees all
  /// three buckets and learns the model.
  final String emptyLine;

  final List<_CoverageRow> rows;

  @override
  State<_CoverageSection> createState() => _CoverageSectionState();
}

class _CoverageSectionState extends State<_CoverageSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: V2Colors.bg,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space12,
                vertical: V2Spacing.space12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.tone,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: V2Spacing.space8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: V2Typography.bodyMedium(color: V2Colors.fg),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: V2Spacing.space8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: widget.tone.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                    ),
                    child: Text(
                      '${widget.count}',
                      style: V2Typography.caption(color: widget.tone),
                    ),
                  ),
                  const SizedBox(width: V2Spacing.space8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: V2Motion.base,
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: V2Colors.fgMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // AnimatedSize + conditional child (not AnimatedCrossFade) so
          // collapsed rows are truly absent from the tree — keeps
          // semantics/finders honest and avoids laying out hidden text.
          AnimatedSize(
            duration: V2Motion.base,
            curve: V2Motion.emphasized,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(
                      V2Spacing.space12,
                      0,
                      V2Spacing.space12,
                      V2Spacing.space12,
                    ),
                    child: widget.rows.isEmpty
                        ? Text(
                            widget.emptyLine,
                            style: V2Typography.caption(
                              color: V2Colors.fgMuted,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < widget.rows.length; i++) ...[
                                if (i > 0)
                                  const SizedBox(height: V2Spacing.space8),
                                widget.rows[i],
                              ],
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CoverageRow extends StatelessWidget {
  const _CoverageRow({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: V2Typography.bodySm(color: V2Colors.fg)),
        const SizedBox(height: 2),
        Text(detail, style: V2Typography.caption(color: V2Colors.fgMuted)),
      ],
    );
  }
}
