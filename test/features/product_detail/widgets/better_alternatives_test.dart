// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.12.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/better_alternatives_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_section.dart';

Future<void> _seedProduct(
  CoreDatabase coreDb, {
  required String dsldId,
  required String productName,
  required String? brandName,
  required double qualityScoreV4100,
  required double score100,
  required String category,
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
    overrides: [coreDatabaseProvider.overrideWithValue(coreDb)],
    child: MaterialApp.router(routerConfig: _stubRouter(child)),
  );
}

BetterAlternativesSection _section({
  String currentDsldId = 'cur',
  double? score100 = 50,
  String? category = 'multivitamin',
  bool isBlocked = false,
  bool isNotScored = false,
  ProfileRelevanceStatus? profileRelevanceStatus =
      ProfileRelevanceStatus.neutral,
  bool profileIncomplete = false,
}) {
  return BetterAlternativesSection(
    currentDsldId: currentDsldId,
    isBlocked: isBlocked,
    isNotScored: isNotScored,
    score100: score100,
    category: category,
    profileRelevanceStatus: profileRelevanceStatus,
    profileIncomplete: profileIncomplete,
  );
}

void main() {
  group('shouldShowBetterAlternatives — pure logic', () {
    test('strong match + high quality → hidden', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 85,
          profileRelevanceStatus: ProfileRelevanceStatus.strongMatch,
          profileIncomplete: false,
        ),
        isFalse,
      );
    });

    test('good match + adequate quality (60..84) → hidden', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 70,
          profileRelevanceStatus: ProfileRelevanceStatus.goodMatch,
          profileIncomplete: false,
        ),
        isFalse,
      );
    });

    test('neutral relevance → hidden when quality is adequate', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 90,
          profileRelevanceStatus: ProfileRelevanceStatus.neutral,
          profileIncomplete: false,
        ),
        isFalse,
      );
    });

    test('review relevance → visible (regardless of score)', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 90,
          profileRelevanceStatus: ProfileRelevanceStatus.review,
          profileIncomplete: false,
        ),
        isTrue,
      );
    });

    test('review relevance + incomplete profile → hidden', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 90,
          profileRelevanceStatus: ProfileRelevanceStatus.review,
          profileIncomplete: true,
        ),
        isFalse,
      );
    });

    test('not-recommended relevance → visible (regardless of score)', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 90,
          profileRelevanceStatus: ProfileRelevanceStatus.notRecommended,
          profileIncomplete: false,
        ),
        isTrue,
      );
    });

    test('not-recommended relevance + incomplete profile → hidden', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 90,
          profileRelevanceStatus: ProfileRelevanceStatus.notRecommended,
          profileIncomplete: true,
        ),
        isFalse,
      );
    });

    test('low quality (<60) → visible (regardless of fit)', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 59,
          profileRelevanceStatus: ProfileRelevanceStatus.strongMatch,
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
          profileRelevanceStatus: ProfileRelevanceStatus.strongMatch,
          profileIncomplete: false,
        ),
        isFalse,
      );
    });

    test('isBlocked → visible (always, even with fit hidden)', () {
      expect(
        shouldShowBetterAlternatives(
          isBlocked: true,
          isNotScored: false,
          score100: null,
          profileRelevanceStatus: null,
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
          profileRelevanceStatus: null,
          profileIncomplete: false,
        ),
        isFalse,
      );
    });

    test('null profileRelevanceStatus + adequate quality → hidden', () {
      // Profile relevance hasn't resolved yet. Do not surface
      // alternatives based on missing personalization alone.
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 75,
          profileRelevanceStatus: null,
          profileIncomplete: false,
        ),
        isFalse,
      );
    });

    test('incomplete profile + adequate quality → hidden', () {
      // Profile incomplete — we lack enough data to recommend alternatives.
      // Defer the alternative push until the profile fills in.
      expect(
        shouldShowBetterAlternatives(
          isBlocked: false,
          isNotScored: false,
          score100: 75,
          profileRelevanceStatus: ProfileRelevanceStatus.incomplete,
          profileIncomplete: true,
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
        await tester.pumpWidget(_wrap(coreDb, _section(category: null)));
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
      // Names + brands.
      expect(find.text('Premium Multi'), findsOneWidget);
      expect(find.text('BrandA'), findsOneWidget);
      expect(find.text('Daily Wellness'), findsOneWidget);
      expect(find.text('BrandB'), findsOneWidget);

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
  });
}
