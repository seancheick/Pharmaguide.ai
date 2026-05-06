// "Label confidence" card — replaces UnknownIngredientBanner +
// BlendWarningBanner + ProductStatusChip + UnmappedActivesDisclosure.
//
// Sprint: docs/sprints/product_detail_page_sprint.md — T3.
//
// Single neutral / amber card listing every label-quality caveat in
// one place. Never red — recalled / banned products go through the
// hero BlockedBanner. This card answers "how much do we know about
// this label?", not "is this product unsafe?".

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';

class LabelConfidenceCard extends StatefulWidget {
  /// `_product.mappedCoverage` (0..1).
  final double mappedCoverage;

  /// `detailBlob.proprietary_blend_detail.has_proprietary_blends`.
  final bool hasProprietaryBlends;

  /// `detailBlob.product_status` — `{type, date, display}`. May be null.
  final Map<String, dynamic>? productStatus;

  /// `detailBlob.unmapped_actives` — `{total, names, excluding_banned_exact_alias}`.
  /// May be null.
  final Map<String, dynamic>? unmappedActives;

  /// True when `_product.score100Equivalent == null && !isBlocked`, i.e.
  /// the verdict is `NOT_SCORED`.
  final bool isNotScored;

  const LabelConfidenceCard({
    super.key,
    required this.mappedCoverage,
    required this.hasProprietaryBlends,
    required this.isNotScored,
    this.productStatus,
    this.unmappedActives,
  });

  /// Returns true when this card should render at all. Used by the
  /// screen to decide whether to wrap the sliver — keeps the visual
  /// padding consistent (no empty SizedBox slots between sections).
  static bool hasAnySignal({
    required double mappedCoverage,
    required bool hasProprietaryBlends,
    required bool isNotScored,
    Map<String, dynamic>? productStatus,
    Map<String, dynamic>? unmappedActives,
  }) {
    if (isNotScored) return true;
    if (mappedCoverage < 0.5) return true;
    if (hasProprietaryBlends) return true;
    if (_unmappedTotal(unmappedActives) > 0) return true;
    if (_productStatusLabel(productStatus) != null) return true;
    return false;
  }

  @override
  State<LabelConfidenceCard> createState() => _LabelConfidenceCardState();
}

class _LabelConfidenceCardState extends State<LabelConfidenceCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final hasAnySignal = LabelConfidenceCard.hasAnySignal(
      mappedCoverage: widget.mappedCoverage,
      hasProprietaryBlends: widget.hasProprietaryBlends,
      isNotScored: widget.isNotScored,
      productStatus: widget.productStatus,
      unmappedActives: widget.unmappedActives,
    );
    if (!hasAnySignal) return const SizedBox.shrink();

    final tier = _computeTier(
      mappedCoverage: widget.mappedCoverage,
      hasProprietaryBlends: widget.hasProprietaryBlends,
      isNotScored: widget.isNotScored,
      unmappedActives: widget.unmappedActives,
    );
    final tierColor = tier == _Tier.note
        ? scheme.onSurfaceVariant
        : AppTheme.severityCaution;
    final tierLabel = _tierLabel(tier);
    final headerPrefix = _headerPrefix(tier);
    final headerText = tier == _Tier.note
        ? 'Product note'
        : '$headerPrefix $tierLabel';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        0,
        AppTheme.space20,
        AppTheme.space12,
      ),
      child: PGCard(
        variant: PGCardVariant.plain,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space16,
                vertical: AppTheme.space12,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: tierColor,
                  ),
                  const SizedBox(width: AppTheme.space12),
                  Expanded(
                    child: Text(
                      headerText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
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
                  if (widget.isNotScored)
                    const _Row(
                      icon: Icons.help_outline_rounded,
                      title: 'Not enough verified data to score',
                      body: 'The label data we have is too incomplete to '
                          'produce a reliable score for this product.',
                    ),
                  if (widget.mappedCoverage < 0.5)
                    _Row(
                      icon: Icons.warning_amber_rounded,
                      title: widget.mappedCoverage < 0.3
                          ? 'Limited label data available'
                          : 'Some ingredients could not be fully verified',
                      body: widget.mappedCoverage < 0.3
                          ? 'We could not match enough of this label to our '
                                'reference data to assess it confidently.'
                          : 'A portion of this label did not match our '
                                'reference data, so the analysis may miss '
                                'some context.',
                    ),
                  if (widget.hasProprietaryBlends)
                    const _Row(
                      icon: Icons.visibility_off_outlined,
                      title: 'Blend amounts not disclosed',
                      body: 'This product lists a proprietary blend, so '
                          'individual ingredient doses are hidden. Our '
                          'analysis cannot evaluate per-ingredient amounts.',
                    ),
                  if (_unmappedTotal(widget.unmappedActives) >
                      0)
                    _Row(
                      icon: Icons.help_center_outlined,
                      title:
                          '${_unmappedTotal(widget.unmappedActives)} '
                          '${_pluralize(
                            _unmappedTotal(widget.unmappedActives),
                            'ingredient',
                            'ingredients',
                          )} '
                          'could not be mapped',
                      body: 'These appear on the label but were not in our '
                          'reference data, so they did not affect the score.',
                      detail: _unmappedNames(widget.unmappedActives),
                    ),
                  if (_productStatusLabel(
                          widget.productStatus) !=
                      null)
                    _StatusRow(productStatus: widget.productStatus!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tier helpers
// ---------------------------------------------------------------------------

enum _Tier { note, partial, limited }

_Tier _computeTier({
  required double mappedCoverage,
  required bool hasProprietaryBlends,
  required bool isNotScored,
  Map<String, dynamic>? unmappedActives,
}) {
  if (isNotScored || mappedCoverage < 0.3) return _Tier.limited;
  if (mappedCoverage < 0.5) return _Tier.partial;
  if (hasProprietaryBlends) return _Tier.partial;
  if (_unmappedTotal(unmappedActives) > 0) return _Tier.partial;
  // No data-quality issue — only signal is product_status (e.g.
  // discontinued). Status is informational, NOT a label-confidence
  // problem. A 100%-covered discontinued product should not read
  // "Label confidence: Partial".
  return _Tier.note;
}

String _tierLabel(_Tier tier) {
  switch (tier) {
    case _Tier.note:
      return 'Note';
    case _Tier.partial:
      return 'Partial';
    case _Tier.limited:
      return 'Limited';
  }
}

String _headerPrefix(_Tier tier) {
  // Status-only renders as "Product note", not "Label confidence: Note".
  // The card body shows a single status row in that case.
  return tier == _Tier.note ? 'Product' : 'Label confidence:';
}

// ---------------------------------------------------------------------------
// Top-level helpers shared between hasAnySignal() and the build method.
// ---------------------------------------------------------------------------

int _unmappedTotal(Map<String, dynamic>? blob) {
  final raw = blob?['total'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? 0;
  return 0;
}

const _kTypeLabels = <String, String>{
  'discontinued': 'Product discontinued',
  'off_market': 'Off market',
  'reformulated': 'Reformulated',
  'limited_availability': 'Limited availability',
  'seasonal': 'Seasonal product',
};

String? _productStatusLabel(Map<String, dynamic>? blob) {
  if (blob == null) return null;
  final display = blob['display']?.toString().trim();
  final type = blob['type']?.toString().trim().toLowerCase();
  final rawDate = blob['date']?.toString().trim();
  final leadIn = type == null ? null : _kTypeLabels[type];
  if (leadIn != null && rawDate != null && rawDate.isNotEmpty) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed != null) {
      return '$leadIn · ${DateFormat.yMMMd().format(parsed)}';
    }
  }
  if (display != null && display.isNotEmpty) return display;
  return null;
}

