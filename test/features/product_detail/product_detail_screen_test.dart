import 'dart:convert';
import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/core/widgets/pg_score_ring.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/product_detail_screen.dart';
import 'package:pharmaguide/features/product_detail/providers/fit_score_provider.dart';

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
  late _FakeCoreDatabase coreDb;
  late UserDatabase userDb;
  late InteractionDatabase interactionDb;

  setUp(() async {
    interactionDb = InteractionDatabase.memory();
    coreDb = _FakeCoreDatabase(
      const ProductsCoreData(
        dsldId: 'TEST_DETAIL_001',
        productName: 'Guided Vitamin D',
        productStatus: 'active',
        scoreQuality80: 72.5,
        score100Equivalent: 91.0,
        grade: 'A-',
        verdict: 'RECOMMENDED',
        mappedCoverage: 0.95,
        scoreIngredientQuality: 22.0,
        scoreSafetyPurity: 27.0,
        scoreEvidenceResearch: 18.0,
        scoreBrandTrust: 5.0,
        primaryCategory: 'single_nutrient',
        exportVersion: 'test',
        exportedAt: '2026-04-09T00:00:00Z',
      ),
    );
    userDb = UserDatabase.memory();
  });

  testWidgets(
    'score education sheet describes the core product score accurately',
    (tester) async {
      await userDb.cacheDetail(
        'TEST_DETAIL_001',
        jsonEncode(<String, Object>{'warnings': <Object>[]}),
        null,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
            interactionDatabaseProvider.overrideWithValue(interactionDb),
            // FitScoreService loads Flutter assets via rootBundle which aren't
            // available in widget tests. Override to throw immediately so the
            // provider resolves to AsyncValue.error instead of hanging forever.
            fitScoreServiceProvider.overrideWith((ref) async {
              throw UnimplementedError('No FitScore in test');
            }),
          ],
          child: const MaterialApp(
            home: ProductDetailScreen(dsldId: 'TEST_DETAIL_001'),
          ),
        ),
      );

      // Allow async initState operations to complete (_loadProduct,
      // _loadDetailBlob, _loadStackEntry, _loadPersonalizedInteractions).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Guided Vitamin D'), findsWidgets);
      await tester.tap(find.byType(PGScoreRing));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('core product score'), findsOneWidget);
      // Pillar names rendered as separate Text widgets (with visual bars)
      expect(find.text('Ingredient Quality'), findsOneWidget);
      expect(find.text('Safety & Purity'), findsOneWidget);
      expect(find.text('Evidence & Research'), findsOneWidget);
      expect(find.text('Brand Trust'), findsOneWidget);
      // Point values as numeric labels
      expect(find.text('25 pts'), findsOneWidget);
      expect(find.text('30 pts'), findsOneWidget);
      expect(find.text('20 pts'), findsOneWidget);
      expect(find.text('5 pts'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

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
}
