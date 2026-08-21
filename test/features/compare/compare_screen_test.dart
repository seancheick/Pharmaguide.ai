// Compare screen widget tests.
//
// Pillar data flows through the REAL detailBlobProvider path: the test
// seeds the user DB detail cache (24h TTL, fresh) so the provider
// resolves the blob without any network — same machinery production
// uses, no provider doubles except where a fetch failure is the very
// thing under test.

import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
import 'package:pharmaguide/core/components/pg_compare_pillar_row.dart';
import 'package:pharmaguide/features/compare/compare_providers.dart';
import 'package:pharmaguide/features/compare/compare_screen.dart';

Map<String, dynamic> _pillarsBlob({
  double formulation = 18,
  double dose = 16,
  double evidence = 15,
  double transparency = 12,
  double verification = 11,
  double safetyHygiene = 9,
}) {
  return {
    'quality_pillars_v4': {
      'formulation': {'score': formulation, 'max': 20, 'reason': 'r1'},
      'dose': {'score': dose, 'max': 20, 'reason': 'r2'},
      'evidence': {'score': evidence, 'max': 20, 'reason': 'r3'},
      'transparency': {'score': transparency, 'max': 15, 'reason': 'r4'},
      'verification': {'score': verification, 'max': 15, 'reason': 'r5'},
      'safety_hygiene': {'score': safetyHygiene, 'max': 10, 'reason': 'r6'},
    },
  };
}

ProductsCoreCompanion _product({
  required String dsldId,
  required String name,
  String brand = 'Test Brand',
  double? score,
  double coverage = 0.9,
  String category = 'multivitamin',
  String? verdict,
  String? blobSha,
  String? scoreConfidence,
  String? qualityTier,
}) {
  return ProductsCoreCompanion.insert(
    dsldId: dsldId,
    productName: name,
    brandName: drift.Value(brand),
    qualityScoreV4100: drift.Value(score),
    mappedCoverage: drift.Value(coverage),
    primaryCategory: drift.Value(category),
    verdict: drift.Value(verdict),
    qualityScoreConfidence: drift.Value(scoreConfidence),
    qualityTier: drift.Value(qualityTier),
    detailBlobSha256: drift.Value(blobSha),
    exportVersion: 'test',
    exportedAt: '2026-06-01T00:00:00Z',
  );
}

class _ThrowingBlobService extends DetailBlobService {
  @override
  Future<Map<String, dynamic>?> fetchDetailBlobByHash(String sha256) async {
    throw Exception('offline');
  }
}

