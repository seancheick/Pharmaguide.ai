import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Drift contract test for the bundled drug_class_vocab.json asset.
///
/// Cutover safety net: keeps the vocab in lockstep with the
/// (still-shipping) `drugClassLabels` map in
/// `lib/core/constants/schema_ids.dart` until that map is migrated to
/// read from the vocab.
void main() {
  group('drug_class_vocab.json drift contract', () {
    final file = File('assets/data/drug_class_vocab.json');

    test('asset bundle present', () {
      expect(file.existsSync(), isTrue);
    });

    test('schema lock + 24 entries (15 user_selectable + 9 rule-only)', () {
      // 2026-05-13: v6.1.0 hypoglycemics 3-way split — added
      // hypoglycemics_high_risk, hypoglycemics_lower_risk,
      // hypoglycemics_unknown as user_selectable; demoted the original
      // single hypoglycemics ID to rule-only (pipeline interaction
      // rules still emit it via the compat mapping in
      // lib/features/product_detail/widgets/interaction_warnings.dart).
      // Net: +3 entries, +2 selectable, +1 rule-only.
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;

      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 24);
      expect(md['user_selectable_count'], 15);
      expect(md['rule_only_count'], 9);
      expect((md['status'] as String).contains('LOCKED'), isTrue);
    });

    test(
      'user_selectable subset (15) matches schema_ids.dart `drugClasses`',
      () {
        final raw = file.readAsStringSync();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final entries = (decoded['drug_classes'] as List)
            .cast<Map<String, dynamic>>();
        final selectableIds = entries
            .where((e) => e['user_selectable'] == true)
            .map((e) => e['id'] as String)
            .toSet();

        expect(
          selectableIds,
          equals({
            'anticoagulants',
            'antiplatelets',
            'nsaids',
            'antihypertensives',
            // v6.1.0 hypoglycemics 3-way split (2026-05-13)
            'hypoglycemics_high_risk',
            'hypoglycemics_lower_risk',
            'hypoglycemics_unknown',
            'thyroid_medications',
            'sedatives',
            'immunosuppressants',
            'statins',
            'antidepressants_ssri_snri',
            'maois',
            'cardiac_glycosides',
            'anticholinergics',
          }),
        );
      },
    );

    test('rule-only `hypoglycemics` entry preserved for pipeline compat', () {
      // The v6.1.0 split SPLIT the user-facing drug class but the
      // pipeline interaction rules
      // (scripts/data/ingredient_interaction_rules.json) still emit
      // 'hypoglycemics' as drug_class_rules[].drug_class_id. The
      // Flutter compat mapping in interaction_warnings.dart line ~371
      // maps user-profile splits back to the old ID for rule lookup.
      // The vocab entry stays in the asset (with user_selectable=false)
      // so the interaction-warning display can resolve label/notes.
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['drug_classes'] as List)
          .cast<Map<String, dynamic>>();
      final hypo = entries.firstWhere(
        (e) => e['id'] == 'hypoglycemics',
        orElse: () => <String, dynamic>{},
      );
      expect(
        hypo,
        isNotEmpty,
        reason:
            'rule-only hypoglycemics entry deleted — pipeline '
            'interaction rules will break their lookup',
      );
      expect(hypo['user_selectable'], false);
    });

    test(
      'vocab `name` matches schema_ids.dart `drugClassLabels` for selectable subset',
      () {
        // Locked from lib/core/constants/schema_ids.dart drugClassLabels map.
        const expected = {
          'anticoagulants': 'Blood thinners',
          'antiplatelets': 'Antiplatelet medication',
          'nsaids': 'NSAIDs (Ibuprofen, Aspirin regularly)',
          'antihypertensives': 'Blood pressure medication',
          // v6.1.0 split (2026-05-13)
          'hypoglycemics_high_risk':
              'Higher low-blood-sugar risk diabetes meds',
          'hypoglycemics_lower_risk':
              'Lower low-blood-sugar risk diabetes meds',
          'hypoglycemics_unknown': 'Not sure / other diabetes medication',
          'thyroid_medications': 'Thyroid medication',
          'sedatives': 'Sedatives / Sleep medication',
          'immunosuppressants': 'Immunosuppressants',
          'statins': 'Statins / Cholesterol medication',
          'antidepressants_ssri_snri': 'Antidepressants (SSRIs/SNRIs)',
          'maois': 'MAOIs',
          'cardiac_glycosides': 'Digoxin / Heart rhythm medication',
          'anticholinergics': 'Anticholinergic medication',
        };

        final raw = file.readAsStringSync();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final entries = (decoded['drug_classes'] as List)
            .cast<Map<String, dynamic>>();
        final byId = {for (final e in entries) e['id'] as String: e};

        for (final entry in expected.entries) {
          final d = byId[entry.key];
          expect(d, isNotNull, reason: 'drug_class ${entry.key} missing');
          expect(
            d!['name'],
            entry.value,
            reason:
                '${entry.key} drift: vocab=${d['name']} dart=${entry.value}',
          );
        }
      },
    );

    test('every entry has required fields populated', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['drug_classes'] as List)
          .cast<Map<String, dynamic>>();

      for (final d in entries) {
        for (final f in {'id', 'name', 'notes', 'rx_status'}) {
          expect(d[f], isA<String>(), reason: '${d['id']}: $f not string');
          expect(
            (d[f] as String).trim().isNotEmpty,
            isTrue,
            reason: '${d['id']}: $f empty',
          );
        }
        expect(
          d['examples'],
          isA<List<dynamic>>(),
          reason: '${d['id']}: examples not list',
        );
        expect(
          (d['examples'] as List<dynamic>).isNotEmpty,
          isTrue,
          reason: '${d['id']}: empty examples',
        );
        expect(
          d['user_selectable'],
          isA<bool>(),
          reason: '${d['id']}: user_selectable not bool',
        );
        expect(
          (d['notes'] as String).length,
          lessThanOrEqualTo(200),
          reason: '${d['id']}: notes >200 chars',
        );
      }
    });

    test('rx_status enum values valid', () {
      const allowed = {'rx_only', 'otc', 'mixed'};
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['drug_classes'] as List)
          .cast<Map<String, dynamic>>();

      for (final d in entries) {
        expect(
          allowed.contains(d['rx_status']),
          isTrue,
          reason: '${d['id']} rx_status=${d['rx_status']}',
        );
      }
    });
  });
}
