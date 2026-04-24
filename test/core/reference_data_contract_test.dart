import 'dart:convert';
import 'dart:io';

import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract tests for the bundled reference-data JSON assets.
///
/// These guard against silent-breakage footguns in reference data.
///
/// The synergy asset is now pipeline-owned and intentionally remains
/// byte-identical to `scripts/data/synergy_cluster.json`, which uses
/// top-level `synergy_clusters`. Flutter normalizes that shape at the
/// ReferenceDataRepository boundary so local stack/pairs-well consumers still
/// receive `clusters`.
///
/// The recall asset still intentionally diverges from pipeline shape:
///   banned_recalled_ingredients pipeline: `ingredients` -> Flutter: `recalled_ingredients`
///
/// If these tests fail, DO NOT fix them by changing the tests. The
/// asset file has been replaced with an incompatible schema. Re-run
/// the pipeline-to-Flutter remap (scripts/remap_reference_data or the
/// orchestrator-driven transform) before committing.
void main() {
  group('reference data asset contract', () {
    test(
      'synergy_cluster.json uses pipeline shape and normalizes for Flutter',
      () {
        final file = File('assets/reference_data/synergy_cluster.json');
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Bundled synergy asset missing at ${file.path}',
        );

        final raw = file.readAsStringSync();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;

        expect(
          decoded['synergy_clusters'],
          isNotNull,
          reason:
              'Flutter now bundles the pipeline-owned synergy asset. '
              'The raw asset should keep top-level "synergy_clusters".',
        );
        expect(
          decoded['synergy_clusters'],
          isA<List<dynamic>>(),
          reason: '"synergy_clusters" must be a JSON array',
        );

        final pipelineClusters = decoded['synergy_clusters'] as List<dynamic>;
        expect(
          pipelineClusters,
          isNotEmpty,
          reason:
              'Synergy clusters list is empty — every product loses '
              'synergy bonus scoring.',
        );

        expect(
          decoded.containsKey('clusters'),
          isFalse,
          reason:
              'Do not commit a second remapped top-level list into the '
              'asset. Normalize at ReferenceDataRepository instead.',
        );

        final normalized = normalizeSynergyClusterData(decoded);
        expect(
          normalized.containsKey('synergy_clusters'),
          isFalse,
          reason:
              'Repository normalization must hide the pipeline-shaped key '
              'from Flutter consumers.',
        );
        expect(
          normalized['clusters'],
          isA<List<dynamic>>(),
          reason:
              'Repository normalization must expose "clusters" to '
              'synergy_report_provider.dart and pairs_well_provider.dart.',
        );

        final clusters = normalized['clusters'] as List<dynamic>;
        expect(clusters, isNotEmpty);

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
      },
    );

    test('banned_recalled_ingredients.json exposes non-empty '
        '"recalled_ingredients" list', () {
      final file = File(
        'assets/reference_data/banned_recalled_ingredients.json',
      );
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Bundled recall asset missing at ${file.path}',
      );

      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      expect(
        decoded['recalled_ingredients'],
        isNotNull,
        reason:
            'Flutter asset MUST use top-level key "recalled_ingredients". '
            'If it has "ingredients" instead, a raw pipeline file was copied '
            'in — the stack safety provider at '
            'lib/features/stack/providers/stack_safety_providers.dart '
            'reads recallData["recalled_ingredients"] and will silently '
            'skip every banned-ingredient check.',
      );
      expect(
        decoded['recalled_ingredients'],
        isA<List<dynamic>>(),
        reason: '"recalled_ingredients" must be a JSON array',
      );

      final entries = decoded['recalled_ingredients'] as List<dynamic>;
      expect(
        entries,
        isNotEmpty,
        reason:
            'Recalled ingredients list is empty — the stack safety '
            'check cannot flag banned substances.',
      );

      // Guard against accidental direct-copy of pipeline file: the
      // pipeline's bare top-level key must NOT be present.
      expect(
        decoded.containsKey('ingredients'),
        isFalse,
        reason:
            'Pipeline-shaped key "ingredients" found alongside "recalled_ingredients". '
            'This asset was direct-copied from the pipeline — re-run the remap.',
      );

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
      expect(
        first.containsKey('warning_message'),
        isFalse,
        reason:
            'warning_message was removed in Sprint 27.6 (derived strings '
            'were medically incorrect). Re-introduction requires pipeline-side '
            'authoring with safety-team sign-off, NOT Flutter-side derivation '
            'from `reason`. See SPRINT_TRACKER.md Sprint 27.6 Path C.',
      );
    });
  });
}