void main() {
  late CoreDatabase coreDb;
  late UserDatabase userDb;

  setUp(() {
    coreDb = CoreDatabase.memory();
    userDb = UserDatabase.memory();
  });

  Future<void> pumpCompare(
    WidgetTester tester, {
    String idA = 'prod-a',
    String idB = 'prod-b',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
          detailBlobServiceProvider.overrideWithValue(_ThrowingBlobService()),
        ],
        child: MaterialApp(
          home: CompareScreen(dsldIdA: idA, dsldIdB: idB),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tearDownDbs(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  }

  Future<void> seed({
    required ProductsCoreCompanion product,
    Map<String, dynamic>? blob,
  }) async {
    await coreDb.into(coreDb.productsCore).insert(product);
    if (blob != null) {
      await userDb.cacheDetail(product.dsldId.value, jsonEncode(blob), null);
    }
  }

  testWidgets('renders both products with paired pillar rows', (tester) async {
    await seed(
      product: _product(dsldId: 'prod-a', name: 'Alpha Multi', score: 92),
      blob: _pillarsBlob(formulation: 18),
    );
    await seed(
      product: _product(dsldId: 'prod-b', name: 'Beta Multi', score: 81),
      blob: _pillarsBlob(formulation: 14, dose: 12),
    );

    await pumpCompare(tester);

    expect(find.text('Alpha Multi'), findsOneWidget);
    expect(find.text('Beta Multi'), findsOneWidget);
    expect(find.text('Pillar by pillar'), findsOneWidget);
    // All six pillar labels render once each.
    for (final label in [
      'Formulation',
      'Dose',
      'Evidence',
      'Transparency',
      'Testing & Brand',
      'Formula & quality checks',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    // Paired scores from the two fake blobs.
    expect(find.text('18/20'), findsOneWidget);
    expect(find.text('14/20'), findsOneWidget);
    // No winner/better language — calm presentation only.
    expect(find.textContaining('better', findRichText: true), findsNothing);
    expect(find.textContaining('winner', findRichText: true), findsNothing);

    await tearDownDbs(tester);
  });

  testWidgets('shows only limited confidence and neutralizes that score', (
    tester,
  ) async {
    await seed(
      product: _product(
        dsldId: 'prod-a',
        name: 'Alpha',
        score: 85,
        qualityTier: 'Acceptable',
        scoreConfidence: 'moderate',
      ),
      blob: _pillarsBlob(),
    );
    await seed(
      product: _product(
        dsldId: 'prod-b',
        name: 'Beta',
        score: 85,
        scoreConfidence: 'low',
      ),
      blob: _pillarsBlob(),
    );

    await pumpCompare(tester);

    expect(find.text('Score confidence: Moderate'), findsNothing);
    expect(find.text('Score confidence: Limited'), findsOneWidget);
    expect(find.text('85/100'), findsNWidgets(2));
    // Only the moderate-confidence side retains its tier adjective.
    expect(find.text('Acceptable'), findsOneWidget);

    await tearDownDbs(tester);
  });

  testWidgets('delta callout names the largest pillar gap when hero scores '
      'differ by >= 3', (tester) async {
    await seed(
      product: _product(dsldId: 'prod-a', name: 'Alpha', score: 92),
      blob: _pillarsBlob(formulation: 18),
    );
    await seed(
      product: _product(dsldId: 'prod-b', name: 'Beta', score: 80),
      blob: _pillarsBlob(formulation: 11),
    );

    await pumpCompare(tester);

    // Assert via the Key + the load-bearing numbers, not the full
    // sentence — copy tweaks shouldn't break this test.
    final callout = find.byKey(const Key('compare-delta-callout'));
    expect(callout, findsOneWidget);
    final calloutText = (tester.widget<Text>(callout)).data!;
    expect(calloutText, contains('Formulation'));
    expect(calloutText, contains('18 vs 11'));
    // Gap (7) >= total hero delta (12) / 2 → the stronger claim is true.
    expect(calloutText, startsWith('Most of the difference is'));

    await tearDownDbs(tester);
  });

  testWidgets('delta callout downgrades to "largest pillar gap" when the '
      'top gap explains less than half the hero delta', (tester) async {
    // Hero delta 12, but the largest single pillar gap is only 4
    // (spread across pillars) → "Most of the difference" would be false.
    await seed(
      product: _product(dsldId: 'prod-a', name: 'Alpha', score: 92),
      blob: _pillarsBlob(formulation: 18, dose: 16, evidence: 15),
    );
    await seed(
      product: _product(dsldId: 'prod-b', name: 'Beta', score: 80),
      blob: _pillarsBlob(formulation: 14, dose: 12, evidence: 11),
    );

    await pumpCompare(tester);

    final callout = find.byKey(const Key('compare-delta-callout'));
    expect(callout, findsOneWidget);
    final calloutText = (tester.widget<Text>(callout)).data!;
    expect(calloutText, startsWith('The largest pillar gap is'));
    expect(calloutText, contains('Formulation'));
    expect(calloutText, contains('18 vs 14'));

    await tearDownDbs(tester);
  });

  testWidgets('delta callout hidden when hero scores are within 3', (
    tester,
  ) async {
    await seed(
      product: _product(dsldId: 'prod-a', name: 'Alpha', score: 82),
      blob: _pillarsBlob(),
    );
    await seed(
      product: _product(dsldId: 'prod-b', name: 'Beta', score: 80),
      blob: _pillarsBlob(formulation: 12),
    );

    await pumpCompare(tester);

    expect(find.byKey(const Key('compare-delta-callout')), findsNothing);

    await tearDownDbs(tester);
  });

  testWidgets('category hedge shows when primary categories differ', (
    tester,
  ) async {
    await seed(
      product: _product(
        dsldId: 'prod-a',
        name: 'Alpha',
        score: 90,
        category: 'multivitamin',
      ),
      blob: _pillarsBlob(),
    );
    await seed(
      product: _product(
        dsldId: 'prod-b',
        name: 'Beta',
        score: 88,
        category: 'omega-3',
      ),
      blob: _pillarsBlob(),
    );

    await pumpCompare(tester);

    expect(find.textContaining('different product types'), findsOneWidget);

    await tearDownDbs(tester);
  });

  testWidgets('coverage hedge shows when either product is under the 0.3 '
      'floor', (tester) async {
    await seed(
      product: _product(
        dsldId: 'prod-a',
        name: 'Alpha',
        score: 90,
        coverage: 0.2,
      ),
      blob: _pillarsBlob(),
    );
    await seed(
      product: _product(dsldId: 'prod-b', name: 'Beta', score: 88),
      blob: _pillarsBlob(),
    );

    await pumpCompare(tester);

    // The hedge sits under the pillar card — below the test viewport in
    // the lazy ListView. Scroll it into existence first.
    await tester.scrollUntilVisible(
      find.byKey(const Key('compare-coverage-hedge')),
      200,
      scrollable: find.byType(Scrollable),
    );

    expect(find.byKey(const Key('compare-coverage-hedge')), findsOneWidget);
    expect(find.textContaining('couldn\'t be fully analyzed'), findsOneWidget);

    await tearDownDbs(tester);
  });

  testWidgets('blocked product shows status instead of score and suppresses '
      'pillar rows', (tester) async {
    await seed(
      product: _product(
        dsldId: 'prod-a',
        name: 'Alpha',
        score: 40,
        verdict: 'BLOCKED',
      ),
      blob: _pillarsBlob(),
    );
    await seed(
      product: _product(dsldId: 'prod-b', name: 'Beta', score: 88),
      blob: _pillarsBlob(),
    );

    await pumpCompare(tester);

    expect(find.textContaining('Not recommended'), findsOneWidget);
    // No pillar card when one side has no comparable pillars.
    expect(find.text('Pillar by pillar'), findsNothing);
    expect(find.byKey(const Key('compare-delta-callout')), findsNothing);

    await tearDownDbs(tester);
  });

  testWidgets('blob fetch failure degrades to the calm connection line', (
    tester,
  ) async {
    // No cached blobs; both products carry a sha so the provider attempts
    // a fetch, which the throwing service fails — offline simulation.
    await seed(
      product: _product(
        dsldId: 'prod-a',
        name: 'Alpha',
        score: 90,
        blobSha: 'abc',
      ),
    );
    await seed(
      product: _product(
        dsldId: 'prod-b',
        name: 'Beta',
        score: 88,
        blobSha: 'def',
      ),
    );

    await pumpCompare(tester);

    // Hero scores still render.
    expect(find.text('90/100'), findsOneWidget);
    expect(find.text('88/100'), findsOneWidget);
    expect(find.byKey(const Key('compare-connection-hedge')), findsOneWidget);
    expect(find.textContaining('needs a connection'), findsOneWidget);
    expect(find.text('Pillar by pillar'), findsNothing);

    await tearDownDbs(tester);
  });

  testWidgets('partial pillar blob (4/6) on one side suppresses pillar rows '
      'on both', (tester) async {
    final partial = _pillarsBlob();
    final pillars = partial['quality_pillars_v4'] as Map<String, dynamic>;
    pillars.remove('verification');
    pillars.remove('safety_hygiene');

    await seed(
      product: _product(dsldId: 'prod-a', name: 'Alpha', score: 92),
      blob: _pillarsBlob(),
    );
    await seed(
      product: _product(dsldId: 'prod-b', name: 'Beta', score: 80),
      blob: partial,
    );

    await pumpCompare(tester);

    // Shared 6/6 ship rule: no pillar card on a partial parse — a 4/6
    // pairing would imply a complete comparison that isn't.
    expect(find.text('Pillar by pillar'), findsNothing);
    expect(find.byKey(const Key('compare-delta-callout')), findsNothing);
    // Hero scores still render.
    expect(find.text('92/100'), findsOneWidget);
    expect(find.text('80/100'), findsOneWidget);

    await tearDownDbs(tester);
  });

  testWidgets('provider error renders the calm load-error message, not the '
      'catalog-miss claim', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          compareEntryProvider.overrideWith(
            (ref, dsldId) async => throw StateError('boom'),
          ),
        ],
        child: const MaterialApp(
          home: CompareScreen(dsldIdA: 'prod-a', dsldIdB: 'prod-b'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('compare-load-error')), findsOneWidget);
    expect(find.textContaining('couldn\'t load right now'), findsOneWidget);
    // The catalog message would be a false claim on a load failure.
    expect(find.textContaining('verified catalog'), findsNothing);

    await tearDownDbs(tester);
  });

  group('PGComparePillarRow status parity', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('shows Strong/Mixed from the shared statusForPillar thresholds '
        '(13.9/20 is Mixed, matching the score card)', (tester) async {
      await tester.pumpWidget(
        wrap(
          const PGComparePillarRow(
            label: 'Formulation',
            maxA: 20,
            maxB: 20,
            scoreA: 17.0, // 85% → Strong
            scoreB: 13.9, // 69.5% → Mixed (same boundary as the card)
          ),
        ),
      );

      expect(find.text('Strong'), findsOneWidget);
      expect(find.text('Mixed'), findsOneWidget);
    });

    testWidgets('below 60% is Limited; a null score shows an em dash and no '
        'status label', (tester) async {
      await tester.pumpWidget(
        wrap(
          const PGComparePillarRow(
            label: 'Dose',
            maxA: 20,
            maxB: 20,
            scoreA: 11.0, // 55% → Limited
            scoreB: null, // no data
          ),
        ),
      );

      expect(find.text('Limited'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Strong'), findsNothing);
      expect(find.text('Mixed'), findsNothing);
    });
  });
}
