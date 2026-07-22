import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_sheet.dart';

Future<void> _pumpAndOpenSheet(
  WidgetTester tester,
  Map<String, dynamic> ingredient,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showIngredientExplainSheet(context, ingredient: ingredient),
            child: const Text('Open ingredient'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open ingredient'));
  await tester.pumpAndSettle();
}

void main() {
  test('label presenter depends on neutral types, not the widget model', () {
    final source = File(
      'lib/features/product_detail/label_ingredient_presenter.dart',
    ).readAsStringSync();

    expect(source, contains('/label_ingredient_types.dart'));
    expect(source, isNot(contains('/widgets/ingredient_explain_model.dart')));
  });

  testWidgets('assessed form renders its quality heading and full label dose', (
    tester,
  ) async {
    await _pumpAndOpenSheet(tester, const {
      'label_display_name': 'Folate',
      'label_display_form': 'folic acid',
      'form_display_state': 'assessed',
      'exact_dose_text': '665 mcg DFE',
      'parenthetical_dose_text': '400 mcg folic acid',
      'bio_score': 14,
      'score_included': true,
    });

    expect(find.text('Excellent form'), findsOneWidget);
    expect(find.text('folic acid'), findsOneWidget);
    expect(find.text('Folic acid'), findsNothing);
    expect(find.text('665 mcg DFE (400 mcg folic acid)'), findsOneWidget);
    expect(find.text('Form unknown'), findsNothing);
  });

  testWidgets('mixed-case form renders exactly as the label reports it', (
    tester,
  ) async {
    await _pumpAndOpenSheet(tester, const {
      'label_display_name': 'EPA',
      'label_display_form': 'as Ethyl Esters',
      'form_display_state': 'assessed',
      'bio_score': 14,
      'score_included': true,
    });

    expect(find.text('as Ethyl Esters'), findsOneWidget);
    expect(find.text('As Ethyl Esters'), findsNothing);
  });

  testWidgets(
    'ordinary undisclosed form does not render a noisy status block',
    (tester) async {
      await _pumpAndOpenSheet(tester, const {
        'label_display_name': 'Fish Oil',
        'form_display_state': 'not_disclosed',
        'exact_dose_text': '2400 mg',
        'bio_score': 14,
        'score_included': true,
      });

      expect(find.text('Form not disclosed'), findsNothing);
      expect(find.text('Form assessment not applicable'), findsNothing);
      expect(find.text('Form unknown'), findsNothing);
    },
  );

  testWidgets('listed unassessed form stays visible without a quality claim', (
    tester,
  ) async {
    await _pumpAndOpenSheet(tester, const {
      'label_display_name': 'Magnesium',
      'label_display_form': 'TRAACS® Albion Chelate',
      'form_display_state': 'listed_not_assessed',
      'bio_score': 14,
    });

    expect(find.text('Form listed · not yet assessed'), findsNothing);
    expect(find.text('TRAACS® Albion Chelate'), findsOneWidget);
    expect(find.text('Form assessment not applicable'), findsNothing);
    expect(find.text('Form unknown'), findsNothing);
  });

  testWidgets('identity review keeps label dose but hides analysis claims', (
    tester,
  ) async {
    await _pumpAndOpenSheet(tester, const {
      'raw_source_text': 'Marine Lipid Concentrate',
      'label_display_name': 'EPA',
      'identity_integrity_state': 'identity_conflict',
      'form_display_state': 'needs_review',
      'label_display_form': 'Secret Triglyceride Claim',
      'exact_dose_text': '660 mg',
      'bio_score': 14,
      'score_included': true,
    });

    expect(find.text('Marine Lipid Concentrate'), findsOneWidget);
    expect(find.text('Data needs review'), findsNothing);
    expect(find.text('Form assessment not applicable'), findsNothing);
    expect(find.text('Secret Triglyceride Claim'), findsNothing);
    expect(find.text('660 mg'), findsOneWidget);
    expect(find.text('Form unknown'), findsNothing);
  });
}
