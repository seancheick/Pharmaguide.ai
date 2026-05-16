// Phase 11.7e — HeavyMetal section adapter (S12).
//
// V2 mirror of production's `HeavyMetalWarningCard`
// (lib/features/product_detail/widgets/heavy_metal_warning_card.dart).
//
// Production reads `heavy_metal_detail.signals[]` — each signal has
// `ingredient`, `limit_source`, `risk_level`, `notes`. Section auto-
// suppresses when the blob is null or signals list is empty.
//
// V2 PGHeavyMetalWarning takes a flattened metals list + optional note.
// We extract ingredient names from each signal, and use the production
// source-footnote copy as the note ("Source: Prop 65 / EPA reference
// doses. Applies to raw materials from certain origins.").

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_heavy_metal_warning.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';

/// Build the HeavyMetal section. Returns `SizedBox.shrink()` when the
/// blob is null or contains no signals.
Widget buildHeavyMetalSection({
  required Map<String, dynamic>? heavyMetalDetail,
}) {
  if (heavyMetalDetail == null) return const SizedBox.shrink();
  final signals = heavyMetalDetail.safeMapList('signals');
  if (signals.isEmpty) return const SizedBox.shrink();

  final metals = signals
      .map((s) => s['ingredient']?.toString().trim() ?? '')
      .where((n) => n.isNotEmpty)
      .toList(growable: false);

  if (metals.isEmpty) return const SizedBox.shrink();

  return PGHeavyMetalWarning(
    metals: metals,
    note:
        'Source: Prop 65 / EPA reference doses. Applies to raw '
        'materials from certain origins.',
  );
}
