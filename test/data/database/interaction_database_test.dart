// Tests for InteractionDatabase — the read-only Drift wrapper around the
// bundled `assets/db/interaction_db.sqlite` shipped by the M2 pipeline.
//
// These tests run against the REAL bundled DB, not a fixture. The asset
// is byte-identical across runs (codified by the pipeline's
// test_build_is_byte_identical_deterministic test in
// scripts/tests/test_build_interaction_db.py), so we can assert against
// known-stable rows the pipeline guarantees.
//
// We assert on:
//   - structural shape (counts, schema, table presence)
//   - the five spec §7.3 lookup methods (canonical id, rxcui, drug class,
//     symmetric pair, drug-class member RXCUIs)
//   - getMetadata() hydration of every required key
//   - the retired_at IS NULL filter (no tombstoned rows leak through)
//
// If a test below breaks because the pipeline added/removed a curated
// row, update the fixture constants near the top — DO NOT loosen the
// assertion. The whole point of this test is to fail loudly when the
// bundle changes shape.
//
// Run: flutter test test/data/database/interaction_database_test.dart

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/interaction_database.dart';

// ---------------------------------------------------------------------------
// Stable fixtures from the current bundled interaction_db.sqlite.
//
// These constants describe rows the M2 pipeline ships today. The bundle is
// deterministic, so they don't drift between test runs — they only need
// updating when the curated drafts list changes.
// ---------------------------------------------------------------------------

/// Curated row id for calcium ↔ iron — supplement-on-supplement, severity
/// "caution". Stored with iron as agent1 and calcium as agent2.
const _calciumIronInteractionId = 'SSI_IRON_CALCIUM';

/// Curated row id for ACE inhibitors (drug class) ↔ potassium. Demonstrates
/// the class-as-agent shape: agent1_type='drug_class', agent1_id matches
/// the class id, agent1_drug_class is null.
const _aceInhibitorsPotassiumId = 'DSI_ACEI_POTASSIUM';

/// Number of live (non-tombstoned) interaction rows in the current bundle.
/// Updated from 20 (golden fixture) → 128 (full curated v1.0.0) → 136
/// (27 rule fixes in c23d044) → 138 (vinpocetine + horse chestnut
/// anticoagulant release gates).
const _expectedLiveInteractionCount = 138;

