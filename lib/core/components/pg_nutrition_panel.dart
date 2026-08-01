import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One nutrition-facts row — typically a single macro/micro with its
/// per-serving amount + %DV. Mirrors production's `NutritionPanel`
/// row shape.
class PGNutritionFact {
  final String label;
  final String value;

  /// %DV string ("12% DV" / null when unknown).
  final String? dailyValue;

  /// True for headline rows (Calories, Total Fat, Total Carbs) that
  /// production renders with bold weight + heavier divider.
  final bool isHeadline;

  /// Source-label nesting depth for subordinate facts such as saturated or
  /// polyunsaturated fat. The panel uses one modest indent as the hierarchy
  /// cue without changing the label text.
  final int indentLevel;

  const PGNutritionFact({
    required this.label,
    required this.value,
    this.dailyValue,
    this.isHeadline = false,
    this.indentLevel = 0,
  });
}

/// v2 nutrition facts panel.
///
/// Compact supplement-facts panel — name + amount + %DV. Hidden when
/// there's no nutrition data.
class PGNutritionPanel extends StatefulWidget {
  /// Optional kcal per serving — production renders this as the first
  /// row in bold.
  final int? caloriesPerServing;

  /// Nutrition fact rows in label order (caller respects the FDA
  /// nutrition-facts ordering convention).
  final List<PGNutritionFact> facts;

  final String title;
  final String? servingSize;
  final bool collapsible;
  final bool initiallyExpanded;
  final bool embedded;

  const PGNutritionPanel({
    super.key,
    this.caloriesPerServing,
    this.facts = const [],
    this.title = 'Nutrition facts',
    this.servingSize,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.embedded = false,
  });

  @override
  State<PGNutritionPanel> createState() => _PGNutritionPanelState();
}

class _PGNutritionPanelState extends State<PGNutritionPanel> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = !widget.collapsible || widget.initiallyExpanded;
  }

  void _toggle() {
    if (!widget.collapsible) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.facts.isEmpty && widget.caloriesPerServing == null) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: widget.embedded
          ? EdgeInsets.zero
          : const EdgeInsets.all(V2Spacing.space16),
      decoration: widget.embedded
          ? null
          : BoxDecoration(
              color: context.v2.surface,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: context.v2.outline),
              boxShadow: V2Shadows.sm,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: widget.collapsible,
            expanded: widget.collapsible ? _expanded : null,
            label: widget.title,
            onTap: widget.collapsible ? _toggle : null,
            excludeSemantics: true,
            child: InkWell(
              onTap: widget.collapsible ? _toggle : null,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: V2Typography.titleSm(color: context.v2.fg),
                      ),
                    ),
                    if (widget.collapsible)
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 22,
                          color: context.v2.fgMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.servingSize != null) ...[
                        Text(
                          'Serving size · ${widget.servingSize}',
                          style: V2Typography.caption(color: context.v2.fgMuted),
                        ),
                      ],
                      const SizedBox(height: V2Spacing.space8),
                      if (widget.caloriesPerServing != null)
                        _NutritionRow(
                          fact: PGNutritionFact(
                            label: 'Calories',
                            value: '${widget.caloriesPerServing}',
                            isHeadline: true,
                          ),
                          isLast: widget.facts.isEmpty,
                        ),
                      for (var i = 0; i < widget.facts.length; i++)
                        _NutritionRow(
                          fact: widget.facts[i],
                          isLast: i == widget.facts.length - 1,
                        ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _NutritionRow extends StatelessWidget {
  final PGNutritionFact fact;
  final bool isLast;

  const _NutritionRow({required this.fact, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final labelStyle = fact.isHeadline
        ? V2Typography.bodyMedium(color: context.v2.fg)
        : V2Typography.bodySm(color: context.v2.fg);
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: context.v2.outline, width: 0.4),
              ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: V2Spacing.space8),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: fact.indentLevel > 0 ? V2Spacing.space12 : 0,
                ),
                child: Text(fact.label, style: labelStyle),
              ),
            ),
            Text(fact.value, style: V2Typography.monoData(color: context.v2.fg)),
            if (fact.dailyValue != null) ...[
              const SizedBox(width: V2Spacing.space12),
              SizedBox(
                width: 56,
                child: Text(
                  fact.dailyValue!,
                  textAlign: TextAlign.right,
                  style: V2Typography.monoData(color: context.v2.fgMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