// ---------------------------------------------------------------------------
// Sub-rows
// ---------------------------------------------------------------------------

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  /// Optional secondary line — used to spell out unmapped ingredient names.
  final String? detail;

  const _Row({
    required this.icon,
    required this.title,
    required this.body,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppTheme.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final Map<String, dynamic> productStatus;

  const _StatusRow({required this.productStatus});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = _productStatusLabel(productStatus)!;
    final type = productStatus['type']?.toString().trim().toLowerCase();

    return PGPressable(
      onTap: () => PGModal.bottomSheet<void>(
        context: context,
        showDragHandle: false,
        builder: (_) => _ProductStatusExplanationSheet(type: type),
      ),
      pressedScale: 0.98,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.space12),
        child: Row(
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppTheme.space8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lifted from product_status_chip.dart — kept verbatim copy because that
// file is being deleted in this same task.
// ---------------------------------------------------------------------------

class _ProductStatusExplanationSheet extends StatelessWidget {
  final String? type;

  const _ProductStatusExplanationSheet({this.type});

  String _bodyCopy() {
    switch (type) {
      case 'reformulated':
        return 'This product has been reformulated. Ingredients, doses, or '
            'inactive components may differ from older bottles, so rescan '
            'the exact version you have in hand.';
      case 'off_market':
        return 'This product appears to be off market or no longer broadly '
            'available. That does not automatically mean it is unsafe, but '
            'availability and listing details may be outdated.';
      case 'limited_availability':
        return 'This product has limited availability. Listing, stock, or '
            'distribution details may change faster than usual.';
      case 'seasonal':
        return 'This product appears to be seasonal. Availability may vary '
            'throughout the year, and newer lots may differ from older ones.';
      case 'discontinued':
      default:
        return 'This product is no longer manufactured. Formulas may have '
            'changed or been replaced in newer versions.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        AppTheme.space16,
        AppTheme.space20,
        AppTheme.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About this product status',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.space12),
          Text(
            _bodyCopy(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

String _pluralize(int n, String singular, String plural) =>
    n == 1 ? singular : plural;

String? _unmappedNames(Map<String, dynamic>? blob) {
  final raw = blob?['names'];
  if (raw is! List) return null;
  final names = raw
      .map((e) => e.toString().trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  if (names.isEmpty) return null;
  return names.length <= 4
      ? names.join(', ')
      : '${names.take(3).join(', ')} and ${names.length - 3} more';
}
