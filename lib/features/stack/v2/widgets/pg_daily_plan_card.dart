// PGDailyPlanCard — roadmap Phase 3 surface.
//
// Renders the resolved daily plan produced by TimingSequenceResolver. The
// resolver arranges pipeline-emitted constraints into buckets; this card only
// draws that arrangement.
//
// Two things this card deliberately does NOT do:
//   * It never shows a clock time. The resolver's anchor hours exist only to
//     decide whether two buckets are far enough apart; presenting them would
//     read as dosing advice the pipeline never authored.
//   * It never rewrites advice. A constraint that could not be placed is shown
//     in the pipeline's own words, because a plan that quietly drops guidance
//     is worse than one that admits a conflict.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/services/stack/timing_sequence_resolver.dart';

class PGDailyPlanCard extends StatelessWidget {
  const PGDailyPlanCard({
    super.key,
    required this.plan,
    this.margin = EdgeInsets.zero,
  });

  final TimingSequencePlan plan;
  final EdgeInsetsGeometry margin;

  static const _slotIcons = {
    DailySlot.morningEmpty: Icons.wb_twilight_rounded,
    DailySlot.withBreakfast: Icons.free_breakfast_outlined,
    DailySlot.withDinner: Icons.dinner_dining_outlined,
    DailySlot.bedtime: Icons.bedtime_outlined,
  };

  @override
  Widget build(BuildContext context) {
    if (plan.isEmpty && plan.unsatisfied.isEmpty) {
      return const SizedBox.shrink();
    }

    final filled = DailySlot.values
        .where((slot) => (plan.itemsBySlot[slot] ?? const []).isNotEmpty)
        .toList(growable: false);

    return Padding(
      padding: margin,
      child: Container(
        decoration: BoxDecoration(
          color: V2Colors.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: V2Colors.outline),
          boxShadow: V2Shadows.sm,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Padding(
                padding: const EdgeInsets.all(V2Spacing.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: V2Colors.accent,
                        ),
                        SizedBox(width: V2Spacing.space8),
                        PGEyebrow('Daily plan', color: V2Colors.accent),
                      ],
                    ),
                    const SizedBox(height: V2Spacing.space8),
                    Text(
                      'One way to space your day',
                      style: V2Typography.titleSm(color: V2Colors.fg),
                    ),
                    const SizedBox(height: V2Spacing.space4),
                    Text(
                      'Grouped from your timing guidance. Anchor these to meals '
                      'and bedtime you already keep — the grouping matters more '
                      'than the exact hour.',
                      style: V2Typography.bodySm(color: V2Colors.fgMuted),
                    ),
                    const SizedBox(height: V2Spacing.space12),
                    for (final slot in filled) ...[
                      _SlotRow(
                        slot: slot,
                        icon: _slotIcons[slot]!,
                        items: plan.itemsBySlot[slot]!,
                      ),
                      const SizedBox(height: V2Spacing.space12),
                    ],
                    if (plan.unsatisfied.isNotEmpty) _Conflicts(plan: plan),
                  ],
                ),
              ),
            ),
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(color: V2Colors.accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.icon,
    required this.items,
  });

  final DailySlot slot;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: V2Colors.accent),
        const SizedBox(width: V2Spacing.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                slot.label,
                style: V2Typography.label(color: V2Colors.fg),
              ),
              const SizedBox(height: 2),
              Text(
                items.join(' · '),
                style: V2Typography.bodySm(color: V2Colors.fgMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Conflicts extends StatelessWidget {
  const _Conflicts({required this.plan});

  final TimingSequencePlan plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(V2Spacing.space12),
      decoration: BoxDecoration(
        color: V2Colors.bg,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Couldn't fit into one day",
            style: V2Typography.label(color: V2Colors.fg),
          ),
          const SizedBox(height: V2Spacing.space4),
          Text(
            'These are worth a conversation with your pharmacist or doctor, '
            'who can weigh them against your full routine.',
            style: V2Typography.caption(color: V2Colors.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space8),
          for (final conflict in plan.unsatisfied) ...[
            Text(
              conflict.advice,
              style: V2Typography.bodySm(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space4),
          ],
        ],
      ),
    );
  }
}
