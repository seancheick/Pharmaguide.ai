import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/synergy_section.dart';

Map<String, dynamic> _cluster({
  required String name,
  required int tier,
  required int matchCount,
  bool allAdequate = true,
  String benefit = 'Why it works',
  String mechanism = '',
  bool singleIngredientMatch = false,
  List<String> pmids = const [],
}) {
  return {
    'name': name,
    'evidence_tier': tier,
    'match_count': matchCount,
    'all_adequate': allAdequate ? 1 : 0,
    'benefit_short': benefit,
    'mechanism': mechanism,
    'single_ingredient_match': singleIngredientMatch ? 1 : 0,
    'pmids': pmids,
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
          child: buildSynergySection(
            detailBlob: {
              'synergy_detail': {'clusters': clusters},
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('filterHighConfidenceSynergyClusters', () {
    test('drops tier > 2', () {
      final result = filterHighConfidenceSynergyClusters([
        _cluster(name: 'Tier1', tier: 1, matchCount: 3),
        _cluster(name: 'Tier3-Promising', tier: 3, matchCount: 3),
      ]);

      expect(result.map((c) => c['name']), ['Tier1']);
    });

    test('drops match_count < 2', () {
      final result = filterHighConfidenceSynergyClusters([
        _cluster(name: 'Solo', tier: 1, matchCount: 1),
        _cluster(name: 'Pair', tier: 1, matchCount: 2),
      ]);

      expect(result.map((c) => c['name']), ['Pair']);
    });

    test('drops all_adequate=false', () {
      final result = filterHighConfidenceSynergyClusters([
        _cluster(name: 'Adequate', tier: 1, matchCount: 3),
        _cluster(name: 'Sub', tier: 1, matchCount: 3, allAdequate: false),
      ]);

      expect(result.map((c) => c['name']), ['Adequate']);
    });

    test('sorts tier ascending, then match_count descending, capped at 3', () {
      final result = filterHighConfidenceSynergyClusters([
        _cluster(name: 'A-T2-mc2', tier: 2, matchCount: 2),
        _cluster(name: 'B-T1-mc5', tier: 1, matchCount: 5),
        _cluster(name: 'C-T1-mc3', tier: 1, matchCount: 3),
        _cluster(name: 'D-T1-mc2', tier: 1, matchCount: 2),
        _cluster(name: 'E-T2-mc4', tier: 2, matchCount: 4),
      ]);

      expect(result, hasLength(3));
      expect(result.map((c) => c['name']), [
        'B-T1-mc5',
        'C-T1-mc3',
        'D-T1-mc2',
      ]);
    });

    test('handles missing or non-numeric fields defensively', () {
      final result = filterHighConfidenceSynergyClusters([
        {'name': 'NoFields'},
        {'name': 'StringTier', 'evidence_tier': 'moderate', 'match_count': 5},
        _cluster(name: 'Valid', tier: 1, matchCount: 2),
      ]);

      expect(result.map((c) => c['name']), ['Valid']);
    });
  });

  group('Synergy section v2 render', () {
    testWidgets('0 clusters hides section', (tester) async {
      await _pump(tester, clusters: const []);

      expect(find.text('Works well with'), findsNothing);
    });

    testWidgets('0 high-confidence clusters hides section', (tester) async {
      await _pump(
        tester,
        clusters: [
          _cluster(name: 'Tier4', tier: 4, matchCount: 3),
          _cluster(name: 'Solo', tier: 1, matchCount: 1),
          _cluster(name: 'Sub', tier: 1, matchCount: 3, allAdequate: false),
        ],
      );

      expect(find.text('Works well with'), findsNothing);
    });

    testWidgets('passing clusters render as chips', (tester) async {
      await _pump(
        tester,
        clusters: [
          _cluster(name: 'Sleep Stack', tier: 1, matchCount: 3),
          _cluster(name: 'Heart Health', tier: 2, matchCount: 4),
          _cluster(name: 'Tier4-Drop', tier: 4, matchCount: 3),
        ],
      );

      expect(find.text('Works well with'), findsOneWidget);
      expect(find.text('Sleep Stack'), findsOneWidget);
      expect(find.text('Heart Health'), findsOneWidget);
      expect(find.text('Tier4-Drop'), findsNothing);
    });

    testWidgets(
      'tap chip opens bottom sheet with explanation and study count',
      (tester) async {
        await _pump(
          tester,
          clusters: [
            _cluster(
              name: 'Sleep Stack',
              tier: 1,
              matchCount: 3,
              benefit:
                  'Magnesium + ashwagandha + glycine support deep sleep '
                  'across multiple mechanisms.',
              pmids: ['1', '2', '3'],
            ),
          ],
        );

        await tester.tap(find.text('Sleep Stack'));
        await tester.pumpAndSettle();

        expect(find.text('Sleep Stack'), findsNWidgets(2));
        expect(find.textContaining('multiple mechanisms'), findsOneWidget);
        expect(find.text('3 published studies'), findsOneWidget);
      },
    );
  });

  group('Synergy single-ingredient-match caption', () {
    const dentalBenefit =
        'CoQ10 has demonstrated benefit in periodontal inflammation.';

    testWidgets('single-ingredient match renders inline caption', (
      tester,
    ) async {
      await _pump(
        tester,
        clusters: [
          _cluster(
            name: 'Dental & Oral Health',
            tier: 1,
            matchCount: 2,
            benefit: dentalBenefit,
            singleIngredientMatch: true,
          ),
        ],
      );

      expect(find.text('Dental & Oral Health'), findsOneWidget);
      expect(find.text(dentalBenefit), findsOneWidget);
    });

    testWidgets('multi-ingredient match renders no caption', (tester) async {
      await _pump(
        tester,
        clusters: [
          _cluster(
            name: 'Heart Health',
            tier: 1,
            matchCount: 3,
            benefit: dentalBenefit,
          ),
        ],
      );

      expect(find.text('Heart Health'), findsOneWidget);
      expect(find.text(dentalBenefit), findsNothing);
    });

    testWidgets('caption is prefixed with cluster name when multiple chips', (
      tester,
    ) async {
      await _pump(
        tester,
        clusters: [
          _cluster(
            name: 'Dental & Oral Health',
            tier: 1,
            matchCount: 2,
            benefit: dentalBenefit,
            singleIngredientMatch: true,
          ),
          _cluster(name: 'Heart Health', tier: 1, matchCount: 3),
        ],
      );

      expect(
        find.text('Dental & Oral Health — $dentalBenefit'),
        findsOneWidget,
      );
    });

    test('singleMatchCaption prefers benefit_short', () {
      final caption = singleMatchCaption({
        'benefit_short': dentalBenefit,
        'mechanism': 'Long mechanism text. Second sentence.',
      });
      expect(caption, dentalBenefit);
    });

    test('singleMatchCaption falls back to first sentence of mechanism', () {
      final caption = singleMatchCaption({
        'benefit_short': '',
        'mechanism':
            'CoQ10 supports gingival tissue energy metabolism. '
            'Deficiency is associated with periodontal disease.',
      });
      expect(caption, 'CoQ10 supports gingival tissue energy metabolism.');
    });

    test('singleMatchCaption truncates very long text', () {
      final caption = singleMatchCaption({'benefit_short': 'A' * 300});
      expect(caption.length, lessThanOrEqualTo(140));
      expect(caption, endsWith('…'));
    });

    test('singleMatchCaption empty when no authored text exists', () {
      expect(singleMatchCaption({'benefit_short': '', 'mechanism': ''}), '');
      expect(singleMatchCaption(const {}), '');
    });
  });
}
