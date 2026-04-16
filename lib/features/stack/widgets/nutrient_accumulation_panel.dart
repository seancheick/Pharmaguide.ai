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
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
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
        return _PanelShell(
          child: _PanelBody(statuses: statuses),
        );
      },
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('nutrient-accumulation-card'),
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        side: BorderSide(color: scheme.outlineVariant, width: 0.8),
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
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            totalNutrients: widget.statuses.length,
            warningCount: warnings.length,
          ),
          const Divider(height: 1, color: AppColors.border),
          // Warnings always render at the top, sorted by risk score —
          // safety outranks user preference.
          for (final s in warnings)
            NutrientProgressBar(
              key: Key('warn-${s.total.canonicalId}'),
              status: s,
            ),
          if (warnings.isNotEmpty && notable.isNotEmpty)
            const Divider(height: 16, color: AppColors.border),
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
    final scheme = Theme.of(context).colorScheme;
    final label = expanded
        ? 'Show fewer'
        : 'Show all $totalAll tracked nutrients';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.totalNutrients,
    required this.warningCount,
  });

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
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Stack Nutrient Totals',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (warningCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.red.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                '$warningCount ${warningCount == 1 ? "alert" : "alerts"}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.red,
                ),
              ),
            )
          else
            Text(
              '$totalNutrients tracked',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
