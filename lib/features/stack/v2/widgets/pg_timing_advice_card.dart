// PGTimingAdviceCard — Phase 11.7L.C.
//
// V2 stack timing advice surface. Same data, same rule-type vocabulary,
// same maxVisible cap:
//
//   * Cream `V2Colors.surface` card with a 4px accent-tint left
//     stripe — keeps the section visually "positive guidance"
//     (efficacy advice) rather than a warning.
//   * Mono-caps "TIMING · {N}" eyebrow + clear "Timing guidance"
//     title in v2 typography.
//   * Per-rule rows use accent / monitor / caution tints from
//     `V2Colors` instead of the retired v1 severity colors.
//   * "+N more timing tips" footer in mono-caps for parity with the
//     other v2 sections.
//
// Behavior preserves the production data contract — no data shape change.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_evidence_badge.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:url_launcher/url_launcher.dart';

class PGTimingAdviceCard extends StatelessWidget {
  const PGTimingAdviceCard({
    super.key,
    required this.optimizations,
    this.onTap,
    this.margin = EdgeInsets.zero,
    this.maxVisible = 3,
  });

  /// Timing optimizations from `StackSafetyReport.timingOptimizations`.
  /// Pre-sorted by priority — separations first, then take-with-food /
  /// empty-stomach, then time-of-day.
  final List<TimingOptimization> optimizations;

  /// Optional tap target if a future screen adds a full timing view.
  final VoidCallback? onTap;

  /// Outer margin — match the section above (typically the v2 safety
  /// banner) so vertical rhythm holds.
  final EdgeInsetsGeometry margin;

  /// Maximum number of timing items rendered inline before "+N more".
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (optimizations.isEmpty) return const SizedBox.shrink();

    final visible = optimizations.take(maxVisible).toList();

    final card = Container(
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: ColoredBox(
              color: V2Colors.accent,
              child: SizedBox(width: 4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(V2Spacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: V2Colors.accent,
                    ),
                    const SizedBox(width: V2Spacing.space8),
                    PGEyebrow(
                      'Timing  ·  ${optimizations.length}',
                      color: V2Colors.accent,
                    ),
                  ],
                ),
                const SizedBox(height: V2Spacing.space8),
                Text(
                  'Timing guidance',
                  style: V2Typography.titleSm(color: V2Colors.fg),
                ),
                const SizedBox(height: V2Spacing.space4),
                Text(
                  'When to take items in your stack for better spacing or absorption.',
                  style: V2Typography.bodySm(color: V2Colors.fgMuted),
                ),
                const SizedBox(height: V2Spacing.space12),
                ..._buildGroupedRows(context, visible),
                if (optimizations.length > maxVisible) ...[
                  const SizedBox(height: V2Spacing.space8),
                  _MoreTipsButton(
                    count: optimizations.length - maxVisible,
                    onTap: () => showAllTimingTipsSheet(context, optimizations),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: margin,
      child: onTap == null
          ? card
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                child: card,
              ),
            ),
    );
  }

  /// Render the visible rows, grouping separation rules under a
  /// "Space these apart" subsection. Separations sort first (see
  /// [optimizations]), so they're already contiguous at the front; the
  /// remaining with-food / time-of-day tips follow below.
  List<Widget> _buildGroupedRows(
    BuildContext context,
    List<TimingOptimization> visible,
  ) {
    final separations = visible
        .where((o) => o.ruleType == TimingRuleType.separate)
        .toList(growable: false);
    final others = visible
        .where((o) => o.ruleType != TimingRuleType.separate)
        .toList(growable: false);

    Widget rowFor(TimingOptimization opt) => _TimingRow(
          opt: opt,
          onTap: () => showTimingTipSheet(context, opt),
        );

    List<Widget> spacedRows(List<TimingOptimization> opts) {
      final out = <Widget>[];
      for (var i = 0; i < opts.length; i++) {
        out.add(rowFor(opts[i]));
        if (i < opts.length - 1) {
          out.add(const SizedBox(height: V2Spacing.space12));
        }
      }
      return out;
    }

    final widgets = <Widget>[];
    if (separations.isNotEmpty) {
      widgets.add(
        const Padding(
          key: Key('timing-separations-header'),
          padding: EdgeInsets.only(bottom: V2Spacing.space8),
          child: PGEyebrow('Space these apart', color: V2Colors.caution),
        ),
      );
      widgets.addAll(spacedRows(separations));
    }
    if (others.isNotEmpty) {
      // Visual break between the separation subsection and the rest.
      if (separations.isNotEmpty) {
        widgets.add(const SizedBox(height: V2Spacing.space12));
      }
      widgets.addAll(spacedRows(others));
    }
    return widgets;
  }
}

