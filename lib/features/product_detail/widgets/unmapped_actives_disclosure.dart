// UnmappedActivesDisclosure — surfaces the v1.3.2 transparency signal
// for ingredients the pipeline could not map to its quality reference
// data.
//
// The pipeline's coverage gate runs at 99.5% — it accepts releases with
// a small long-tail of unmapped ingredients (exotic branded extracts,
// typos, etc.) rather than block shipping. When that happens, those
// ingredient names DO appear on the label but are NOT counted in the
// scoring. Users deserve to know which ones, so we show this card.
//
// Data source: detail_blob.unmapped_actives, always present in v1.3.2+
// blobs (empty shape when nothing was unmapped):
//
//   {
//     "names": ["Exotic Extract", "Typo Ingredient"],
//     "total": 2,
//     "excluding_banned_exact_alias": 2
//   }
//
// The widget auto-hides when total is 0 or missing.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';

class UnmappedActivesDisclosure extends StatelessWidget {
  final Map<String, dynamic>? unmappedActives;

  const UnmappedActivesDisclosure({
    super.key,
    required this.unmappedActives,
  });

  @override
  Widget build(BuildContext context) {
    final blob = unmappedActives;
    if (blob == null) return const SizedBox.shrink();

    final total = _readInt(blob['total']);
    if (total == null || total <= 0) return const SizedBox.shrink();

    final names = _readNames(blob['names']);

    final resolved = AppColors.of(context);
    return Card(
      key: const Key('unmapped-actives-card'),
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: resolved.textSecondary,
                ),
                const SizedBox(width: AppTheme.space8),
                Expanded(
                  child: Text(
                    '$total ${_pluralize(total, 'ingredient', 'ingredients')} '
                    'could not be mapped',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: resolved.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space6),
            Text(
              'These ingredients appear on the label but were not '
              'recognized by our quality database, so they did NOT '
              'affect this product\'s score. The score reflects only '
              'the ingredients we could verify.',
              style: TextStyle(
                fontSize: 12,
                color: resolved.textSecondary,
                height: 1.4,
              ),
            ),
            if (names.isNotEmpty) ...[
              const SizedBox(height: AppTheme.space12),
              ...names.map(
                (name) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ',
                        style: TextStyle(
                          fontSize: 13,
                          color: resolved.textSecondary,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 13,
                            color: resolved.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Read an int that may have come in as int, double, or string from
  /// loose JSON. Returns null if the value can't be coerced.
  static int? _readInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is double) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  /// jsonDecode emits `List<dynamic>`; convert each element to a string
  /// safely so the widget never crashes on type drift.
  static List<String> _readNames(dynamic raw) {
    if (raw is List) {
      return raw
          .where((e) => e != null)
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  static String _pluralize(int n, String singular, String plural) =>
      n == 1 ? singular : plural;
}
