import 'dart:convert';
import 'dart:io';

import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/services/warnings/profile_gate_evaluator.dart';
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
              'synergy_report_provider.dart.',
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
      final first = entries.first as Map<String, dynamic>;
      expect(first, containsPair('canonical_id', isA<String>()));
      expect(first, containsPair('common_names', isA<List<dynamic>>()));
      expect(first, containsPair('recall_status', isA<String>()));
      expect(first, containsPair('regulatory_basis', isA<String>()));
      expect(first, containsPair('reason', isA<String>()));
      expect(first, containsPair('effective_date', isA<String>()));
      expect(first, containsPair('severity', isA<String>()));
      expect(first, containsPair('safety_warning', isA<String>()));
      expect(first, containsPair('safety_warning_one_liner', isA<String>()));
      expect(first, containsPair('ban_context', isA<String>()));
      expect((first['safety_warning'] as String).trim(), isNotEmpty);
      expect((first['safety_warning_one_liner'] as String).trim(), isNotEmpty);
      expect(const {
        'adulterant_in_supplements',
        'contamination_recall',
        'export_restricted',
        'substance',
        'watchlist',
      }, contains(first['ban_context']));

      // Sprint 27.6: the old derived field must stay gone now that the
      // authored replacement is present.
      expect(
        first.containsKey('warning_message'),
        isFalse,
        reason:
            'warning_message was removed in Sprint 27.6 (derived strings '
            'were medically incorrect). Keep using authored safety_warning '
            '+ safety_warning_one_liner + ban_context instead.',
      );
    });

    test(
      'medication_profile_gate_rules.json exposes validated standalone rules',
      () {
        final file = File(
          'assets/reference_data/medication_profile_gate_rules.json',
        );
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'Bundled medication profile-gate asset missing at ${file.path}',
        );

        final decoded =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(decoded['schema_version'], isA<String>());
        expect(decoded['updated_at'], isA<String>());

        final rawRules = decoded['medication_profile_gate_rules'];
        expect(
          rawRules,
          isA<List<dynamic>>(),
          reason:
              'Medication profile-gate asset must expose top-level '
              '"medication_profile_gate_rules".',
        );

        final rules = rawRules! as List<dynamic>;
        expect(
          rules,
          isNotEmpty,
          reason:
              'No standalone medication profile-gate rules are bundled; '
              'pregnancy × NSAID stack checks cannot fire.',
        );

        final taxonomy =
            jsonDecode(
                  File(
                    'assets/reference_data/clinical_risk_taxonomy.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;

        final first = rules.first as Map<String, dynamic>;
        expect(first['id'], 'MCR_PREGNANCY_NSAIDS');
        expect(first['severity'], 'caution');
        expect(first['evidence_level'], isA<String>());
        expect((first['headline'] as String).trim(), isNotEmpty);
        expect((first['body'] as String).trim(), isNotEmpty);
        expect((first['management'] as String).trim(), isNotEmpty);
        expect(first['sources'], isA<List<dynamic>>());
        expect(first['sources'], isNot(isEmpty));

        final profileGate = first['profile_gate'] as Map<String, dynamic>;
        expect(
          validateProfileGate(profileGate, taxonomy: taxonomy),
          isEmpty,
          reason:
              'Standalone medication rules must use the same v6.0 '
              'profile_gate schema and controlled vocabulary as product '
              'warnings.',
        );

        final requires = profileGate['requires'] as Map<String, dynamic>;
        expect(requires['profile_flags_any'], contains('pregnant'));
        expect(requires['drug_classes_any'], contains('nsaids'));
        expect(
          requires['profile_flags_any'],
          isNot(contains('trying_to_conceive')),
          reason: 'v1 rule intentionally applies to pregnancy only.',
        );
      },
    );
  });
}
