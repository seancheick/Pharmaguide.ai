import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/tradeoffs_section.dart';

Map<String, dynamic> _bonus(String label, [String detail = '']) => {
  'label': label,
  'detail': detail,
};

Map<String, dynamic> _penalty(String label, [String detail = '']) => {
  'label': label,
  'detail': detail,
};

Map<String, dynamic> _ing(String severity) => {
  'name': 'Ing',
  'harmful_severity': severity,
};

Future<void> _pump(
  WidgetTester tester, {
  List<Map<String, dynamic>> bonuses = const [],
  List<Map<String, dynamic>> penalties = const [],
  List<Map<String, dynamic>> inactives = const [],
  Map<String, dynamic>? rdaUlData,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: buildTradeoffsSection(
            detailBlob: {
              'score_bonuses': bonuses,
              'score_penalties': penalties,
              'inactive_ingredients': inactives,
              if (rdaUlData != null) 'rda_ul_data': rdaUlData,
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Tradeoffs section v2', () {
    testWidgets('empty input hides entirely', (tester) async {
      await _pump(tester);

      expect(find.text('WHAT\'S GOOD'), findsNothing);
      expect(find.text('WHAT TO CONSIDER'), findsNothing);
    });

    testWidgets('"Harmful additive" prefix never reaches rendered tree', (
      tester,
    ) async {
      await _pump(
        tester,
        penalties: [
          _penalty('Harmful additive Sugar syrup'),
          _penalty('Harmful additive Palm oil'),
        ],
      );

      expect(
        find.text('Additive concern: Sugar syrup, Palm oil'),
        findsOneWidget,
      );
      expect(find.text('Harmful additive Sugar syrup'), findsNothing);
      expect(find.text('Harmful additive Palm oil'), findsNothing);
    });

    testWidgets('dedupes additive names case-insensitively', (tester) async {
      await _pump(
        tester,
        penalties: [
          _penalty('Harmful additive: Modified Food Starch'),
          _penalty('Harmful additive: modified food starch'),
          _penalty('Harmful additive: Silicon Dioxide'),
        ],
      );

      expect(
        find.text('Additive concern: Modified Food Starch, Silicon Dioxide'),
        findsOneWidget,
      );
    });

    testWidgets('4 concerns render fully with no toggle', (tester) async {
      await _pump(
        tester,
        penalties: [
          _penalty('Concern A'),
          _penalty('Concern B'),
          _penalty('Concern C'),
          _penalty('Concern D'),
        ],
      );

      expect(find.text('Concern A'), findsOneWidget);
      expect(find.text('Concern D'), findsOneWidget);
      expect(find.textContaining('Show'), findsNothing);
    });

    testWidgets('6 concerns collapse to 4 with expandable toggle', (
      tester,
    ) async {
      await _pump(
        tester,
        penalties: [
          _penalty('Concern A'),
          _penalty('Concern B'),
          _penalty('Concern C'),
          _penalty('Concern D'),
          _penalty('Concern E'),
          _penalty('Concern F'),
        ],
      );

      expect(find.text('Concern A'), findsOneWidget);
      expect(find.text('Concern D'), findsOneWidget);
      expect(find.text('Concern E'), findsNothing);
      expect(find.text('Show 2 more concerns'), findsOneWidget);

      await tester.tap(find.text('Show 2 more concerns'));
      await tester.pumpAndSettle();

      expect(find.text('Concern E'), findsOneWidget);
      expect(find.text('Concern F'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('bonus overflow pluralizes bonuses correctly', (tester) async {
      await _pump(
        tester,
        bonuses: [
          _bonus('A'),
          _bonus('B'),
          _bonus('C'),
          _bonus('D'),
          _bonus('E'),
          _bonus('F'),
        ],
      );

      expect(find.text('Show 2 more bonuses'), findsOneWidget);
      expect(find.text('Show 2 more bonuss'), findsNothing);
    });

    testWidgets('collapse happens before the concern cap', (tester) async {
      await _pump(
        tester,
        penalties: [
          _penalty('Harmful additive Sugar'),
          _penalty('Harmful additive Palm'),
          _penalty('Harmful additive Red 40'),
          _penalty('Harmful additive Yellow 5'),
          _penalty('Harmful additive Aspartame'),
          _penalty('Proprietary blend'),
          _penalty('Below RDA'),
          _penalty('Old reformulation'),
        ],
      );

      expect(
        find.text('Additive concern: Sugar, Palm, Red 40, Yellow 5, Aspartame'),
        findsOneWidget,
      );
      expect(find.text('Proprietary blend'), findsOneWidget);
      expect(find.text('Below RDA'), findsOneWidget);
      expect(find.text('Old reformulation'), findsOneWidget);
      expect(find.textContaining('Show'), findsNothing);
    });

    testWidgets(
      'shows verified UL exceedances even when score penalty threshold does not fire',
      (tester) async {
        await _pump(
          tester,
          rdaUlData: {
            'safety_flags': [
              {
                'nutrient': 'Niacin',
                'amount': 50.0,
                'unit': 'mg NE',
                'ul': 35,
                'pct_ul': 142.85714285714286,
                'over_amount': 15.0,
                'warning': 'Exceeds UL by 15.0 mg NE',
                'severity': 'warning',
              },
            ],
          },
        );

        expect(find.text('WHAT TO CONSIDER'), findsOneWidget);
        expect(find.text('Niacin exceeds the upper limit'), findsOneWidget);
        expect(
          find.text('50 mg NE vs 35 mg NE UL (143% of UL)'),
          findsOneWidget,
        );
      },
    );
  });

  group('Tradeoffs section safety summary', () {
    testWidgets('low or empty severity does not trigger summary', (
      tester,
    ) async {
      await _pump(
        tester,
        penalties: [_penalty('Some concern')],
        inactives: [_ing('low'), _ing(''), _ing('none')],
      );

      expect(find.textContaining('flagged for safety'), findsNothing);
    });

    testWidgets('1 high triggers summary', (tester) async {
      await _pump(
        tester,
        penalties: [_penalty('Some concern')],
        inactives: [_ing('high')],
      );

      expect(
        find.text('1 ingredients flagged for safety — review the list'),
        findsOneWidget,
      );
    });

    testWidgets('2 moderate triggers combined threshold', (tester) async {
      await _pump(
        tester,
        penalties: [_penalty('Some concern')],
        inactives: [_ing('moderate'), _ing('moderate')],
      );

      expect(
        find.text('2 ingredients flagged for safety — review the list'),
        findsOneWidget,
      );
    });

    testWidgets('summary renders even when concern list is empty', (
      tester,
    ) async {
      await _pump(tester, inactives: [_ing('high'), _ing('moderate')]);

      expect(find.textContaining('flagged for safety'), findsOneWidget);
    });
  });
}
