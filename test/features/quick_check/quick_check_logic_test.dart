// Tests for the pure helpers powering the "Safe to Take Together?" quick
// check feature. The widget itself has presentation-only concerns; all
// interesting logic lives in `quick_check_logic.dart` and is exercised here.

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/features/quick_check/quick_check_logic.dart';

void main() {
  group('extractCanonicalIds', () {
    test('null fingerprint returns empty', () {
      expect(extractCanonicalIds(null), isEmpty);
    });

    test('empty string returns empty', () {
      expect(extractCanonicalIds(''), isEmpty);
    });

    test('malformed JSON returns empty (does not throw)', () {
      expect(extractCanonicalIds('{not json'), isEmpty);
    });

    test('non-object/list JSON (string literal) returns empty', () {
      expect(extractCanonicalIds('"just a string"'), isEmpty);
    });

    test('numeric JSON returns empty', () {
      expect(extractCanonicalIds('42'), isEmpty);
    });

    test('object keyed by canonical id returns lowercase keys', () {
      final out = extractCanonicalIds(
        '{"Calcium":{"dose":500},"IRON":{"dose":18}}',
      );
      expect(out, containsAll(['calcium', 'iron']));
      expect(out.length, 2);
    });

    test('bare list of canonical ids lowercases entries', () {
      expect(
        extractCanonicalIds('["Vitamin_D","MAGNESIUM"]'),
        equals(['vitamin_d', 'magnesium']),
      );
    });

    test('list with nulls drops them', () {
      expect(
        extractCanonicalIds('["calcium",null,"iron"]'),
        equals(['calcium', 'iron']),
      );
    });
  });

  group('toneForSeverity', () {
    test('contraindicated → danger', () {
      expect(toneForSeverity(Severity.contraindicated), PGBannerTone.danger);
    });
    test('avoid → danger', () {
      expect(toneForSeverity(Severity.avoid), PGBannerTone.danger);
    });
    test('caution → caution', () {
      expect(toneForSeverity(Severity.caution), PGBannerTone.caution);
    });
    test('monitor → info', () {
      expect(toneForSeverity(Severity.monitor), PGBannerTone.info);
    });
    test('safe → info', () {
      expect(toneForSeverity(Severity.safe), PGBannerTone.info);
    });
  });

  group('runPairCheck', () {
    late InteractionDatabase db;

    setUp(() {
      db = InteractionDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'returns empty when product A has no ingredient fingerprint',
      () async {
        final a = _product('A', 'Product A', null);
        final b = _product('B', 'Product B', '{"iron":{}}');
        expect(await runPairCheck(a, b, db), isEmpty);
      },
    );

    test(
      'returns empty when product B has no ingredient fingerprint',
      () async {
        final a = _product('A', 'Product A', '{"calcium":{}}');
        final b = _product('B', 'Product B', null);
        expect(await runPairCheck(a, b, db), isEmpty);
      },
    );

    test('returns empty when DB has no matching interactions', () async {
      final a = _product('A', 'Vitamin C', '["vitamin_c"]');
      final b = _product('B', 'Vitamin E', '["vitamin_e"]');
      expect(await runPairCheck(a, b, db), isEmpty);
    });

    test(
      'finds a direction-agnostic match and applies name overrides',
      () async {
        await db.batch((batch) {
          batch.insert(
            db.interactions,
            _interactionRow(
              id: 'CA_FE_1',
              a1Canonical: 'calcium',
              a2Canonical: 'iron',
              severity: 'caution',
            ),
          );
        });

        final a = _product('A', 'Calcium Citrate', '["calcium"]');
        final b = _product('B', 'Iron Bisglycinate', '["iron"]');

        final results = await runPairCheck(a, b, db);
        expect(results, hasLength(1));
        expect(results.first.severity, Severity.caution);
        expect(results.first.agent1Name, 'Calcium Citrate');
        expect(results.first.agent2Name, 'Iron Bisglycinate');
      },
    );

    test('sorts results with highest severity first', () async {
      await db.batch((batch) {
        batch.insert(
          db.interactions,
          _interactionRow(
            id: 'LOW',
            a1Canonical: 'ingredient_a',
            a2Canonical: 'ingredient_b',
            severity: 'monitor',
          ),
        );
        batch.insert(
          db.interactions,
          _interactionRow(
            id: 'HIGH',
            a1Canonical: 'ingredient_a',
            a2Canonical: 'ingredient_c',
            severity: 'contraindicated',
          ),
        );
        batch.insert(
          db.interactions,
          _interactionRow(
            id: 'MED',
            a1Canonical: 'ingredient_a',
            a2Canonical: 'ingredient_d',
            severity: 'caution',
          ),
        );
      });

      final a = _product('A', 'Product A', '["ingredient_a"]');
      final b = _product(
        'B',
        'Product B',
        '["ingredient_b","ingredient_c","ingredient_d"]',
      );

      final results = await runPairCheck(a, b, db);
      expect(
        results.map((r) => r.severity).toList(),
        equals([Severity.contraindicated, Severity.caution, Severity.monitor]),
      );
    });

    test(
      'deduplicates same interaction id across multiple A-side lookups',
      () async {
        // This row would be returned on both sides of the lookup if we
        // didn't dedupe — A has both canonical ids, so iterating A's ids
        // would find the same row twice.
        await db.batch((batch) {
          batch.insert(
            db.interactions,
            _interactionRow(
              id: 'SELF_PAIR',
              a1Canonical: 'xx',
              a2Canonical: 'yy',
              severity: 'caution',
            ),
          );
        });

        final a = _product('A', 'Product A', '["xx","yy"]');
        final b = _product('B', 'Product B', '["xx","yy"]');

        final results = await runPairCheck(a, b, db);
        expect(results, hasLength(1));
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

ProductsCoreData _product(String id, String name, String? fingerprint) {
  return ProductsCoreData(
    dsldId: id,
    productName: name,
    productStatus: 'active',
    ingredientFingerprint: fingerprint,
    exportVersion: 'test',
    exportedAt: '2026-04-16T00:00:00Z',
  );
}

InteractionsCompanion _interactionRow({
  required String id,
  required String a1Canonical,
  required String a2Canonical,
  String severity = 'caution',
}) {
  return InteractionsCompanion.insert(
    id: id,
    agent1Type: 'supplement',
    agent1Name: a1Canonical.replaceAll('_', ' '),
    agent1Id: 'c_$a1Canonical',
    agent1CanonicalId: drift.Value(a1Canonical),
    agent2Type: 'supplement',
    agent2Name: a2Canonical.replaceAll('_', ' '),
    agent2Id: 'c_$a2Canonical',
    agent2CanonicalId: drift.Value(a2Canonical),
    severity: severity,
    mechanism: 'Test mechanism',
    management: 'Test management',
    evidenceLevel: const drift.Value('established'),
    sourceUrlsJson: '["https://example.org/test"]',
    sourcePmidsJson: '[]',
    typeAuthored: 'curated',
    source: 'curated',
    provenance: 'test',
    versionAdded: '1.0.0',
    versionLastModified: '1.0.0',
    lastUpdated: '2026-04-11T00:00:00Z',
  );
}
