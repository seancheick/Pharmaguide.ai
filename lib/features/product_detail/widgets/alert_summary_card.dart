// "Alert Summary" card — Section 3 of the product detail page.
//
// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T13 + T16.2g.
//
// Sean's design call:
//
//   ┌──────────────────────────────────────┐
//   │ ⚠ 2 interactions to monitor      ⌄  │
//   └──────────────────────────────────────┘   ← collapsed
//
//   ┌──────────────────────────────────────┐
//   │ ⚠ 2 interactions to monitor      ⌃  │
//   ├──────────────────────────────────────┤
//   │ • CAUTION  Title                     │
//   │   mechanism + management              │
//   │ • MONITOR  Title                     │
//   │   mechanism + management              │
//   └──────────────────────────────────────┘   ← expanded
//
// **T16.2g (2026-04-30) — accordion replacing scroll-to.** Pre-T16.2g
// the chevron promised drop-down behavior but the tap actually scrolled
// the page to the interactions section. PureLean live walkthrough:
// "drop down and we see everything there, one source". Inline expansion
// keeps the user's reading position and surfaces the warning bodies
// inline so they don't have to scroll past the rest of the IA to read
// what the alerts actually are.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';

class AlertSummaryCard extends StatefulWidget {
  /// Profile-filtered warnings the user should review. Empty list →
  /// the card hides itself entirely; caller doesn't need a separate
  /// `if (count > 0)` guard.
  final List<InteractionWarning> warnings;

  const AlertSummaryCard({super.key, required this.warnings});

  @override
  State<AlertSummaryCard> createState() => _AlertSummaryCardState();
}

class _AlertSummaryCardState extends State<AlertSummaryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.warnings.length;
    if (count <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PGCard(
      // Plain (not elevated) so the card sits visually quiet.
      variant: PGCardVariant.plain,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tappable header row — toggles expand/collapse.
          PGPressable(
            onTap: () => setState(() => _expanded = !_expanded),
            pressedScale: 0.98,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space16,
                vertical: AppTheme.space12,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: AppTheme.severityCaution,
                  ),
                  const SizedBox(width: AppTheme.space12),
                  Expanded(
                    child: Text(
                      _summaryCopy(count),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.space8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expanded body — sorted-by-severity warning rows.
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.space16,
                      0,
                      AppTheme.space16,
                      AppTheme.space12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(
                          height: 1,
                          thickness: 0.6,
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: AppTheme.space12),
                        for (final w in _sortedBySeverity(widget.warnings))
                          _AlertRow(warning: w),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  static List<InteractionWarning> _sortedBySeverity(
    List<InteractionWarning> input,
  ) {
    final sorted = List<InteractionWarning>.from(input);
    sorted.sort((a, b) => b.severity.weight.compareTo(a.severity.weight));
    return sorted;
  }

  /// Copy with proper singular/plural agreement.
  static String _summaryCopy(int count) {
    if (count == 1) return '1 interaction to monitor';
    return '$count interactions to monitor';
  }
}

/// Compact inline row for one interaction warning. Severity tag +
/// title on the first line, mechanism / management beneath. Mirrors
/// the visual hierarchy of `InteractionWarningsList` rows but lighter
/// (no per-row card chrome — the parent card already supplies it).
class _AlertRow extends StatelessWidget {
  final InteractionWarning warning;

  const _AlertRow({required this.warning});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _severityColor(warning.severity);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  warning.severity.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.space8),
              Expanded(
                child: Text(
                  warning.title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (warning.mechanism.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              warning.mechanism,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          if (warning.management.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              warning.management,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _severityColor(Severity severity) {
    switch (severity) {
      case Severity.contraindicated:
      case Severity.avoid:
        return AppTheme.severityContraindicated;
      case Severity.caution:
        return AppTheme.severityCaution;
      case Severity.monitor:
        return AppTheme.severityMonitor;
      case Severity.informational:
      case Severity.safe:
        return AppTheme.severityCaution;
    }
  }
}
