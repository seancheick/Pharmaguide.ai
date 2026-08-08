// StackGoalSupportCard — goal support for the v2 Stack screen. Nutrient totals
// and reference comparisons live exclusively on the Nutrients tab.
//
// Like [StackSafetyBanner], the widget is pure — no Riverpod hooks, no
// I/O. Tests drive it directly with synthetic reports. The provider
// wiring lives in the stack screen's coverage slot.
//
// Medication-related nutrient guidance is intentionally absent here; the
// Medication & nutrients card owns that interpretation.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/scoring/coverage.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/services/stack/coverage_analyzer.dart';

class StackGoalSupportCard extends StatelessWidget {
  const StackGoalSupportCard({
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
    if (report.isEmpty || report.goalsOptedOut) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: margin,
      child: _CoveragePanel(
        key: const Key('goal-support-card'),
        eyebrow: 'Goals',
        title: 'Is your stack supporting your goals?',
        child: report.hasGoals
            ? Column(
                children: [
                  _CoverageSection(
                    key: const Key('coverage-supported'),
                    title: 'Supported',
                    count: report.supported.length,
                    tone: context.v2.safe,
                    emptyLine:
                        'No products currently meet the evidence criteria for '
                        'your goals.',
                    rows: [
                      for (final g in report.supported)
                        _CoverageRow(
                          title: g.goalLabel,
                          detail: _supportedDetail(g),
                        ),
                    ],
                  ),
                  const Divider(height: 1),
                  _CoverageSection(
                    key: const Key('coverage-partial'),
                    title: 'Partially supported',
                    count: report.partiallySupported.length,
                    tone: context.v2.monitor,
                    emptyLine: 'No goals are partially supported.',
                    rows: [
                      for (final g in report.partiallySupported)
                        _CoverageRow(
                          title: g.goalLabel,
                          detail: _partialDetail(g),
                        ),
                    ],
                  ),
                  const Divider(height: 1),
                  _CoverageSection(
                    key: const Key('coverage-not-supported'),
                    title: 'Not currently supported',
                    count: report.unaddressedGoals.length,
                    tone: context.v2.caution,
                    emptyLine: 'All of your goals have some support.',
                    rows: [
                      for (final g in report.unaddressedGoals)
                        _CoverageRow(
                          title: g.goalLabel,
                          detail:
                              'No current product meets the evidence criteria '
                              'for this goal.',
                        ),
                    ],
                  ),
                  if (report.coverageIncomplete) ...[
                    const SizedBox(height: V2Spacing.space8),
                    Text(
                      coverageHedge('goal support may be incomplete'),
                      key: const Key('coverage-hedge-line'),
                      style: V2Typography.caption(color: context.v2.fgSubtle),
                    ),
                  ],
                ],
              )
            : _noGoalsInvitation(context),
      ),
    );
  }

  /// Calm single-line invitation when no goals are set — no fake
  /// analysis, just a pointer to the profile.
  Widget _noGoalsInvitation(BuildContext context) {
    final text = Text(
      'Add goals to see which products support them.',
      key: const Key('coverage-no-goals'),
      style: V2Typography.bodySm(color: context.v2.fgMuted),
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
                color: context.v2.accent.withValues(alpha: 0.32),
              ),
            ),
            child: Text(
              'Add goals',
              style: V2Typography.label(color: context.v2.accent),
            ),
          ),
        ),
      ],
    );
  }

  static String _supportedDetail(SupportedGoal g) {
    final names = g.productNames;
    if (names.length == 1) {
      return 'Supported by ${names.first}.';
    }
    return 'Supported by ${names.length} products: ${names.join(", ")}.';
  }

  static String _partialDetail(SupportedGoal g) {
    final names = g.productNames;
    final who = names.length == 1 ? names.first : '${names.length} products';
    return '$who is present, but support may be limited at this amount.';
  }
}

class _CoveragePanel extends StatelessWidget {
  const _CoveragePanel({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
        boxShadow: V2Shadows.sm,
      ),
      padding: const EdgeInsets.all(V2Spacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PGEyebrow(eyebrow),
          const SizedBox(height: V2Spacing.space8),
          Text(title, style: V2Typography.titleSm(color: context.v2.fg)),
          const SizedBox(height: V2Spacing.space8),
          child,
        ],
      ),
    );
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
  /// empty — sections stay visible so the taxonomy remains predictable.
  final String emptyLine;

  final List<_CoverageRow> rows;

  @override
  State<_CoverageSection> createState() => _CoverageSectionState();
}

class _CoverageSectionState extends State<_CoverageSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.count > 0;
  }

  @override
  void didUpdateWidget(covariant _CoverageSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count == 0 && widget.count > 0) _expanded = true;
    if (oldWidget.count > 0 && widget.count == 0) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final countStyle = context.v2.tintedLabel(widget.tone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: V2Spacing.space12),
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
                    style: V2Typography.bodyMedium(color: context.v2.fg),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: V2Spacing.space8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: countStyle.fill,
                    borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                  ),
                  child: Text(
                    '${widget.count}',
                    style: V2Typography.caption(color: countStyle.foreground),
                  ),
                ),
                const SizedBox(width: V2Spacing.space8),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: V2Motion.base,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: context.v2.fgMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: V2Motion.base,
          curve: V2Motion.emphasized,
          alignment: Alignment.topCenter,
          child: !_expanded
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(
                    left: V2Spacing.space16,
                    right: V2Spacing.space4,
                    bottom: V2Spacing.space12,
                  ),
                  child: widget.rows.isEmpty
                      ? Text(
                          widget.emptyLine,
                          style: V2Typography.caption(
                            color: context.v2.fgMuted,
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
        Text(title, style: V2Typography.bodySm(color: context.v2.fg)),
        const SizedBox(height: 2),
        Text(detail, style: V2Typography.caption(color: context.v2.fgMuted)),
      ],
    );
  }
}
