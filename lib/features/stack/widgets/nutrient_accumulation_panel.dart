// NutrientAccumulationPanel — top-of-stack-screen card showing every
// nutrient summed across the user's stack against RDA/UL benchmarks.
//
// This is the visual surface for the M1 medical-grade gap fix:
// per-product UL checks miss accumulation across multiple products.
//
// States:
//   * loading       → small CircularProgressIndicator
//   * error         → silent shrink (the rest of the stack screen still
//                     works; no need to fail loud over a panel)
//   * empty stack   → hidden entirely (handled by SizedBox.shrink)
//   * one warning   → expanded inline list
//   * many warnings → expanded inline list, scroll-friendly
//
// We deliberately do NOT make this collapsible at first launch. The
// whole point is that the most dangerous nutrient is visible the
// moment the user opens the screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
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
      error: (_, __) => const SizedBox.shrink(),
      data: (statuses) {
        if (statuses.isEmpty) return const SizedBox.shrink();
        return _PanelShell(child: _PanelBody(statuses: statuses));
      },
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
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
      ),
      child: child,
    );
  }
}

class _PanelBody extends StatefulWidget {
  const _PanelBody({required this.statuses});

  final List<NutrientStatus> statuses;

  @override
  State<_PanelBody> createState() => _PanelBodyState();
}

class _PanelBodyState extends State<_PanelBody> {
  /// How many non-warning nutrients to show before the user taps "Show
  /// all". Keeps the stack screen scannable on first load.
  static const _collapsedLimit = 8;

  bool _expanded = false;

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

  @override
  Widget build(BuildContext context) {
    final warnings = widget.statuses.where((s) => s.shouldWarn).toList()
      ..sort((a, b) => _riskScore(b).compareTo(_riskScore(a)));
    final notable = widget.statuses.where((s) => !s.shouldWarn).toList()
      ..sort((a, b) => _riskScore(b).compareTo(_riskScore(a)));

    final hasMore = notable.length > _collapsedLimit;
    final shown = _expanded ? notable : notable.take(_collapsedLimit).toList();

    return Padding(
      padding: const EdgeInsets.all(V2Spacing.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            totalNutrients: widget.statuses.length,
            warningCount: warnings.length,
          ),
          const Divider(height: 1, color: V2Colors.outline),
          // Warnings always render at the top, sorted by risk score —
          // safety outranks user preference.
          for (final s in warnings)
            NutrientProgressBar(
              key: Key('warn-${s.total.canonicalId}'),
              status: s,
            ),
          if (warnings.isNotEmpty && notable.isNotEmpty)
            const Divider(height: 16, color: V2Colors.outline),
          // Notable nutrients (no warning) sorted by %UL/%RDA desc.
          for (final s in shown)
            NutrientProgressBar(
              key: Key('row-${s.total.canonicalId}'),
              status: s,
            ),
          if (hasMore)
            _ShowMoreRow(
              expanded: _expanded,
              totalRemaining: notable.length - _collapsedLimit,
              totalAll: notable.length,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
        ],
      ),
    );
  }
}

/// Tappable footer row that toggles between showing the top 8 and the
/// full list of tracked nutrients. Placed inside the nutrient card so
/// the user keeps context instead of navigating away.
class _ShowMoreRow extends StatelessWidget {
  const _ShowMoreRow({
    required this.expanded,
    required this.totalRemaining,
    required this.totalAll,
    required this.onTap,
  });

  final bool expanded;
  final int totalRemaining;
  final int totalAll;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = expanded
        ? 'Show fewer'
        : 'Show all $totalAll tracked nutrients';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space12,
          V2Spacing.space12,
          V2Spacing.space12,
          V2Spacing.space8,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: V2Typography.label(color: V2Colors.accent)),
            const SizedBox(width: V2Spacing.space4),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: V2Motion.fast,
              child: const Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: V2Colors.accent,
              ),
            ),
          ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(
        children: [
          const Icon(
            Icons.health_and_safety_outlined,
            size: 20,
            color: V2Colors.fgMuted,
          ),
          const SizedBox(width: V2Spacing.space8),
          Expanded(
            child: Text(
              'Stack Nutrient Totals',
              style: V2Typography.bodyMedium(color: V2Colors.fg),
            ),
          ),
          if (warningCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: V2Colors.contraindicatedTint,
                borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                border: Border.all(
                  color: V2Colors.contraindicated.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                '$warningCount ${warningCount == 1 ? "alert" : "alerts"}',
                style: V2Typography.overline(color: V2Colors.contraindicated),
              ),
            )
          else
            Text(
              '$totalNutrients tracked',
              style: V2Typography.caption(color: V2Colors.fgMuted),
            ),
        ],
      ),
    );
  }
}
