// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T22.
//
// Locks the T22 "Works well with" tightening contract:
//   - Pipeline schema: evidence_tier 1-4 (1 best, 4 popular),
//     match_count, all_adequate
//   - Filter: tier ≤ 2 AND match_count ≥ 2 AND all_adequate truthy
//   - Sort: tier asc, then match_count desc
//   - Cap: top 3
//   - Hide entire section when 0 pass
//   - Tap chip → modal explainer (preserves T6 drilldown)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/pipeline_sections/synergy_detail_section.dart';

Map<String, dynamic> _cluster({
  required String name,
  required int tier,
  required int matchCount,
  bool allAdequate = true,
  String benefit = 'Why it works',
  List<String> pmids = const [],
}) {
  return {
    'name': name,
    'evidence_tier': tier,
    'match_count': matchCount,
    'all_adequate': allAdequate ? 1 : 0,
    'benefit_short': benefit,
    'pmids': pmids,
    'single_ingredient_match': matchCount == 1 ? 1 : 0,
  };
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Map<String, dynamic>> clusters,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SynergyDetailSection(
            synergyDetail: {'clusters': clusters},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('filterHighConfidence — pure helper (T22)', () {
    test('drops tier > 2', () {
      final result = SynergyDetailSection.filterHighConfidence([
        _cluster(name: 'Tier1', tier: 1, matchCount: 3),
        _cluster(name: 'Tier3-Promising', tier: 3, matchCount: 3),
        _cluster(name: 'Tier4-Popular', tier: 4, matchCount: 3),
      ]);
      expect(result.map((c) => c['name']), ['Tier1']);
    });

    test('drops match_count < 2 (single-ingredient match)', () {
      final result = SynergyDetailSection.filterHighConfidence([
        _cluster(name: 'Solo', tier: 1, matchCount: 1),
        _cluster(name: 'Pair', tier: 1, matchCount: 2),
      ]);
      expect(result.map((c) => c['name']), ['Pair']);
    });

    test('drops all_adequate=false (sub-clinical doses)', () {
      final result = SynergyDetailSection.filterHighConfidence([
        _cluster(name: 'Adequate', tier: 1, matchCount: 3, allAdequate: true),
        _cluster(name: 'Sub', tier: 1, matchCount: 3, allAdequate: false),
      ]);
      expect(result.map((c) => c['name']), ['Adequate']);
    });

    test('caps at 3 even when more pass filters', () {
      final result = SynergyDetailSection.filterHighConfidence([
        _cluster(name: 'A', tier: 1, matchCount: 5),
        _cluster(name: 'B', tier: 1, matchCount: 4),
        _cluster(name: 'C', tier: 1, matchCount: 3),
        _cluster(name: 'D', tier: 1, matchCount: 2),
        _cluster(name: 'E', tier: 2, matchCount: 5),
      ]);
      expect(result, hasLength(3));
      expect(result.map((c) => c['name']), ['A', 'B', 'C']);
    });

    test('sorts tier 1 before tier 2', () {
      final result = SynergyDetailSection.filterHighConfidence([
        _cluster(name: 'T2', tier: 2, matchCount: 5),
        _cluster(name: 'T1', tier: 1, matchCount: 2),
      ]);
      expect(result.map((c) => c['name']), ['T1', 'T2']);
    });

    test('within tier, sorts by match_count desc', () {
      final result = SynergyDetailSection.filterHighConfidence([
        _cluster(name: 'Lo', tier: 1, matchCount: 2),
        _cluster(name: 'Hi', tier: 1, matchCount: 5),
        _cluster(name: 'Mid', tier: 1, matchCount: 3),
      ]);
      expect(result.map((c) => c['name']), ['Hi', 'Mid', 'Lo']);
    });

    test('handles missing/non-numeric fields defensively', () {
      final result = SynergyDetailSection.filterHighConfidence([
        {'name': 'NoFields'},
        {'name': 'StringTier', 'evidence_tier': 'moderate', 'match_count': 5},
        _cluster(name: 'Valid', tier: 1, matchCount: 2),
      ]);
      expect(result.map((c) => c['name']), ['Valid']);
    });
  });

  group('SynergyDetailSection — render gating (T22)', () {
    testWidgets(
      '0 clusters → entire section hidden',
      (tester) async {
        await _pump(tester, clusters: const []);
        await tester.pumpAndSettle();
        expect(find.text('Works well with'), findsNothing);
      },
    );

    testWidgets(
      '0 high-confidence clusters → entire section hidden '
      '(despite raw clusters present)',
      (tester) async {
        // All clusters fail at least one filter dimension.
        await _pump(
          tester,
          clusters: [
            _cluster(name: 'Tier4', tier: 4, matchCount: 3),
            _cluster(name: 'Solo', tier: 1, matchCount: 1),
            _cluster(name: 'Sub', tier: 1, matchCount: 3, allAdequate: false),
          ],
        );
        await tester.pumpAndSettle();
        expect(find.text('Works well with'), findsNothing);
      },
    );

    testWidgets(
      '2 passing clusters → renders both as chips',
      (tester) async {
        await _pump(
          tester,
          clusters: [
            _cluster(name: 'Sleep Stack', tier: 1, matchCount: 3),
            _cluster(name: 'Heart Health', tier: 2, matchCount: 4),
            _cluster(name: 'Tier4-Drop', tier: 4, matchCount: 3),
          ],
        );
        await tester.pumpAndSettle();
        expect(find.text('Works well with'), findsOneWidget);
        expect(find.text('Sleep Stack'), findsOneWidget);
        expect(find.text('Heart Health'), findsOneWidget);
        expect(find.text('Tier4-Drop'), findsNothing);
      },
    );

    testWidgets(
      '5 passing clusters → cap at 3 (top 3 by tier+match_count)',
      (tester) async {
        await _pump(
          tester,
          clusters: [
            _cluster(name: 'A-T2-mc2', tier: 2, matchCount: 2),
            _cluster(name: 'B-T1-mc5', tier: 1, matchCount: 5),
            _cluster(name: 'C-T1-mc3', tier: 1, matchCount: 3),
            _cluster(name: 'D-T1-mc2', tier: 1, matchCount: 2),
            _cluster(name: 'E-T2-mc4', tier: 2, matchCount: 4),
          ],
        );
        await tester.pumpAndSettle();
        // Top 3: B (T1/mc5), C (T1/mc3), D (T1/mc2). E and A drop.
        expect(find.text('B-T1-mc5'), findsOneWidget);
        expect(find.text('C-T1-mc3'), findsOneWidget);
        expect(find.text('D-T1-mc2'), findsOneWidget);
        expect(find.text('E-T2-mc4'), findsNothing);
        expect(find.text('A-T2-mc2'), findsNothing);
      },
    );
  });

  group('SynergyDetailSection — chip tap → modal (preserves T6)', () {
    testWidgets(
      'tap chip opens bottom sheet with explanation + study count',
      (tester) async {
        await _pump(
          tester,
          clusters: [
            _cluster(
              name: 'Sleep Stack',
              tier: 1,
              matchCount: 3,
              benefit: 'Magnesium + ashwagandha + glycine support deep sleep '
                  'across multiple mechanisms.',
              pmids: ['1', '2', '3'],
            ),
          ],
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sleep Stack'));
        await tester.pumpAndSettle();

        // Sheet header + chip both display the name → 2 occurrences.
        expect(find.text('Sleep Stack'), findsNWidgets(2));
        // Full benefit text in sheet body.
        expect(
          find.textContaining('multiple mechanisms'),
          findsAtLeastNWidgets(1),
        );
        expect(find.text('3 published studies'), findsOneWidget);
      },
    );
  });
}