class _TimingRow extends StatelessWidget {
  const _TimingRow({required this.opt, this.onTap});

  final TimingOptimization opt;

  /// Opens this tip's detail sheet. Null in non-interactive contexts.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = _iconFor(opt.ruleType);
    final color = _colorFor(opt.ruleType);
    final contextText = _contextFor(opt);

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: V2Spacing.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _instructionFor(opt),
                style: V2Typography.bodySm(color: V2Colors.fg),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (contextText != null && contextText.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  contextText,
                  style: V2Typography.caption(color: V2Colors.fgMuted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: V2Spacing.space8),
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: V2Colors.fgSubtle,
            ),
          ),
        ],
      ],
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: V2Spacing.space4),
          child: row,
        ),
      ),
    );
  }

  /// Mono-caps section label for a rule type (used by the detail sheet).
  static String _ruleTypeLabel(TimingRuleType type) {
    switch (type) {
      case TimingRuleType.separate:
        return 'Separate';
      case TimingRuleType.takeTogether:
        return 'Take together';
      case TimingRuleType.takeWithFood:
        return 'With food';
      case TimingRuleType.takeOnEmptyStomach:
        return 'Empty stomach';
      case TimingRuleType.timeOfDay:
        return 'Time of day';
    }
  }

  static IconData _iconFor(TimingRuleType type) {
    switch (type) {
      case TimingRuleType.separate:
        return Icons.swap_horiz_rounded;
      case TimingRuleType.takeTogether:
        return Icons.link_rounded;
      case TimingRuleType.takeWithFood:
        return Icons.restaurant_rounded;
      case TimingRuleType.takeOnEmptyStomach:
        return Icons.no_food_rounded;
      case TimingRuleType.timeOfDay:
        return Icons.wb_sunny_rounded;
    }
  }

  /// V2 tint palette for each rule type. Separations carry the most
  /// weight (timing matters most) — render as caution. The rest are
  /// neutral / accent: positive optimization guidance, not warning.
  static Color _colorFor(TimingRuleType type) {
    switch (type) {
      case TimingRuleType.separate:
        return V2Colors.caution;
      case TimingRuleType.takeTogether:
        return V2Colors.accent;
      case TimingRuleType.takeWithFood:
      case TimingRuleType.takeOnEmptyStomach:
        return V2Colors.monitor;
      case TimingRuleType.timeOfDay:
        return V2Colors.fgMuted;
    }
  }

  static String _instructionFor(TimingOptimization opt) {
    final advice = opt.advice.trim();
    if (advice.isNotEmpty) return advice;

    final p1 = opt.product1Name ?? opt.ingredient1;
    final p2 = opt.product2Name ?? opt.ingredient2;
    switch (opt.ruleType) {
      case TimingRuleType.separate:
        return 'Take $p1 and $p2 separately';
      case TimingRuleType.takeTogether:
        return 'Take $p1 with $p2 for better absorption';
      case TimingRuleType.takeWithFood:
        return 'Take $p1 with a meal';
      case TimingRuleType.takeOnEmptyStomach:
        return 'Take $p1 on an empty stomach';
      case TimingRuleType.timeOfDay:
        return 'Consider timing $p1 earlier or later in the day.';
    }
  }

  /// Inline context under the instruction. We keep ONLY the actionable
  /// separation window ("Keep at least Nh apart.") here; the explanatory
  /// mechanism is folded into the detail sheet (tap the row) to keep the
  /// stack list compact. The full "why" still renders under "Why this
  /// matters" in [_TimingDetailSheet].
  static String? _contextFor(TimingOptimization opt) {
    final hours = opt.separationHours;
    return hours != null ? 'Keep at least ${hours}h apart.' : null;
  }
}

