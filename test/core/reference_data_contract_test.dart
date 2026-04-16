import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contract tests for the bundled reference-data JSON assets.
///
/// These guard against the #1 silent-breakage footgun: accidentally
/// direct-copying a pipeline-produced file (which uses a *different*
/// top-level key) over the Flutter asset. The app consumers key off
/// specific top-level lists; if those become null, the UI silently
/// renders empty — never throws — and users lose safety signals.
///
/// The Flutter schema intentionally diverges from pipeline v5.0:
///   synergy_cluster.json        pipeline: `synergy_clusters` -> Flutter: `clusters`
///   banned_recalled_ingredients pipeline: `ingredients`      -> Flutter: `recalled_ingredients`
///
/// If these tests fail, DO NOT fix them by changing the tests. The
/// asset file has been replaced with an incompatible schema. Re-run
/// the pipeline-to-Flutter remap (scripts/remap_reference_data or the
/// orchestrator-driven transform) before committing.
void main() {
  group('reference data asset contract', () {
    test('synergy_cluster.json exposes non-empty "clusters" list', () {
      final file = File('assets/reference_data/synergy_cluster.json');
      expect(file.existsSync(), isTrue,
          reason: 'Bundled synergy asset missing at ${file.path}');

      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      expect(decoded['clusters'], isNotNull,
          reason:
              'Flutter asset MUST use top-level key "clusters". If it has '
              '"synergy_clusters" instead, a raw pipeline file was copied '
              'in — consumers at lib/features/stack/providers/synergy_report_provider.dart '
              'and lib/features/product_detail/providers/pairs_well_provider.dart '
              'read clustersData["clusters"] and will silently render empty.');
      expect(decoded['clusters'], isA<List<dynamic>>(),
          reason: '"clusters" must be a JSON array');

      final clusters = decoded['clusters'] as List<dynamic>;
      expect(clusters, isNotEmpty,
          reason: 'Synergy clusters list is empty — every product loses '
              'synergy bonus scoring.');

      // Guard against accidental direct-copy of pipeline file: the
      // pipeline's top-level key must NOT be present.
      expect(decoded.containsKey('synergy_clusters'), isFalse,
          reason:
              'Pipeline-shaped key "synergy_clusters" found alongside "clusters". '
              'This asset was direct-copied from the pipeline — re-run the remap.');

      // Spot-check the first entry has the exact field names Flutter
      // consumers read. Using only the narrow set the providers rely on.
      final first = clusters.first as Map<String, dynamic>;
      expect(first, containsPair('cluster_id', isA<String>()));
      expect(first, containsPair('name', isA<String>()));
      expect(first, containsPair('ingredients', isA<List<dynamic>>()));
      expect(first, containsPair('evidence_tier', isA<String>()));
      expect(first, containsPair('mechanism', isA<String>()));
      expect(first, containsPair('bonus_points', isA<num>()));
      expect(first, containsPair('citations', isA<List<dynamic>>()));
    });

    test('banned_recalled_ingredients.json exposes non-empty '
        '"recalled_ingredients" list', () {
      final file =
          File('assets/reference_data/banned_recalled_ingredients.json');
      expect(file.existsSync(), isTrue,
          reason: 'Bundled recall asset missing at ${file.path}');

      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      expect(decoded['recalled_ingredients'], isNotNull,
          reason:
              'Flutter asset MUST use top-level key "recalled_ingredients". '
              'If it has "ingredients" instead, a raw pipeline file was copied '
              'in — the stack safety provider at '
              'lib/features/stack/providers/stack_safety_providers.dart '
              'reads recallData["recalled_ingredients"] and will silently '
              'skip every banned-ingredient check.');
      expect(decoded['recalled_ingredients'], isA<List<dynamic>>(),
          reason: '"recalled_ingredients" must be a JSON array');

      final entries = decoded['recalled_ingredients'] as List<dynamic>;
      expect(entries, isNotEmpty,
          reason: 'Recalled ingredients list is empty — the stack safety '
              'check cannot flag banned substances.');

      // Guard against accidental direct-copy of pipeline file: the
      // pipeline's bare top-level key must NOT be present.
      expect(decoded.containsKey('ingredients'), isFalse,
          reason:
              'Pipeline-shaped key "ingredients" found alongside "recalled_ingredients". '
              'This asset was direct-copied from the pipeline — re-run the remap.');

      // Spot-check the first entry has the exact field names Flutter
      // consumers read at stack_safety_providers.dart:358-398.
      //
      // NOTE: `warning_message` was REMOVED in Sprint 27.6 after audit
      // found derived strings were medically incorrect for ~30-40 entries.
      // Do NOT re-add this assertion until the pipeline-side
      // `safety_warning` + `safety_warning_one_liner` + `ban_context`
      // fields are authored upstream (Sprint 27.6 Path C). When they
      // land, assert the new fields here AND assert `warning_message`
      // is still ABSENT (guards against the old derivation creeping back).
      final first = entries.first as Map<String, dynamic>;
      expect(first, containsPair('canonical_id', isA<String>()));
      expect(first, containsPair('common_names', isA<List<dynamic>>()));
      expect(first, containsPair('recall_status', isA<String>()));
      expect(first, containsPair('regulatory_basis', isA<String>()));
      expect(first, containsPair('reason', isA<String>()));
      expect(first, containsPair('effective_date', isA<String>()));
      expect(first, containsPair('severity', isA<String>()));

      // Sprint 27.6: enforce that the removed field does NOT come back
      // as a silent derivation. Any re-introduction MUST be accompanied
      // by pipeline-side authored content (see Path C in SPRINT_TRACKER).
      expect(first.containsKey('warning_message'), isFalse,
          reason:
              'warning_message was removed in Sprint 27.6 (derived strings '
              'were medically incorrect). Re-introduction requires pipeline-side '
              'authoring with safety-team sign-off, NOT Flutter-side derivation '
              'from `reason`. See SPRINT_TRACKER.md Sprint 27.6 Path C.');
    });
  });
}
