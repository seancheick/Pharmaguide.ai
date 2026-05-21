import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/schema_ids.dart';
import 'package:pharmaguide/core/data/vocab_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('taxonomy asset registry contract', () {
    test('every bundled vocab asset is declared in pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final vocabFiles =
          Directory('assets/data')
              .listSync()
              .whereType<File>()
              .map((f) => f.path)
              .where((path) => path.endsWith('_vocab.json'))
              .toList()
            ..sort();

      for (final path in vocabFiles) {
        expect(pubspec, contains(path), reason: '$path missing from pubspec');
      }
    });

    test('VocabRegistry initializes recently-added taxonomy loaders', () async {
      VocabRegistry.instance.debugReset();
      await VocabRegistry.instance.init();

      expect(
        VocabRegistry.instance.productType('omega_3')?.shortName,
        'Omega-3',
      );
      expect(
        VocabRegistry.instance.formFactor('softgel')?.shortName,
        'Softgel',
      );
      expect(
        VocabRegistry.instance
            .ingredientCategory('fatty_acid')
            ?.iqmParentCategory,
        'fatty_acids',
      );
      expect(VocabRegistry.instance.functionalRole('binder')?.name, 'Binder');
    });
  });

  group('new taxonomy vocab contracts', () {
    test('product_type_vocab.json has stable shape', () {
      final decoded = _json('assets/data/product_type_vocab.json');
      final entries = _entries(decoded, 'product_types');

      _expectMetadataTotal(decoded, entries);
      _expectUniqueSnakeIds(entries);

      for (final entry in entries) {
        for (final field in {'id', 'name', 'short_name', 'notes'}) {
          _expectNonEmptyString(entry, field);
        }
      }
    });

    test('form_factor_vocab.json has stable shape', () {
      final decoded = _json('assets/data/form_factor_vocab.json');
      final entries = _entries(decoded, 'form_factors');

      _expectMetadataTotal(decoded, entries);
      _expectUniqueSnakeIds(entries);

      for (final entry in entries) {
        for (final field in {'id', 'short_name', 'description'}) {
          _expectNonEmptyString(entry, field);
        }
        expect(entry['aliases'], isA<List<dynamic>>());
      }
    });

    test('ingredient categories stay aligned to IQM parent categories', () {
      final decoded = _json('assets/data/ingredient_category_vocab.json');
      final iqm = _json('assets/data/iqm_category_vocab.json');
      final entries = _entries(decoded, 'ingredient_categories');
      final iqmIds = _entries(
        iqm,
        'iqm_categories',
      ).map((entry) => entry['id'] as String).toSet();

      _expectMetadataTotal(decoded, entries);
      _expectUniqueSnakeIds(entries);

      for (final entry in entries) {
        for (final field in {'id', 'short_name', 'description'}) {
          _expectNonEmptyString(entry, field);
        }

        final parent = entry['iqm_parent_category'];
        if (parent != null) {
          expect(
            iqmIds,
            contains(parent),
            reason: '${entry['id']} references unknown IQM parent $parent',
          );
        }
      }
    });

    test('functional_roles_vocab.json has clinician-locked display shape', () {
      final decoded = _json('assets/data/functional_roles_vocab.json');
      final entries = _entries(decoded, 'functional_roles');
      final metadata = decoded['_metadata'] as Map<String, dynamic>;
      final notesLimit = metadata['char_limit_notes'] as int;

      _expectMetadataTotal(decoded, entries);
      _expectUniqueSnakeIds(entries);

      for (final entry in entries) {
        for (final field in {'id', 'name', 'notes'}) {
          _expectNonEmptyString(entry, field);
        }
        expect(
          (entry['notes'] as String).length,
          lessThanOrEqualTo(notesLimit),
          reason: '${entry['id']} notes exceed $notesLimit chars',
        );
        expect(entry['examples'], isA<List<dynamic>>());
        expect((entry['examples'] as List<dynamic>).isNotEmpty, isTrue);
        for (final ref in entry['regulatory_references'] as List<dynamic>) {
          final regulatoryRef = ref as Map<String, dynamic>;
          _expectNonEmptyString(regulatoryRef, 'jurisdiction');
          _expectNonEmptyString(regulatoryRef, 'code');
        }
      }
    });
  });

  group('clinical_risk_taxonomy.json cross-taxonomy contract', () {
    test('metadata total matches all taxonomy rows', () {
      final decoded = _json(
        'assets/reference_data/clinical_risk_taxonomy.json',
      );
      final metadata = decoded['_metadata'] as Map<String, dynamic>;
      final total =
          _entries(decoded, 'conditions').length +
          _entries(decoded, 'drug_classes').length +
          _entries(decoded, 'severity_levels').length +
          _entries(decoded, 'evidence_levels').length +
          _entries(decoded, 'profile_flags').length +
          _entries(decoded, 'product_forms').length +
          (decoded['sources'] as List<dynamic>).length;

      expect(metadata['total_entries'], total);
    });

    test('condition IDs match SchemaIds.conditions exactly', () {
      final decoded = _json(
        'assets/reference_data/clinical_risk_taxonomy.json',
      );
      final ids = _entries(
        decoded,
        'conditions',
      ).map((entry) => entry['id'] as String).toList(growable: false);

      expect(ids, SchemaIds.conditions);
    });

    test('drug-class IDs are known to drug_class_vocab.json', () {
      final decoded = _json(
        'assets/reference_data/clinical_risk_taxonomy.json',
      );
      final drugClassVocab = _json('assets/data/drug_class_vocab.json');
      final knownIds = _entries(
        drugClassVocab,
        'drug_classes',
      ).map((entry) => entry['id'] as String).toSet();

      for (final entry in _entries(decoded, 'drug_classes')) {
        expect(
          knownIds,
          contains(entry['id']),
          reason: 'clinical risk drug class ${entry['id']} not in vocab',
        );
      }
    });

    test('severity IDs are known to severity_vocab.json', () {
      final decoded = _json(
        'assets/reference_data/clinical_risk_taxonomy.json',
      );
      final severityVocab = _json('assets/data/severity_vocab.json');
      final knownIds = _entries(
        severityVocab,
        'severities',
      ).map((entry) => entry['id'] as String).toSet();

      for (final entry in _entries(decoded, 'severity_levels')) {
        expect(
          knownIds,
          contains(entry['id']),
          reason: 'clinical risk severity ${entry['id']} not in severity vocab',
        );
      }
    });

    test('evidence entries have stable display shape', () {
      final decoded = _json(
        'assets/reference_data/clinical_risk_taxonomy.json',
      );

      for (final entry in _entries(decoded, 'evidence_levels')) {
        _expectNonEmptyString(entry, 'id');
        _expectNonEmptyString(entry, 'description');
      }
    });

    test(
      'user-goal related drug classes are known to drug_class_vocab.json',
      () {
        final userGoals = _json('assets/data/user_goals_vocab.json');
        final drugClassVocab = _json('assets/data/drug_class_vocab.json');
        final knownDrugClasses = _entries(
          drugClassVocab,
          'drug_classes',
        ).map((entry) => entry['id'] as String).toSet();

        for (final goal in _entries(userGoals, 'user_goals')) {
          final related = (goal['related_drug_class_ids'] as List<dynamic>).map(
            (id) => id.toString(),
          );
          for (final id in related) {
            expect(
              knownDrugClasses,
              contains(id),
              reason: '${goal['id']} references unknown drug class $id',
            );
          }
        }
      },
    );
  });
}

Map<String, dynamic> _json(String path) {
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _entries(Map<String, dynamic> decoded, String key) {
  return (decoded[key] as List<dynamic>).cast<Map<String, dynamic>>();
}

void _expectMetadataTotal(
  Map<String, dynamic> decoded,
  List<Map<String, dynamic>> entries,
) {
  final metadata = decoded['_metadata'] as Map<String, dynamic>;
  expect(metadata['total_entries'], entries.length);
}

void _expectUniqueSnakeIds(List<Map<String, dynamic>> entries) {
  final seen = <String>{};
  final snakeId = RegExp(r'^[a-z][a-z0-9_]*$');
  for (final entry in entries) {
    _expectNonEmptyString(entry, 'id');
    final id = entry['id'] as String;
    expect(snakeId.hasMatch(id), isTrue, reason: '$id is not snake_case');
    expect(seen.add(id), isTrue, reason: '$id is duplicated');
  }
}

void _expectNonEmptyString(Map<String, dynamic> entry, String field) {
  expect(entry[field], isA<String>(), reason: '${entry['id']}: $field');
  expect(
    (entry[field] as String).trim().isNotEmpty,
    isTrue,
    reason: '${entry['id']}: $field is empty',
  );
}