/// Tappable "+N more timing tips" footer — opens the full list sheet.
class _MoreTipsButton extends StatelessWidget {
  const _MoreTipsButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: V2Spacing.space4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '+$count more timing ${count == 1 ? 'tip' : 'tips'}',
                style: V2Typography.label(color: V2Colors.accent),
              ),
              const SizedBox(width: V2Spacing.space4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: V2Colors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the detail sheet for one timing tip — full advice, evidence
/// strength, separation window, the mechanism ("why"), and tappable
/// citations so the user can verify the claim.
Future<void> showTimingTipSheet(BuildContext context, TimingOptimization opt) {
  return PGModal.bottomSheet<void>(
    context: context,
    builder: (_) => _TimingDetailSheet(opt: opt),
  );
}

/// Opens a sheet listing every timing tip for the stack; each row opens its
/// own detail sheet.
Future<void> showAllTimingTipsSheet(
  BuildContext context,
  List<TimingOptimization> optimizations,
) {
  return PGModal.bottomSheet<void>(
    context: context,
    builder: (_) => _AllTimingTipsSheet(optimizations: optimizations),
  );
}

class _TimingDetailSheet extends StatelessWidget {
  const _TimingDetailSheet({required this.opt});

  final TimingOptimization opt;

  @override
  Widget build(BuildContext context) {
    final mechanism = opt.mechanism?.trim() ?? '';
    final hours = opt.separationHours;
    final sources = opt.sourceUrls;
    final productsLine = _productsLine(opt);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            PGEyebrow(
              _TimingRow._ruleTypeLabel(opt.ruleType),
              color: _TimingRow._colorFor(opt.ruleType),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              _TimingRow._instructionFor(opt),
              style: V2Typography.titleSm(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space12),
            Wrap(
              spacing: V2Spacing.space8,
              runSpacing: V2Spacing.space8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PGEvidenceBadge(level: opt.evidenceLevel),
                if (hours != null)
                  _DetailChip(
                    icon: Icons.schedule_rounded,
                    label: '${hours}h apart',
                  ),
              ],
            ),
            if (productsLine.isNotEmpty) ...[
              const SizedBox(height: V2Spacing.space12),
              Text(
                productsLine,
                style: V2Typography.bodySm(color: V2Colors.fgMuted),
              ),
            ],
            if (mechanism.isNotEmpty) ...[
              const SizedBox(height: V2Spacing.space16),
              Text(
                'Why this matters',
                style: V2Typography.label(color: V2Colors.fgMuted),
              ),
              const SizedBox(height: V2Spacing.space4),
              Text(
                mechanism,
                style: V2Typography.bodySm(
                  color: V2Colors.fg,
                ).copyWith(height: 1.45),
              ),
            ],
            if (sources.isNotEmpty) ...[
              const SizedBox(height: V2Spacing.space16),
              Text(
                'Sources',
                style: V2Typography.label(color: V2Colors.fgMuted),
              ),
              const SizedBox(height: V2Spacing.space8),
              for (final url in sources) _SourceLink(url: url),
            ],
          ],
        ),
      ),
    );
  }

  static String _productsLine(TimingOptimization opt) {
    final p1 = opt.product1Name;
    final p2 = opt.product2Name;
    if (p1 != null && p2 != null) return 'In your stack: $p1 and $p2';
    if (p1 != null) return 'In your stack: $p1';
    return '';
  }
}

class _AllTimingTipsSheet extends StatelessWidget {
  const _AllTimingTipsSheet({required this.optimizations});

  final List<TimingOptimization> optimizations;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          PGEyebrow(
            'Timing  ·  ${optimizations.length}',
            color: V2Colors.accent,
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'Timing guidance',
            style: V2Typography.titleSm(color: V2Colors.fg),
          ),
          const SizedBox(height: V2Spacing.space12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: optimizations.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: V2Spacing.space12),
              itemBuilder: (context, i) => _TimingRow(
                opt: optimizations[i],
                onTap: () => showTimingTipSheet(context, optimizations[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: V2Colors.caution.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: V2Colors.caution),
          const SizedBox(width: 5),
          Text(
            label,
            style: V2Typography.caption(
              color: V2Colors.caution,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SourceLink extends StatelessWidget {
  const _SourceLink({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space8),
      child: InkWell(
        onTap: () async {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.open_in_new_rounded,
                size: 13,
                color: V2Colors.accent,
              ),
            ),
            const SizedBox(width: V2Spacing.space8),
            Expanded(
              child: Text(
                _label(url),
                style: V2Typography.bodySm(
                  color: V2Colors.accent,
                ).copyWith(decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _label(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final host = uri.host.replaceFirst('www.', '');
    if (host.contains('pubmed')) {
      final id = uri.pathSegments.where((s) => s.isNotEmpty).join('/');
      return id.isEmpty ? 'PubMed' : 'PubMed · $id';
    }
    if (host.contains('ods.od.nih.gov')) {
      return 'NIH Office of Dietary Supplements';
    }
    if (host.contains('nccih.nih.gov')) return 'NCCIH';
    if (host.contains('lpi.oregonstate.edu')) return 'Linus Pauling Institute';
    if (host.contains('accessdata.fda.gov')) return 'FDA Drugs@FDA';
    return host;
  }
}
