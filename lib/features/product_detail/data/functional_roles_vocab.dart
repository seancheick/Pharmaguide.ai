// Functional-roles vocab loader.
//
// Pipeline contract (clinician-locked v1.0.0, schema in pipeline
// repo `scripts/DATABASE_SCHEMA.md` § 13b):
//
//   {
//     "schema_version": "1.0.0",
//     "functional_roles": [
//       {
//         "id": "lubricant",
//         "name": "Lubricant",
//         "notes": "≤ 200-char user-facing description...",
//         "regulatory_references": [
//           {"jurisdiction": "FDA", "code": "21 CFR 170.3(o)(18)"},
//           {"jurisdiction": "EU",  "code": "E470a"}
//         ],
//         "examples": ["magnesium stearate", "stearic acid"]
//       },
//       ...
//     ]
//   }
//
// 32 entries, locked. Updates require a clinician sign-off cycle and
// a new app release. Bundled as a static asset (not per-blob) per the
// 2026-04-30 handoff doc.
//
// Loaded once at first call to `loadFunctionalRolesVocab()`; subsequent
// calls return the cached value. The cache is process-lifetime — there
// is no invalidation API because vocab updates ship via app release,
// never at runtime.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// One regulatory reference attached to a role. Tappable "Learn more"
/// link in the modal — `jurisdiction` "FDA" deep-links to the eCFR for
/// the given `code`; "EU" deep-links to eur-lex.
class RegulatoryReference {
  final String jurisdiction;
  final String code;
  const RegulatoryReference({required this.jurisdiction, required this.code});

  factory RegulatoryReference.fromJson(Map<String, dynamic> json) {
    return RegulatoryReference(
      jurisdiction: json['jurisdiction']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
    );
  }
}

/// One vocab entry — a single functional role with display-ready
/// content for the tap modal.
///
/// Critical UX rule (clinician-locked): show `name` + `notes` verbatim.
/// Never paraphrase — every line was reviewed for clinical accuracy
/// and consumer framing.
class FunctionalRole {
  /// Stable snake_case ID — matches values in
  /// `inactive_ingredients[].functional_roles[]`.
  final String id;

  /// User-facing role label (chip / title), e.g. "Lubricant".
  final String name;

  /// ≤200-char plain-English description shown in the tap modal body.
  final String notes;

  /// Tappable "Learn more" links rendered as deep links to FDA CFR
  /// and EU E-numbers.
  final List<RegulatoryReference> regulatoryReferences;

  /// 1-5 ingredient names users might recognize on labels — render
  /// as a small chip list under the body copy.
  final List<String> examples;

  const FunctionalRole({
    required this.id,
    required this.name,
    required this.notes,
    required this.regulatoryReferences,
    required this.examples,
  });

  factory FunctionalRole.fromJson(Map<String, dynamic> json) {
    return FunctionalRole(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      regulatoryReferences: (json['regulatory_references'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(RegulatoryReference.fromJson)
              .toList(growable: false) ??
          const [],
      examples: (json['examples'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
    );
  }
}

/// Process-lifetime cache. First call to `loadFunctionalRolesVocab`
/// hits the asset bundle, builds the index, and stores it here.
Map<String, FunctionalRole>? _cache;

/// Load the vocab from `assets/data/functional_roles_vocab.json` and
/// return a `Map<id, FunctionalRole>` for O(1) lookup. Cached after
/// first call.
///
/// Throws `FlutterError` if the asset is missing — bundling is
/// non-optional, the pipeline contract requires it. The vocab itself
/// is gated by `tests/test_functional_roles_vocab_contract.py`
/// pipeline-side, so a malformed asset here means a release-bundle
/// integrity bug, not a runtime data error.
Future<Map<String, FunctionalRole>> loadFunctionalRolesVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/functional_roles_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['functional_roles'] as List?) ?? const [];

  final byId = <String, FunctionalRole>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final role = FunctionalRole.fromJson(entry);
    if (role.id.isEmpty) continue;
    byId[role.id] = role;
  }

  _cache = byId;
  return byId;
}

/// Test seam — overrides the cache so widget tests can pump fixture
/// vocabs without hitting the asset bundle.
void debugSetFunctionalRolesVocabForTesting(
  Map<String, FunctionalRole>? value,
) {
  _cache = value;
}
