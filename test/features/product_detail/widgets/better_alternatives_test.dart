// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.12.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/widgets/product_image.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/better_alternatives_section.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

late UserDatabase _userDb;

Future<void> _seedProduct(
  CoreDatabase coreDb, {
  required String dsldId,
  required String productName,
  required String? brandName,
  required double qualityScoreV4100,
  required double score100,
  required String category,
  String? scoreConfidence,
}) async {
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: productName,
          exportVersion: 'test',
          exportedAt: '2026-04-29T00:00:00Z',
          brandName: Value(brandName),
          qualityScoreV4100: Value(qualityScoreV4100),
          score100Equivalent: Value(score100),
          qualityScoreStatus: const Value('scored'),
          qualityScoreConfidence: Value(scoreConfidence),
          primaryCategory: Value(category),
        ),
      );
}

/// Phase 11.7L.F — the new pipeline calls `coreDb.findById(currentDsldId)`
/// to build the candidate pool. Render tests must seed a current row
/// for the lookup to succeed; otherwise the widget early-returns to
/// SizedBox.shrink. Seeds a generic low-score "current" so the
/// section's gate condition fires.
Future<void> _seedCurrent(
  CoreDatabase coreDb, {
  String dsldId = 'cur',
  double qualityScoreV4100 = 40,
  double score100 = 50,
  String category = 'multivitamin',
}) => _seedProduct(
  coreDb,
  dsldId: dsldId,
  productName: 'Current Test Product',
  brandName: 'CurrentBrand',
  qualityScoreV4100: qualityScoreV4100,
  score100: score100,
  category: category,
);

GoRouter _stubRouter(Widget child) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: child),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (_, _) => const Scaffold(body: Text('routed')),
      ),
    ],
  );
}

Widget _wrap(CoreDatabase coreDb, Widget child) {
  return ProviderScope(
    overrides: [
      coreDatabaseProvider.overrideWithValue(coreDb),
      userDatabaseProvider.overrideWithValue(_userDb),
      profileProvider.overrideWith((ref) => ProfileNotifier()),
    ],
    child: MaterialApp.router(routerConfig: _stubRouter(child)),
  );
}

BetterAlternativesSection _section({
  String currentDsldId = 'cur',
  double? score100 = 50,
  bool isBlocked = false,
  bool isNotScored = false,
  bool profileIncomplete = false,
}) {
  return BetterAlternativesSection(
    currentDsldId: currentDsldId,
    isBlocked: isBlocked,
    isNotScored: isNotScored,
    score100: score100,
    profileIncomplete: profileIncomplete,
  );
}

