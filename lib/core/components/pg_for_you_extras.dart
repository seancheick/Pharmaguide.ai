// "For You" supplementary widgets — context chips + why-this-fits
// expander. Ported from v1 ForYouSection's private widgets so v2
// PersonalFit can render the full Section-2 signal set (Trust & IA
// Sprint 1 T1.2). Pure v2 styling: V2Colors + V2Typography.
//
// Each widget is data-only — composed by `buildPersonalFitSection`
// after the connected screen pulls the chips from the user profile
// and the reasons from FitScoreResult.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';

/// Small outline pills naming the user's profile signals — goals,
/// conditions, drug classes. Tells the user "this fit is keyed on X,
/// Y, Z" so they know which inputs are driving the verdict.
///
/// `chips` is the raw list from
/// `profile.goals + profile.conditions + profile.drugClasses`,
/// already deduped and capped by the caller (v1 spec: 4 max). This
/// widget only renders; the chip wrap returns `SizedBox.shrink()`
/// when the list is empty so the section's spacing math doesn't
/// reserve room for nothing.
class PGContextChips extends StatelessWidget {
  final List<String> chips;
  const PGContextChips({super.key, required this.chips});

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips
          .map(
            (c) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: V2Colors.bg,
                borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                border: Border.all(color: V2Colors.outline, width: 0.8),
              ),
              child: Text(
                _humanize(c),
                style: V2Typography.caption(
                  color: V2Colors.fgMuted,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  /// `snake_case` → `Snake Case`. Pipeline-shape-tolerant: passes
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

/// Expandable "Why this fits you" — 4-bullet deterministic explanation
/// pulled from `FitScoreResult.reasons`. Collapsed by default; tapping
/// the header reveals the bullets with an AnimatedSize curve.
///
/// `reasons` is the raw `FitScoreResult.reasons` list. Caller doesn't
/// need to filter or sort — this widget caps at 4 to keep the
/// expanded view scannable, matching v1 spec.
class PGWhyThisFitsExpander extends StatefulWidget {
  final List<String> reasons;
  const PGWhyThisFitsExpander({super.key, required this.reasons});

  @override
  State<PGWhyThisFitsExpander> createState() => _PGWhyThisFitsExpanderState();
}

class _PGWhyThisFitsExpanderState extends State<PGWhyThisFitsExpander> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.reasons.isEmpty) return const SizedBox.shrink();
    // Cap at 4 bullets — FitScore can carry more from E1/E2a/E2b/E2c
    // sub-signals; we surface the top 4 to keep the section scannable.
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
                style: V2Typography.label(
                  color: V2Colors.fgMuted,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 4),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: V2Colors.fgMuted,
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
                                  decoration: const BoxDecoration(
                                    color: V2Colors.fgMuted,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  b,
                                  style: V2Typography.bodySm(
                                    color: V2Colors.fg,
                                  ).copyWith(height: 1.35),
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
