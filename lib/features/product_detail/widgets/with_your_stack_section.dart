// "With your stack" interactions — Section 7.1 of the Trust & IA
// product detail.
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.7.
//
// Renders one row per profile-relevant grouping (drug class or
// condition the user has on file) with the interaction status against
// THIS product:
//
//   ⚠  Statins             Avoid — competes for absorption
//   ⚠  Anticoagulants      Caution — may amplify effect
//   ✓  Hypertension        No known interaction
//
// The ✓ rows are deliberately positive trust signals (not just
// absence of a warning) — users want explicit confirmation that the
// product is safe with their current regimen, not silence.
//
// Tapping a ⚠ row reveals the mechanism + recommendation + citation
// links from the underlying [InteractionWarning].
//
// 7.2 (general interactions — alerts not tied to user profile) is
// deferred to Sprint 3 per spec; the existing
// [InteractionWarningsList] continues to handle generic precautions
// directly below this section.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';

/// Renders a per-stack-item interaction summary. Hides entirely when
/// the user's profile has no drug classes AND no conditions on file —
/// without those signals there's no way to compute a personalized
/// status, and the empty-state would be noise.
class WithYourStackSection extends StatelessWidget {
  /// Full set of warnings for this product (already deduped + filtered
  /// upstream). The widget partitions by `drugClassIds` / `conditionIds`.
  final List<InteractionWarning> warnings;

  /// User's declared drug classes (e.g. `{'statins', 'anticoagulants'}`).
  /// One row per entry. Lowercase canonical form.
  final Set<String> userDrugClasses;

  /// User's declared conditions (e.g. `{'hypertension', 'pregnancy'}`).
  /// One row per entry.
  final Set<String> userConditions;

  const WithYourStackSection({
    super.key,
    required this.warnings,
    required this.userDrugClasses,
    required this.userConditions,
  });

