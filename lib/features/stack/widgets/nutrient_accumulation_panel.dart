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
    return Card(
      key: const Key('nutrient-accumulation-card'),
      color: AppColors.surface,
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _PanelBody extends StatelessWidget {
  const _PanelBody({required this.statuses});

  final List<NutrientStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final warnings = statuses.where((s) => s.shouldWarn).toList();
    final notable = statuses.where((s) => !s.shouldWarn).toList();

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            totalNutrients: statuses.length,
            warningCount: warnings.length,
          ),
          const Divider(height: 1, color: AppColors.border),
          // Warnings always render at the top, regardless of any
          // user-initiated re-ordering. Safety wins over preference.
          for (final s in warnings)
            NutrientProgressBar(
              key: Key('warn-${s.total.canonicalId}'),
              status: s,
            ),
          if (warnings.isNotEmpty && notable.isNotEmpty)
            const Divider(height: 16, color: AppColors.border),
          for (final s in notable.take(8))
            NutrientProgressBar(
              key: Key('row-${s.total.canonicalId}'),
              status: s,
            ),
          if (notable.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                'Showing top 8 of ${notable.length} tracked nutrients',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
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
