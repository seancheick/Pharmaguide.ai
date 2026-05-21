// Phase 11.7f — TransparencyFooter section adapter (S17).
//
// V2 mirror of the inline `PGTransparencyFooter()` call. The footer
// stays site-wide trust language, but reads `catalogInfoProvider` for
// the real "Updated <Mon DD, YYYY>" freshness label — same pattern the
// v2 home screen's `_CitationStrip` already uses.
//
// Architecture note: keeps the connected screen orchestration-only by
// extracting the catalog-info watch into a dedicated ConsumerWidget.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/components/pg_transparency_footer.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

/// TransparencyFooter section — site-wide trust language with the real
/// catalog freshness label. Always renders.
class TransparencyFooterSection extends ConsumerWidget {
  const TransparencyFooterSection({super.key});

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _formatDate(DateTime d) =>
      'Updated ${_months[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(catalogInfoProvider);
    final info = catalogAsync.asData?.value;
    final freshness = info?.buildDate != null
        ? _formatDate(info!.buildDate!)
        : null;
    return PGTransparencyFooter(freshnessLabel: freshness);
  }
}
