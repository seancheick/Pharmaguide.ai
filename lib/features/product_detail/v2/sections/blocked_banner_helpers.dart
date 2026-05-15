// Phase 11.7c.1 — Blocked-banner helpers (pure).
//
// Pure data helpers for the v2 blocked banner. No widget refs, no
// theme refs — all logic is testable with hand-built inputs.
//
// Why split from `blocked_banner_section.dart`: the widget composition
// is ~150 lines on its own; combined with the helpers it would exceed
// the 250-line/section ceiling Sean set. Keeping logic and widgets
// in separate files preserves the testability promise.
//
// Three production-side helpers are inlined verbatim:
//   • `parseTopWarnings` — JSON-decode of `_product.topWarnings`
//     (was `_ProductDetailScreenState._topWarnings`)
//   • `humanizeBlockingReason` — enum-to-sentence mapping (was
//     `_humanizeBlockingReason` top-level in product_detail_screen)
//   • `extractFdaLinks` — drain FDA / recall URLs from a warnings list
//     (was `_BlockedBanner._extractFdaLinks` static method)
// Phase 11.11 cleanup extracts the production copies too so both
// screens share these.

import 'dart:convert';

import 'package:pharmaguide/data/database/core_database.dart';

/// JSON-decode `_product.topWarnings` into a list of warning maps.
/// Returns empty list on null, empty string, or malformed JSON.
///
/// Verbatim port of production's `_ProductDetailScreenState._topWarnings`.
List<Map<String, dynamic>> parseTopWarnings(ProductsCoreData? product) {
  final raw = product?.topWarnings;
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  } on FormatException {
    return const [];
  }
}

/// Map the pipeline's coarse `blocking_reason` enum to user-facing
/// copy. Falls back to sentence-case of the raw token so a future
/// pipeline-side new code never leaks raw to the UI.
///
/// Verbatim port of production's top-level `_humanizeBlockingReason`.
String humanizeBlockingReason(String code) {
  switch (code.trim().toLowerCase()) {
    case 'banned_ingredient':
      // Mirrors the BLOCKED verdict's notes from verdict_vocab.json:
      // "Product contains a banned, recalled, or otherwise prohibited
      // substance."
      return 'Contains a banned, recalled, or otherwise prohibited substance.';
    case '':
      return '';
  }
  final spaced = code.replaceAll('_', ' ').trim();
  if (spaced.isEmpty) return '';
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// Drain FDA / recall URLs from a top-warnings list. Used as a
/// fallback when `bannedSubstanceDetail.source_urls` is absent —
/// surfaces existing FDA recall notices on multi-warning products.
///
/// Verbatim port of production's `_BlockedBanner._extractFdaLinks`.
List<String> extractFdaLinks(List<Map<String, dynamic>> warnings) {
  final links = <String>[];
  for (final w in warnings) {
    final urls = w['source_urls'];
    if (urls is List) {
      for (final u in urls) {
        final str = u.toString();
        if (str.contains('fda.gov') || str.contains('recall')) {
          links.add(str);
        }
      }
    }
  }
  return links;
}

/// Pick which FDA links to display. Mirrors production's preference
/// order (Sprint C, 2026-05-13):
///   1. `bannedSubstanceDetail.source_urls` — the specific citation
///      set for THIS banned substance (preferred)
///   2. FDA / recall links extracted from `topWarnings` — fallback
///      so existing recall notices on multi-warning products surface
List<String> chooseFdaLinks({
  required Map<String, dynamic>? bannedSubstanceDetail,
  required List<Map<String, dynamic>> topWarnings,
}) {
  final bsdSourceUrls = (bannedSubstanceDetail?['source_urls'] as List?)
      ?.whereType<String>()
      .map((u) => u.trim())
      .where((u) => u.isNotEmpty)
      .toList(growable: false);
  if (bsdSourceUrls != null && bsdSourceUrls.isNotEmpty) {
    return bsdSourceUrls;
  }
  return extractFdaLinks(topWarnings);
}

/// Resolve the banner body copy. Three tiers, in order of richness:
///   1. Pipeline-emitted one-liner (authored layperson sentence)
///   2. Substance-specific phrasing when we know the substance name
///      but no authored one-liner is present
///   3. Humanized blocking_reason enum — last-resort fallback that
///      replaces the raw token with prose
///
/// Mirrors production's `_BlockedBanner.build()` reasonBody logic
/// (lines 1675–1691).
String resolveBlockedReasonBody({
  required String? oneLiner,
  required String? substanceName,
  required String blockingReason,
}) {
  if (oneLiner != null && oneLiner.isNotEmpty) {
    return oneLiner;
  }
  if (substanceName != null && substanceName.isNotEmpty) {
    // Brand-attributed phrasing per Sean's 2026-05 product-tone
    // guidelines — surfaces PharmaGuide as the agent making the
    // recommendation rather than implying a voice-from-nowhere.
    return 'Reason: Contains $substanceName, '
        'which PharmaGuide flags as not recommended.';
  }
  final humanized = humanizeBlockingReason(blockingReason);
  return humanized.isNotEmpty
      ? 'Reason: $humanized'
      : 'PharmaGuide flagged this product on safety grounds.';
}