void main() {
  setUp(() => _userDb = UserDatabase.memory());
  tearDown(() => _userDb.close());

  group('shouldShowBetterAlternatives — pure logic', () {
    test('Strong-or-better quality stays quiet', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 85,
          profileIncomplete: false,
        ),
        isFalse,
      );
    });

    test('Weak quality stays quiet when the profile is complete', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 65,
          profileIncomplete: false,
        ),
        isFalse,
      );
    });

    test('high score + incomplete profile → hidden (no fit claims)', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 90,
          profileIncomplete: true,
        ),
        isFalse,
      );
    });

    test('Strong tier + incomplete profile → hidden', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 80,
          qualityTier: 'Strong',
          profileIncomplete: true,
        ),
        isFalse,
      );
    });

    test('shipped Acceptable tier + incomplete profile → visible', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 80,
          qualityTier: 'Acceptable',
          profileIncomplete: true,
        ),
        isTrue,
      );
    });

    test('low quality (<60) → visible', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 59,
          profileIncomplete: true,
        ),
        isTrue,
      );
    });

    test('quality boundary — exactly 60 → hidden', () {
      // <60 strict per spec; 60 itself is not "low quality".
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 60,
          profileIncomplete: false,
        ),
        isFalse,
      );
    });

    test('isBlocked → visible even without a score', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: true,
          isNotScored: false,
          score100: null,
          profileIncomplete: true,
        ),
        isTrue,
      );
    });

    test('isNotScored + not blocked → hidden (no signal to act on)', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: true,
          score100: null,
          profileIncomplete: false,
        ),
        isFalse,
      );
    });
  });

  group('BetterAlternativesSection — render', () {
    testWidgets(
      'missing current product → renders nothing (no skeleton, no error)',
      (tester) async {
        // Category is not a gate. If `findById(currentDsldId)` returns
        // null the section settles to SizedBox.shrink with no error.
        final coreDb = CoreDatabase.memory();
        await tester.pumpWidget(_wrap(coreDb, _section()));
        await tester.pumpAndSettle();
        expect(find.text('Similar higher-quality options'), findsNothing);
        // Defensive — old title also absent.
        expect(find.text('Higher quality alternatives'), findsNothing);
        await coreDb.close();
      },
    );

    testWidgets(
      'title is "Similar higher-quality options" (Phase 11.7L.F follow-up)',
      (tester) async {
        // Sean 2026-05-16: the new ranker mixes strict-quality picks
        // with intent/family/audience matches, so the title now
        // describes what we actually return — not a category-only
        // "higher score" claim.
        final coreDb = CoreDatabase.memory();
        await _seedCurrent(coreDb);
        await _seedProduct(
          coreDb,
          dsldId: 'alt-1',
          productName: 'Premium Multi',
          brandName: 'BrandA',
          qualityScoreV4100: 70,
          score100: 87,
          category: 'multivitamin',
        );

        await tester.pumpWidget(_wrap(coreDb, _section()));
        await tester.pumpAndSettle();

        expect(find.text('Similar higher-quality options'), findsOneWidget);
        // Defensive: the previous title strings shouldn't linger.
        expect(find.text('Higher quality alternatives'), findsNothing);
        expect(find.text('Better Alternatives'), findsNothing);
        expect(
          find.text('Higher-scored products in this category'),
          findsNothing,
        );

        await coreDb.close();
      },
    );

    testWidgets('renders alternatives with score + brand name', (tester) async {
      final coreDb = CoreDatabase.memory();
      await _seedCurrent(coreDb);
      await _seedProduct(
        coreDb,
        dsldId: 'alt-1',
        productName: 'Premium Multi',
        brandName: 'BrandA',
        qualityScoreV4100: 70,
        score100: 87,
        category: 'multivitamin',
        scoreConfidence: 'moderate',
      );
      await _seedProduct(
        coreDb,
        dsldId: 'alt-2',
        productName: 'Daily Wellness',
        brandName: 'BrandB',
        qualityScoreV4100: 65,
        score100: 81,
        category: 'multivitamin',
      );

      await tester.pumpWidget(_wrap(coreDb, _section()));
      await tester.pumpAndSettle();

      // Compact v4 score lines (rounded to 0 decimals).
      expect(find.text('70/100'), findsOneWidget);
      expect(find.text('65/100'), findsOneWidget);
      expect(find.textContaining('Score confidence:'), findsNothing);
      // Names + brands.
      expect(find.text('Premium Multi'), findsOneWidget);
      expect(find.text('BrandA'), findsOneWidget);
      expect(find.text('Daily Wellness'), findsOneWidget);
      expect(find.text('BrandB'), findsOneWidget);
      expect(
        find.byType(ProductImage),
        findsNWidgets(2),
        reason:
            'alternatives must use the same catalog/OFF image resolver as '
            'Product Detail, Stack, Search, and Wishlist',
      );

      await coreDb.close();
    });

    testWidgets('caps the list at 3 alternatives', (tester) async {
      final coreDb = CoreDatabase.memory();
      // Phase 11.7L.F: current must exist for the new pipeline.
      await _seedCurrent(coreDb);
      // Seed 5 alternatives — section should only render the top 3.
      for (var i = 0; i < 5; i++) {
        await _seedProduct(
          coreDb,
          dsldId: 'alt-$i',
          productName: 'Alt $i',
          brandName: 'Brand$i',
          qualityScoreV4100: 70 - i.toDouble(),
          score100: 87 - i.toDouble(),
          category: 'multivitamin',
        );
      }

      await tester.pumpWidget(_wrap(coreDb, _section()));
      await tester.pumpAndSettle();

      // Top 3 (sorted desc by qualityScoreV4100) are alt-0, alt-1, alt-2.
      expect(find.text('Alt 0'), findsOneWidget);
      expect(find.text('Alt 1'), findsOneWidget);
      expect(find.text('Alt 2'), findsOneWidget);
      // 4th + 5th are dropped.
      expect(find.text('Alt 3'), findsNothing);
      expect(find.text('Alt 4'), findsNothing);

      await coreDb.close();
    });

    testWidgets('no per-row "+N fit" delta visible', (tester) async {
      // Defensive: the section currently shows score badge + name +
      // brand. No "+N fit" pill. If a future change adds one without
      // updating the spec, this test catches it.
      final coreDb = CoreDatabase.memory();
      await _seedCurrent(coreDb);
      await _seedProduct(
        coreDb,
        dsldId: 'alt-1',
        productName: 'Premium Multi',
        brandName: 'BrandA',
        qualityScoreV4100: 70,
        score100: 87,
        category: 'multivitamin',
      );

      await tester.pumpWidget(_wrap(coreDb, _section()));
      await tester.pumpAndSettle();

      for (final phrase in const ['+1 fit', '+5 fit', 'fit delta']) {
        expect(
          find.textContaining(phrase),
          findsNothing,
          reason: 'Rows should not show fit-delta phrase "$phrase"',
        );
      }
      // The word "fit" itself shouldn't appear in the rendered rows
      // — only the score, name, brand.
      expect(find.textContaining(' fit '), findsNothing);

      await coreDb.close();
    });

    testWidgets('no alternatives in DB → hides empty state', (tester) async {
      // Empty pool → ranker returns [] → section returns SizedBox.shrink.
      // Phase 11.7L.F follow-up: must also seed `cur` so the new
      // pipeline gets past `findById` and reaches the empty-pool
      // branch (rather than the no-current-product branch above).
      final coreDb = CoreDatabase.memory();
      await _seedCurrent(coreDb);
      await tester.pumpWidget(_wrap(coreDb, _section()));
      await tester.pumpAndSettle();

      expect(find.text('Similar higher-quality options'), findsNothing);
      // Defensive — old title also absent.
      expect(find.text('Higher quality alternatives'), findsNothing);
      await coreDb.close();
    });

    testWidgets('blocked product keeps an honest destination when none match', (
      tester,
    ) async {
      final coreDb = CoreDatabase.memory();
      await _seedCurrent(coreDb);

      await tester.pumpWidget(
        _wrap(coreDb, _section(isBlocked: true, score100: null)),
      );
      await tester.pumpAndSettle();

      expect(find.text('No comparable alternatives found'), findsOneWidget);
      expect(
        find.text(
          'We couldn\'t find a similar, higher-quality option in this catalog.',
        ),
        findsOneWidget,
      );
      await coreDb.close();
    });
  });
}
