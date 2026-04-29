// Calm bottom sheet shown once per (medication-id, depletion) pair
// after a user adds a medication. Uses authored layperson copy from
// the depletion record; falls back to the legacy clinical fields.
//
// Tone: share, don't alarm. Primary CTA is "Remind me later" (not
// "Dismiss" — users read dismiss as permission to ignore the
// biology, and that's not what we want either). Secondary CTA is
// "Not now" which marks the nudge dismissed permanently for this
// medication.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/medication_depletion_nudge.dart';

/// Present the depletion nudge as a modal bottom sheet.
///
/// Returns the user's choice:
///   true  — "Not now" (dismissed permanently — service should call
///           [MedicationDepletionNudgeService.markAllSeen])
///   false — the sheet was dismissed by scrim tap or back gesture —
///           the caller may choose to show again later
///   null  — sheet closed without a concrete choice
Future<bool?> showDepletionNudgeSheet(
  BuildContext context, {
  required PendingDepletionNudge nudge,
}) {
  return PGModal.bottomSheet<bool>(
    context: context,
    builder: (ctx) => _DepletionNudgeSheet(nudge: nudge),
  );
}

class _DepletionNudgeSheet extends StatelessWidget {
  final PendingDepletionNudge nudge;
  const _DepletionNudgeSheet({required this.nudge});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final drugName =
        nudge.depletions.first.drugDisplayName.isEmpty
            ? 'your medication'
            : nudge.depletions.first.drugDisplayName;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space20,
          AppTheme.space16,
          AppTheme.space20,
          AppTheme.space20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Grabber bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.space16),
            // Calm header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.severityInformational.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: const Icon(
                    Icons.lightbulb_outline_rounded,
                    color: AppTheme.severityInformational,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppTheme.space12),
                Expanded(
                  child: Text(
                    'Since you take $drugName',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space8),
            Text(
              'Here\'s something worth knowing over time — nothing urgent.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTheme.space16),
            // One panel per depletion (max 2).
            ...nudge.depletions.map(
              (d) => Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.space12),
                child: _NudgePanel(depletion: d),
              ),
            ),
            const SizedBox(height: AppTheme.space8),
            // Actions. When there's exactly ONE depletion in the nudge
            // and it has an identifiable nutrient name, we surface a
            // "Browse options" CTA that deep-links into the supplement
            // search pre-filtered to that nutrient. Multiple-depletion
            // nudges keep the simpler two-button layout — picking which
            // nutrient to browse becomes ambiguous otherwise.
            if (nudge.depletions.length == 1 &&
                nudge.depletions.first.nutrientName.isNotEmpty) ...[
              FilledButton(
                onPressed: () {
                  final nutrient = nudge.depletions.first.nutrientName;
                  Navigator.of(context).pop(false);
                  // Use go_router to preserve app shell; pass the
                  // nutrient name as the initialQuery so the search
                  // screen pre-fills the field and fires the search.
                  GoRouter.of(context).go(
                    '${Routes.search}?query=${Uri.encodeQueryComponent(nutrient)}',
                  );
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
                child: Text('Browse ${nudge.depletions.first.nutrientName} options'),
              ),
              const SizedBox(height: AppTheme.space8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Not now'),
                    ),
                  ),
                  const SizedBox(width: AppTheme.space12),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Got it'),
                    ),
                  ),
                ],
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Not now'),
                    ),
                  ),
                  const SizedBox(width: AppTheme.space12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Got it'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _NudgePanel extends StatelessWidget {
  final DepletionMatch depletion;
  const _NudgePanel({required this.depletion});

  String _fallbackBody() {
    final d = depletion;
    if (d.clinicalImpact != null && d.clinicalImpact!.isNotEmpty) {
      return d.clinicalImpact!;
    }
    if (d.recommendation.isNotEmpty) return d.recommendation;
    final n = d.nutrientName.isEmpty ? 'this nutrient' : d.nutrientName;
    return 'Long-term use can gradually lower $n.';
  }

  String _fallbackHeadline() {
    final d = depletion;
    return 'May affect ${d.nutrientName.isEmpty ? "a nutrient" : d.nutrientName} over time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = depletion;
    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: scheme.outlineVariant, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.alertHeadline ?? _fallbackHeadline(),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            d.alertBody ?? _fallbackBody(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.86),
            ),
          ),
          if (d.monitoringTipShort != null &&
              d.monitoringTipShort!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 14,
                  color: AppTheme.severitySafe,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    d.monitoringTipShort!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          // Food-sources line — when Dr. Pham authored food_sources_short
          // we show it as a second helper row. For absorption-blocked
          // depletions her honest hint ("food sources may not be enough
          // on their own") surfaces here too, so the user gets the full
          // picture: supplement OR food, context-aware.
          if (d.foodSourcesShort != null &&
              d.foodSourcesShort!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.restaurant_menu_rounded,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    d.foodSourcesShort!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
