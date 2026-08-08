import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/formulation_section.dart';

Future<void> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? formulationDetail,
  Map<String, dynamic>? ingredientQualityData,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // Builder so the section receives a context beneath MaterialApp.
        body: Builder(
          builder: (context) => buildFormulationSection(
            context: context,
            formulationDetail: formulationDetail,
            ingredientQualityData: ingredientQualityData,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Formulation section v2', () {
    testWidgets('demoted absorption enhancers include quantity and unit', (
      tester,
    ) async {
      await _pump(
        tester,
        formulationDetail: const {
          'delivery_form': 'Capsule',
          'delivery_tier': 'standard',
        },
        ingredientQualityData: const {
          'demoted_absorption_enhancers': [
            {'name': 'BioPerine', 'quantity': 5.0, 'unit': 'mg'},
          ],
        },
      );

      expect(find.text('Formulation'), findsOneWidget);
      expect(find.text('Capsule'), findsOneWidget);
      expect(find.text('STANDARD'), findsOneWidget);
      // "Absorption support", not "Listed but not credited" (2026-08-07).
      // BioPerine at 5 mg is there to help you absorb the active, not as a
      // second active. The old wording read as an accusation — filler, or a
      // padded label — when the engine is describing a role, not a defect.
      expect(find.text('Absorption support'), findsOneWidget);
      expect(find.text('BioPerine 5.0 mg'), findsOneWidget);
      expect(
        find.text('Included to aid absorption — not scored as a primary active.'),
        findsOneWidget,
      );
      expect(find.text('Listed but not credited'), findsNothing);
    });

    testWidgets('multiple demoted aids render as separate chips', (
      tester,
    ) async {
      await _pump(
        tester,
        formulationDetail: const {'delivery_form': 'Tablet'},
        ingredientQualityData: const {
          'demoted_absorption_enhancers': [
            {'name': 'BioPerine', 'quantity': 5.0, 'unit': 'mg'},
            {'name': 'Lecithin', 'quantity': 50.0, 'unit': 'mg'},
          ],
        },
      );

      expect(find.text('BioPerine 5.0 mg'), findsOneWidget);
      expect(find.text('Lecithin 50.0 mg'), findsOneWidget);
    });

    testWidgets(
      'null ingredientQualityData does not render demoted aid section',
      (tester) async {
        await _pump(
          tester,
          formulationDetail: const {'delivery_form': 'Liquid'},
        );

        expect(find.text('Liquid'), findsOneWidget);
        expect(find.text('Listed but not credited'), findsNothing);
      },
    );
  });

  group('extractIngredientNames', () {
    test('current pipeline shape: list of maps with name field', () {
      final raw = [
        {
          'name': 'Ashwagandha (KSM-66)',
          'evidence_source': 'branded_form',
          'meets_threshold': true,
        },
        {'name': 'BioPerine', 'evidence_source': 'absorption_enhancer'},
      ];

      expect(extractIngredientNames(raw), [
        'Ashwagandha (KSM-66)',
        'BioPerine',
      ]);
    });

    test('legacy plain strings still work and are trimmed', () {
      expect(extractIngredientNames(['  Piperine  ', '\tBioPerine\n']), [
        'Piperine',
        'BioPerine',
      ]);
    });

    test('invalid shapes and empty names are dropped', () {
      expect(extractIngredientNames(null), <String>[]);
      expect(extractIngredientNames({'name': 'Nope'}), <String>[]);
      expect(
        extractIngredientNames([
          {'evidence_source': 'orphan'},
          {'name': ''},
          {'name': 'Quercetin'},
        ]),
        ['Quercetin'],
      );
    });

    test('no curly-brace JSON leak escapes the helper', () {
      final out = extractIngredientNames([
        {
          'name': 'Ashwagandha (KSM-66)',
          'evidence_source': 'branded_form',
          'meets_threshold': true,
        },
      ]);

      expect(out.single, 'Ashwagandha (KSM-66)');
      expect(out.single, isNot(contains('{')));
      expect(out.single, isNot(contains('evidence_source')));
    });
  });
}
