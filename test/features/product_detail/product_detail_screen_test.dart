import 'dart:convert';
import 'package:drift/drift.dart' show MigrationStrategy, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/core/widgets/pg_score_ring.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/product_detail_screen.dart';
import 'package:pharmaguide/features/product_detail/widgets/score_line.dart';
import 'package:pharmaguide/features/product_detail/providers/fit_score_provider.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';

class _FakeCoreDatabase extends CoreDatabase {
  final ProductsCoreData product;

  _FakeCoreDatabase(this.product) : super.memory();

  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (m) => m.createAll());

  @override
  Future<ProductsCoreData?> findById(String dsldId) async {
    return dsldId == product.dsldId ? product : null;
  }

  @override
  Future<List<ProductsCoreData>> findAlternatives(
    String category,
    double minScore, {
    String? excludeDsldId,
    int limit = 5,
  }) async {
    return <ProductsCoreData>[];
  }
}

void main() {
  // T11 (2026-04-29) — `coreDb` + `userDb` setUp removed. The only
  // test that consumed them was the "score education sheet"
  // walkthrough, which was retired with the score-ring affordance.
  // Other tests in this file construct their own per-test fixtures
  // (`reviewDb`, etc.), so the file-level setUp() was dead post-T11.
  late InteractionDatabase interactionDb;

  setUp(() async {
    interactionDb = InteractionDatabase.memory();
  });

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  // T11 (2026-04-29) — `score education sheet` test removed.
  // The score-ring tap-to-explain affordance was deleted along with
  // the ring itself; `_ScoreEducationSheet` no longer exists. The
  // pillar breakdown the sheet documented now lives in the
  // `score_breakdown_card.dart` (renamed to "Product Analysis" in
  // T14). The score itself is covered by widget tests in
  // `test/features/product_detail/widgets/score_line_test.dart`.

  testWidgets(
    'T1.1 hero does NOT render the inline "Why this score" reasoning row '
    '(reasoning lives in T1.6 Tradeoffs section now)',
    (tester) async {
      // Replaces the pre-T1.1 "hero score teaser prefers penalty reason
      // for review verdicts" test. The score-led hero (T1.1) intentionally
      // strips the inline `_HeroScoreReason` widget — bonus/penalty detail
      // strings now flow to T1.6 Tradeoffs (Section 5) where they get the
      // pros/cons split they deserve, instead of competing with the
      // Quality Score altar in the hero. See INITIATIVE_PRODUCT_TRUST_
      // AND_IA.md change log entry 2026-04-29.
      final reviewDb = _FakeCoreDatabase(
        const ProductsCoreData(
          dsldId: 'TEST_DETAIL_REVIEW_001',
          productName: 'Review Blend',
          productStatus: 'active',
          scoreQuality80: 51.0,
          score100Equivalent: 64.0,
          grade: 'C',
          verdict: 'REVIEW',
          mappedCoverage: 0.92,
          primaryCategory: 'blend',
          exportVersion: 'test',
          exportedAt: '2026-04-26T00:00:00Z',
        ),
      );
      final reviewUserDb = UserDatabase.memory();

      await reviewUserDb.cacheDetail(
        'TEST_DETAIL_REVIEW_001',
        jsonEncode(<String, Object>{
          'warnings': <Object>[],
          'score_bonuses': <Object>[
            {'label': 'Third-party tested'},
          ],
          'score_penalties': <Object>[
            {'label': 'Contains proprietary blend'},
          ],
        }),
        null,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coreDatabaseProvider.overrideWithValue(reviewDb),
            userDatabaseProvider.overrideWithValue(reviewUserDb),
            interactionDatabaseProvider.overrideWithValue(interactionDb),
            fitScoreServiceProvider.overrideWith((ref) async {
              throw UnimplementedError('No FitScore in test');
            }),
          ],
          child: const MaterialApp(
            home: ProductDetailScreen(dsldId: 'TEST_DETAIL_REVIEW_001'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // T1.1 invariant: no inline "Why this score" reasoning in the
      // hero. The text might still appear elsewhere later (T14
      // Product Analysis pillar bars), so we lock the invariant
      // here only.
      expect(find.text('Why this score'), findsNothing);

      // T11 (2026-04-29) — score is now rendered as a `ScoreLine`
      // widget (text-based) instead of a `PGScoreRing` altar +
      // "PG SCORE" label. Lock the new invariant: ScoreLine is in
      // the hero, the old "PG SCORE" altar string is gone.
      expect(find.byType(ScoreLine), findsOneWidget);
      expect(find.text('PG SCORE'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  group('product-detail warning filtering', () {
    test('suppresses non-matching profile-tagged critical warnings', () {
      final out = filterProductDetailWarningsForProfile(
        detailBlob: null,
        warnings: const [
          InteractionWarning(
            severity: Severity.avoid,
            evidenceLevel: EvidenceLevel.established,
            title: 'Avoid during pregnancy',
            mechanism: 'Pregnancy-specific rule.',
            management: 'Avoid if pregnant.',
            displayModeDefault: 'critical',
            conditionIds: ['pregnancy'],
          ),
        ],
        userConditions: const {'hypertension'},
        userDrugClasses: const {},
      );

      expect(out, isEmpty);
    });

    test('keeps matching profile-tagged warnings', () {
      final out = filterProductDetailWarningsForProfile(
        detailBlob: null,
        warnings: const [
          InteractionWarning(
            severity: Severity.avoid,
            evidenceLevel: EvidenceLevel.established,
            title: 'Avoid during pregnancy',
            mechanism: 'Pregnancy-specific rule.',
            management: 'Avoid if pregnant.',
            displayModeDefault: 'suppress',
            conditionIds: ['pregnancy'],
          ),
        ],
        userConditions: const {'pregnancy'},
        userDrugClasses: const {},
      );

      expect(out.single.title, 'Avoid during pregnancy');
    });

    test('synthesizes UL exceedance warnings as global critical alerts', () {
      final out = filterProductDetailWarningsForProfile(
        detailBlob: const {
          'rda_ul_data': {
            'analyzed_ingredients': [
              {
                'standard_name': 'Vitamin B3 (Niacin)',
                'skip_ul_check': false,
                'warnings': ['Exceeds UL by 15 mg'],
              },
            ],
          },
        },
        warnings: const [],
        userConditions: const {},
        userDrugClasses: const {},
      );

      expect(out.single.title, 'Exceeds upper limit: Vitamin B3 (Niacin)');
      expect(out.single.displayModeDefault, 'critical');
    });
  });

  group('fit-score cluster extraction', () {
    test('reads current final-DB synergy_detail cluster ids', () {
      final out = extractFitProductClusters({
        'synergy_detail': {
          'clusters': [
            {'cluster_id': 'sleep_stack'},
            {'cluster_id': 'sleep_stack'},
            {'cluster_id': 'blood_sugar_support'},
            {'cluster_name': 'No ID should be ignored'},
          ],
        },
      });

      expect(out, ['sleep_stack', 'blood_sugar_support']);
    });

    test('prefers explicit product_clusters when present', () {
      final out = extractFitProductClusters({
        'product_clusters': ['explicit_cluster'],
        'synergy_detail': {
          'clusters': [
            {'cluster_id': 'sleep_stack'},
          ],
        },
      });

      expect(out, ['explicit_cluster']);
    });
  });

  // ------------------------------------------------------------------
  // BLOCKED / UNSAFE mode
  //
  // BLOCKED verdict now uses the shared product-detail shell with a
  // safety-first hero state. It must still suppress stack actions.
  // ------------------------------------------------------------------

  testWidgets(
    'BLOCKED verdict renders shared shell safety state and hides stack UI',
    (tester) async {
      final blockedDb = _FakeCoreDatabase(
        const ProductsCoreData(
          dsldId: 'TEST_BLOCKED_001',
          productName: 'Legiox Extreme',
          brandName: 'Dark Labs',
          productStatus: 'active',
          verdict: 'BLOCKED',
          blockingReason:
              'Banned Ingredient: Norethandriol (synthetic anabolic steroid)',
          mappedCoverage: 0.0,
          exportVersion: 'test',
          exportedAt: '2026-04-23T00:00:00Z',
        ),
      );
      final blockedUserDb = UserDatabase.memory();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coreDatabaseProvider.overrideWithValue(blockedDb),
            userDatabaseProvider.overrideWithValue(blockedUserDb),
            interactionDatabaseProvider.overrideWithValue(interactionDb),
            fitScoreServiceProvider.overrideWith((ref) async {
              throw UnimplementedError('No FitScore in test');
            }),
          ],
          child: const MaterialApp(
            home: ProductDetailScreen(dsldId: 'TEST_BLOCKED_001'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('BLOCKED'), findsOneWidget);
      expect(find.text('Do not use this product'), findsOneWidget);
      // Full banned-ingredient name rendered without truncation
      // (via the blockingReason fallback since no blob is cached).
      expect(find.textContaining('Norethandriol'), findsOneWidget);

      // Score / stack UI must not be mounted.
      expect(find.byType(PGScoreRing), findsNothing);
      expect(find.text('Add to my stack'), findsNothing);
      expect(find.text('In your stack'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('BLOCKED shell surfaces banned_substance_detail from the blob', (
    tester,
  ) async {
    // When the pipeline's detail blob carries banned_substance_detail,
    // the view should promote substance_name + safety_warning_one_liner
    // + safety_warning over the coarse "banned_ingredient" enum from
    // products_core.
    final blockedDb = _FakeCoreDatabase(
      const ProductsCoreData(
        dsldId: 'TEST_BSD_001',
        productName: 'Vinpocetine',
        brandName: 'Thorne Research',
        productStatus: 'active',
        verdict: 'BLOCKED',
        blockingReason: 'banned_ingredient',
        detailBlobSha256: 'fake-sha-for-test',
        mappedCoverage: 0.0,
        exportVersion: 'test',
        exportedAt: '2026-04-23T00:00:00Z',
      ),
    );
    final blockedUserDb = UserDatabase.memory();

    await blockedUserDb.cacheDetail(
      'TEST_BSD_001',
      jsonEncode(<String, Object>{
        'banned_substance_detail': {
          'substance_name': 'Vinpocetine',
          'safety_warning_one_liner':
              'Not a lawful US supplement with pregnancy risk. Stop.',
          'safety_warning':
              'An FDA statement in 2019 concluded vinpocetine is not '
              'a lawful supplement ingredient, and it is associated '
              'with miscarriage risk in pregnancy. Stop and '
              'consult a doctor.',
        },
      }),
      'fake-sha-for-test',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(blockedDb),
          userDatabaseProvider.overrideWithValue(blockedUserDb),
          interactionDatabaseProvider.overrideWithValue(interactionDb),
          fitScoreServiceProvider.overrideWith((ref) async {
            throw UnimplementedError('No FitScore in test');
          }),
        ],
        child: const MaterialApp(
          home: ProductDetailScreen(dsldId: 'TEST_BSD_001'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Substance name promoted into the body.
    expect(
      find.textContaining('Vinpocetine'),
      findsWidgets,
      reason: 'banned substance name must be visible to the user',
    );
    // Pipeline one-liner replaces the generic banner copy.
    expect(find.textContaining('Not a lawful US supplement'), findsOneWidget);
    // Full pipeline warning replaces the generic educational text.
    expect(find.textContaining('FDA statement in 2019'), findsOneWidget);
    // The coarse enum value must NOT leak through when the blob
    // provides a richer substitute.
    expect(find.text('banned_ingredient'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'UNSAFE verdict stays on the shared detail shell with no stack bar',
    (tester) async {
      final unsafeDb = _FakeCoreDatabase(
        const ProductsCoreData(
          dsldId: 'TEST_UNSAFE_001',
          productName: 'Questionable Pre-workout',
          productStatus: 'active',
          verdict: 'UNSAFE',
          blockingReason: 'Contains DMAA, a banned stimulant',
          mappedCoverage: 0.0,
          exportVersion: 'test',
          exportedAt: '2026-04-23T00:00:00Z',
        ),
      );
      final unsafeUserDb = UserDatabase.memory();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coreDatabaseProvider.overrideWithValue(unsafeDb),
            userDatabaseProvider.overrideWithValue(unsafeUserDb),
            interactionDatabaseProvider.overrideWithValue(interactionDb),
            fitScoreServiceProvider.overrideWith((ref) async {
              throw UnimplementedError('No FitScore in test');
            }),
          ],
          child: const MaterialApp(
            home: ProductDetailScreen(dsldId: 'TEST_UNSAFE_001'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('UNSAFE'), findsOneWidget);
      expect(find.text('Add to my stack'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  test(
    'isBlockedVerdict matches only BLOCKED (case-insensitive, null-safe)',
    () {
      expect(isBlockedVerdict('BLOCKED'), isTrue);
      expect(isBlockedVerdict('blocked'), isTrue);
      expect(isBlockedVerdict(' blocked '), isTrue);
      // UNSAFE is deliberately excluded from the BLOCKED override.
      expect(isBlockedVerdict('UNSAFE'), isFalse);
      expect(isBlockedVerdict('unsafe'), isFalse);
      expect(isBlockedVerdict('RECOMMENDED'), isFalse);
      expect(isBlockedVerdict('REVIEW'), isFalse);
      expect(isBlockedVerdict('NOT_SCORED'), isFalse);
      expect(isBlockedVerdict(null), isFalse);
      expect(isBlockedVerdict(''), isFalse);
    },
  );

  test('isUnsafeVerdict matches BLOCKED and UNSAFE (stack-gate predicate)', () {
    expect(isUnsafeVerdict('BLOCKED'), isTrue);
    expect(isUnsafeVerdict('UNSAFE'), isTrue);
    expect(isUnsafeVerdict('blocked'), isTrue);
    expect(isUnsafeVerdict(' unsafe '), isTrue);
    expect(isUnsafeVerdict('RECOMMENDED'), isFalse);
    expect(isUnsafeVerdict('REVIEW'), isFalse);
    expect(isUnsafeVerdict('MODERATE'), isFalse);
    expect(isUnsafeVerdict('NOT_SCORED'), isFalse);
    expect(isUnsafeVerdict(null), isFalse);
    expect(isUnsafeVerdict(''), isFalse);
  });

  group('sanitizeWhyDetail (T0.2)', () {
    test('null → empty string', () {
      expect(sanitizeWhyDetail(null), '');
    });

    test('empty / whitespace → empty string', () {
      expect(sanitizeWhyDetail(''), '');
      expect(sanitizeWhyDetail('   '), '');
    });

    test('bare integer "3" is stripped (delivery-tier noise)', () {
      expect(sanitizeWhyDetail('3'), '');
    });

    test('multi-digit integer is stripped', () {
      expect(sanitizeWhyDetail('42'), '');
    });

    test('"Tier 3" is stripped (case-insensitive)', () {
      expect(sanitizeWhyDetail('Tier 3'), '');
      expect(sanitizeWhyDetail('tier 3'), '');
      expect(sanitizeWhyDetail('TIER 3'), '');
    });

    test('prose detail passes through unchanged', () {
      expect(
        sanitizeWhyDetail('Standardized, botanical'),
        'Standardized, botanical',
      );
    });

    test(
      'prose with embedded number passes through (we only strip pure noise)',
      () {
        expect(sanitizeWhyDetail('3 study citations'), '3 study citations');
        expect(
          sanitizeWhyDetail('Backed by Tier 3 evidence'),
          'Backed by Tier 3 evidence',
        );
      },
    );

    test('leading/trailing whitespace is trimmed off prose', () {
      expect(
        sanitizeWhyDetail('  Liposomal delivery format  '),
        'Liposomal delivery format',
      );
    });
  });
}