  @override
  Widget build(BuildContext context) {
    if (userDrugClasses.isEmpty && userConditions.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final rows = <_StackRowData>[];
    // Drug-class rows first, then condition rows. Within each group,
    // descending severity then alphabetical so the loudest interactions
    // surface at the top.
    rows.addAll(_buildRows(
      keys: userDrugClasses,
      isDrugClass: true,
      warnings: warnings,
    ));
    rows.addAll(_buildRows(
      keys: userConditions,
      isDrugClass: false,
      warnings: warnings,
    ));

    // Sort by severity weight (worst first); within same weight,
    // alphabetical by humanized label.
    rows.sort((a, b) {
      final cmp = (b.severity?.weight ?? -1)
          .compareTo(a.severity?.weight ?? -1);
      if (cmp != 0) return cmp;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.medication_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                'With your stack',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.15,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space4),
          Text(
            'Personal interaction check based on your medications and '
            'conditions on file.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppTheme.space12),
          for (final row in rows) ...[
            _StackRow(data: row),
            if (row != rows.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  /// Build one row per profile entry, picking the worst-matching
  /// warning (or null for ✓ rows).
  static List<_StackRowData> _buildRows({
    required Set<String> keys,
    required bool isDrugClass,
    required List<InteractionWarning> warnings,
  }) {
    final rows = <_StackRowData>[];
    for (final key in keys) {
      InteractionWarning? worst;
      for (final w in warnings) {
        final matches = isDrugClass
            ? w.drugClassIds.contains(key)
            : w.conditionIds.contains(key);
        if (!matches) continue;
        if (worst == null || w.severity.weight > worst.severity.weight) {
          worst = w;
        }
      }
      rows.add(_StackRowData(
        key: key,
        label: _humanize(key),
        warning: worst,
      ));
    }
    return rows;
  }

  /// snake_case → "Snake Case". Matches the humanizer pattern used in
  /// for_you_section.dart so context chips and stack rows read with
  /// the same casing.
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

/// Per-row data computed by [WithYourStackSection._buildRows].
class _StackRowData {
  final String key;
  final String label;

  /// `null` when no warning matched — the row renders as a ✓
  /// "no interaction" trust signal.
  final InteractionWarning? warning;

  Severity? get severity => warning?.severity;

  const _StackRowData({
    required this.key,
    required this.label,
    required this.warning,
  });
}

/// Single row — ⚠ severity-tinted with tap-expand OR ✓ static
/// "no interaction" line.
class _StackRow extends StatefulWidget {
  final _StackRowData data;
  const _StackRow({required this.data});

  @override
  State<_StackRow> createState() => _StackRowState();
}

class _StackRowState extends State<_StackRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final w = widget.data.warning;
    final hasWarning = w != null;
    final tone = hasWarning ? w.severity.color : AppTheme.severitySafe;

    final headline = hasWarning
        ? (w.alertHeadline?.trim().isNotEmpty ?? false)
            ? w.alertHeadline!.trim()
            : w.title
        : 'No known interaction';

    return Container(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: hasWarning ? 0.06 : 0.04),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: tone.withValues(alpha: hasWarning ? 0.20 : 0.15),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PGPressable(
            // ✓ rows aren't tappable — there's nothing to expand.
            onTap: hasWarning
                ? () => setState(() => _expanded = !_expanded)
                : null,
            pressedScale: 0.98,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space12,
                vertical: AppTheme.space8 + 2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    hasWarning
                        ? _iconFor(w.severity)
                        : Icons.check_circle_outline_rounded,
                    size: 18,
                    color: tone,
                  ),
                  const SizedBox(width: AppTheme.space8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.data.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          hasWarning
                              ? '${w.severity.label} — $headline'
                              : headline,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (hasWarning) ...[
                    const SizedBox(width: AppTheme.space8),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (hasWarning)
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? _ExpandedDetail(warning: w)
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  static IconData _iconFor(Severity s) => switch (s) {
        Severity.contraindicated => Icons.do_not_disturb_on_outlined,
        Severity.avoid => Icons.error_outline_rounded,
        Severity.caution => Icons.warning_amber_rounded,
        Severity.monitor => Icons.visibility_outlined,
        _ => Icons.info_outline_rounded,
      };
}

/// Expanded mechanism + recommendation + citations panel.
class _ExpandedDetail extends StatelessWidget {
  final InteractionWarning warning;
  const _ExpandedDetail({required this.warning});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = warning.alertBody?.trim().isNotEmpty == true
        ? warning.alertBody!.trim()
        : warning.mechanism;
    final management = warning.management.trim();
    final hasCitations = warning.sourceUrls.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space12,
        0,
        AppTheme.space12,
        AppTheme.space12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (body.isNotEmpty) ...[
            const _DetailLabel(text: 'Mechanism'),
            const SizedBox(height: 2),
            Text(
              body,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppTheme.space8),
          ],
          if (management.isNotEmpty) ...[
            const _DetailLabel(text: 'Recommendation'),
            const SizedBox(height: 2),
            Text(
              management,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppTheme.space8),
          ],
          Row(
            children: [
              _EvidenceChip(level: warning.evidenceLevel),
              if (hasCitations) ...[
                const SizedBox(width: AppTheme.space8),
                PGPressable(
                  onTap: () => _showCitations(context),
                  pressedScale: 0.96,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusFull),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${warning.sourceUrls.length} citation${warning.sourceUrls.length == 1 ? '' : 's'}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showCitations(BuildContext context) {
    PGModal.bottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space20,
            AppTheme.space12,
            AppTheme.space20,
            AppTheme.space24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Citations',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: AppTheme.space12),
              for (final url in warning.sourceUrls)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    url,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailLabel extends StatelessWidget {
  final String text;
  const _DetailLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _EvidenceChip extends StatelessWidget {
  final EvidenceLevel level;
  const _EvidenceChip({required this.level});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Text(
        level.label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