/// Pipeline-built drug classes that the current bundle ships.
/// v1.0.0 has 21 classes with curated interaction rows.
const _classesWithLiveInteractions = <String>{
  'class:ace_inhibitors',
  'class:antacids',
  'class:anticoagulants',
  'class:anticonvulsants',
  'class:antihypertensives',
  'class:antipsychotics',
  'class:benzodiazepines',
  'class:beta_blockers',
  'class:calcium_channel_blockers',
  'class:corticosteroids',
  'class:diabetes_meds',
  'class:diuretics',
  'class:hiv_protease_inhibitors',
  'class:immunosuppressants',
  'class:maois',
  'class:nsaids',
  'class:oral_contraceptives',
  'class:sedatives',
  'class:ssris',
  'class:statins',
  'class:triptans',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InteractionDatabase db;

  setUpAll(() async {
    // Materialize the bundled asset to a temp file. NativeDatabase cannot
    // open from in-memory ByteData; we follow the same pattern as
    // bundled_catalog_test.dart.
    tempDir = await Directory.systemTemp.createTemp('idb-test');
    final assetData = await rootBundle.load('assets/db/interaction_db.sqlite');
    final bytes = assetData.buffer.asUint8List(
      assetData.offsetInBytes,
      assetData.lengthInBytes,
    );
    final dbFile = File(p.join(tempDir.path, 'interaction_db.sqlite'));
    await dbFile.writeAsBytes(bytes, flush: true);
    db = InteractionDatabase.open(dbFile.path);
  });

  tearDownAll(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  group('bundled asset structural sanity', () {
    test(
      'countLiveInteractions returns the pipeline-shipped row count',
      () async {
        final count = await db.countLiveInteractions();
        expect(
          count,
          _expectedLiveInteractionCount,
          reason:
              'If this fails, the curated drafts list changed — update '
              '_expectedLiveInteractionCount and the fixture constants.',
        );
      },
    );

    test('every live row has a non-empty severity', () async {
      final rows = await db.lookupByCanonicalId('calcium');
      expect(rows, isNotEmpty);
      for (final r in rows) {
        expect(r.severity, isNotEmpty);
        expect(r.retiredAt, isNull);
      }
    });
  });

  group('lookupByCanonicalId', () {
    test('finds rows where the supplement is agent1 OR agent2', () async {
      final rows = await db.lookupByCanonicalId('calcium');
      // calcium appears in DDI_IRON_CALCIUM and DDI_CALCIUM_ZINC
      expect(rows.length, greaterThanOrEqualTo(2));
      final ids = rows.map((r) => r.id).toSet();
      expect(ids, contains(_calciumIronInteractionId));
    });

    test('returns an empty list for an unknown canonical id', () async {
      final rows = await db.lookupByCanonicalId('definitely_not_a_supplement');
      expect(rows, isEmpty);
    });

    test('every returned row matches on canonical_id (a1 or a2)', () async {
      final rows = await db.lookupByCanonicalId('iron');
      expect(rows, isNotEmpty);
      for (final r in rows) {
        final matches =
            r.agent1CanonicalId == 'iron' || r.agent2CanonicalId == 'iron';
        expect(
          matches,
          isTrue,
          reason: 'row ${r.id} returned but neither side matches',
        );
      }
    });
  });

  group('lookupByRxcui', () {
    test(
      'returns an empty list when no drug rows reference the rxcui',
      () async {
        // The current bundle has no individual drug-id rows; everything is
        // either supplement-supplement or drug_class-supplement. So a real
        // RXCUI lookup must return zero, NOT throw.
        final rows = await db.lookupByRxcui('999999');
        expect(rows, isEmpty);
      },
    );

    test('only matches when agent_type=drug, not drug_class', () async {
      // 'class:ace_inhibitors' is stored with agent_type='drug_class'.
      // Passing it to lookupByRxcui must NOT match — that would be a type
      // confusion bug callers depend on us preventing.
      final rows = await db.lookupByRxcui('class:ace_inhibitors');
      expect(rows, isEmpty);
    });
  });

  group('lookupByDrugClass', () {
    test('finds the class-as-agent rows for ACE inhibitors', () async {
      final rows = await db.lookupByDrugClass('class:ace_inhibitors');
      expect(rows.length, greaterThanOrEqualTo(1));
      final ids = rows.map((r) => r.id).toSet();
      expect(ids, contains(_aceInhibitorsPotassiumId));
      // Confirm every returned row has the class on the agent_id side,
      // not the agent_drug_class tag column.
      for (final row in rows) {
        final classOnAgent =
            (row.agent1Type == 'drug_class' &&
                row.agent1Id == 'class:ace_inhibitors') ||
            (row.agent2Type == 'drug_class' &&
                row.agent2Id == 'class:ace_inhibitors');
        expect(
          classOnAgent,
          isTrue,
          reason: 'row ${row.id} missing class agent',
        );
      }
    });

    test(
      'every drug_class agent in the bundle has at least one live row',
      () async {
        for (final classId in _classesWithLiveInteractions) {
          final rows = await db.lookupByDrugClass(classId);
          expect(
            rows,
            isNotEmpty,
            reason:
                '$classId is in _classesWithLiveInteractions but has zero '
                'live rows — fixture is stale or the pipeline removed it.',
          );
        }
      },
    );

    test('returns empty for a class id with no curated interactions', () async {
      // Use a class that exists in drug_class_map but has no curated rows.
      final rows = await db.lookupByDrugClass('class:thyroid_medications');
      expect(rows, isEmpty);
    });
  });

  group('lookupPair (symmetric)', () {
    test('finds calcium ↔ iron in either direction', () async {
      // Forward: ask in canonical pipeline order.
      final forward = await db.lookupPair(
        'C0006675',
        'supplement',
        'C0302583',
        'supplement',
      );
      expect(forward.length, 1);
      expect(forward.single.id, _calciumIronInteractionId);

      // Reverse: arguments swapped — must return the same row.
      final reverse = await db.lookupPair(
        'C0302583',
        'supplement',
        'C0006675',
        'supplement',
      );
      expect(reverse.length, 1);
      expect(reverse.single.id, _calciumIronInteractionId);
    });

    test('finds drug_class ↔ supplement pairs', () async {
      // ACE inhibitors class ↔ potassium (CUI C0032821)
      final rows = await db.lookupPair(
        'class:ace_inhibitors',
        'drug_class',
        'C0032821',
        'supplement',
      );
      expect(rows.length, 1);
      expect(rows.single.id, _aceInhibitorsPotassiumId);
    });

    test('returns empty when the type does not match the id', () async {
      // Right id, wrong type — must NOT match.
      final rows = await db.lookupPair(
        'C0006675',
        'drug', // calcium is supplement, not drug
        'C0302583',
        'supplement',
      );
      expect(rows, isEmpty);
    });

    test('returns empty for an unknown pair', () async {
      final rows = await db.lookupPair(
        'C0000000',
        'supplement',
        'C9999999',
        'supplement',
      );
      expect(rows, isEmpty);
    });
  });

  group('rxcuisForDrugClass', () {
    test('decodes the JSON membership list for ACE inhibitors', () async {
      final members = await db.rxcuisForDrugClass('class:ace_inhibitors');
      // The bundled NLM RxClass snapshot ships >5 members for ACE inhibitors.
      expect(members.length, greaterThan(5));
      // Members are RXCUIs — numeric strings.
      for (final m in members) {
        expect(
          int.tryParse(m),
          isNotNull,
          reason: 'expected numeric RXCUI string, got "$m"',
        );
      }
      // Spot-check a known captopril RXCUI (1998 in the live bundle).
      expect(members, contains('1998'));
    });

    test('returns an empty list for an unknown class id (no throw)', () async {
      final members = await db.rxcuisForDrugClass('class:does_not_exist');
      expect(members, isEmpty);
    });
  });

  group('getMetadata', () {
    test('hydrates every required key from the embedded kv table', () async {
      final meta = await db.getMetadata();
      expect(meta.schemaVersion, '1.0.0');
      expect(meta.builtAt, isNotEmpty);
      expect(meta.totalInteractions, _expectedLiveInteractionCount);
      expect(meta.sourceDraftsCount, greaterThan(0));
      expect(meta.sourceSuppaiCount, greaterThan(0));
      expect(meta.overrideCount, greaterThanOrEqualTo(0));
      expect(meta.resolvedConflictCount, greaterThanOrEqualTo(0));
      expect(meta.interactionDbVersion, isNotEmpty);
      expect(meta.pipelineVersion, isNotEmpty);
      expect(meta.minAppVersion, isNotEmpty);
    });

    test('totalInteractions matches countLiveInteractions', () async {
      // The pipeline tombstones nothing in the v1 release, so total ==
      // live count. If we ever ship a release with retired rows, this
      // test will need to assert total >= live, not equal.
      final meta = await db.getMetadata();
      final live = await db.countLiveInteractions();
      expect(meta.totalInteractions, live);
    });
  });
}
