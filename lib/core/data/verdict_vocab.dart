// Verdict vocab loader.
//
// Pipeline source: scripts/data/verdict_vocab.json. Catalog safety status and
// quality tier are separate contracts; this vocabulary displays warnings and
// retains legacy SAFE/POOR labels for cached catalogs. It does not determine
// product safety, quality, score eligibility, or personalized medical safety.
//
// Loaded once at first call to `loadVerdictVocab()`; subsequent calls
// return the cached value. The cache is process-lifetime — there is
// no invalidation API because vocab updates ship via app release,
// never at runtime.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// One vocab entry — a single verdict with the full DISPLAY CONTRACT
/// (name + short_label + tone + ui_color + ui_icon + action + notes).
///
/// Labels preserve the pipeline display contract. Typed catalog safety and
/// ScoreTier own current safety and quality rendering respectively; legacy
/// vocabulary metadata must never infer either assessment.
class VerdictEntry {
  /// Stable UPPER_SNAKE ID emitted by the pipeline scoring engine.
  /// Safety disposition or a legacy cached mixed-verdict identifier.
  final String id;

  /// Full user-facing label (sentence case), e.g. "Safe".
  /// Shown in detail screens and full-text contexts.
  final String name;

  /// Compact chip / pill label (≤12 chars), e.g. "Caution".
  /// Shown in search-result tiles and dense list views.
  final String shortLabel;

  /// Semantic intent — one of: positive, neutral, info, warning, danger.
  /// Theming primitive; Flutter resolves to concrete color/text styles.
  final String tone;

  /// Color hint — one of: green, blue, gray, yellow, orange, red.
  /// Flutter resolves this semantic hint through the active v2 surface.
  final String uiColor;

  /// Icon hint — one of: check, info, warning, alert, block.
  /// Flutter resolves to an icon asset.
  final String uiIcon;

  /// Suggested user action verb-phrase (≤40 chars), e.g. "Do not use".
  /// Shown beneath the verdict in product detail.
  final String action;

  /// ≤200-char plain-English description shown in tap-to-learn modal.
  final String notes;

  const VerdictEntry({
    required this.id,
    required this.name,
    required this.shortLabel,
    required this.tone,
    required this.uiColor,
    required this.uiIcon,
    required this.action,
    required this.notes,
  });

  factory VerdictEntry.fromJson(Map<String, dynamic> json) {
    return VerdictEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      shortLabel: json['short_label']?.toString() ?? '',
      tone: json['tone']?.toString() ?? '',
      uiColor: json['ui_color']?.toString() ?? '',
      uiIcon: json['ui_icon']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
    );
  }
}

/// Process-lifetime cache. First call to `loadVerdictVocab` hits the
/// asset bundle, builds the index, and stores it here.
Map<String, VerdictEntry>? _cache;

/// Load the vocab from `assets/data/verdict_vocab.json` and return a
/// `Map<id, VerdictEntry>` for O(1) lookup. Cached after first call.
///
/// The vocab is gated by
/// `tests/test_verdict_vocab_contract.py` pipeline-side, so a malformed
/// asset here means a release-bundle integrity bug, not a runtime data
/// error.
Future<Map<String, VerdictEntry>> loadVerdictVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString('assets/data/verdict_vocab.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['verdicts'] as List?) ?? const [];

  final byId = <String, VerdictEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final v = VerdictEntry.fromJson(entry);
    if (v.id.isEmpty) continue;
    byId[v.id] = v;
  }

  _cache = byId;
  return byId;
}

/// Test seam — overrides the cache so widget tests can pump fixture
/// vocabs without hitting the asset bundle.
void debugSetVerdictVocabForTesting(Map<String, VerdictEntry>? value) {
  _cache = value;
}
