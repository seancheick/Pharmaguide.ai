import 'dart:io';
import 'dart:ui' show SemanticsAction;

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
      'score_included': true,
      'analysis': {
        'bio_score': 14,
        'form_note': 'Folic acid is the synthetic folate compound.',
        'form_note_preview': 'Folic acid is the synthetic folate compound.',
      },
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

  // --- reviewed form notes ------------------------------------------------
  //
  // The pipeline ships `form_note` (+ `form_note_preview`, pre-split) on
  // display_ingredients[].analysis only when the scoring form carries an
  // approved consumer_note. The sheet renders that reviewed copy and never
  // substitutes a generic per-tier line beside an assessed form.

  const notePreview = 'The active coenzyme form of B2, also called FMN.';
  const noteFull =
      '$notePreview Taken by mouth it is converted back to plain riboflavin '
      'before your body absorbs it, so it is taken up about as well as '
      'standard riboflavin.';
  const genericGood = 'Reasonable absorption profile for most users.';

  Map<String, dynamic> riboflavinRow({
    String formState = 'assessed',
    bool scoreIncluded = true,
    String? identityState,
    bool withNote = true,
  }) {
    return {
      'label_display_name': 'Riboflavin',
      'label_display_form': "Riboflavin 5' Phosphate",
      'form_display_state': formState,
      'score_included': scoreIncluded,
      if (identityState != null) 'identity_integrity_state': identityState,
      // Nested exactly as the canonical ledger emits it.
      'analysis': {
        'bio_score': 10,
        if (withNote) 'form_note': noteFull,
        if (withNote) 'form_note_preview': notePreview,
      },
    };
  }

  testWidgets('reviewed note replaces the generic tier line', (tester) async {
    await _pumpAndOpenSheet(tester, riboflavinRow());

    expect(find.text('Good form'), findsOneWidget);
    expect(find.text(notePreview), findsOneWidget);
    expect(find.text(genericGood), findsNothing);
  });

  testWidgets('form-rating sources are explicit, readable, and tappable', (
    tester,
  ) async {
    final opened = <String>[];
    final ingredient = riboflavinRow();
    final analysis = Map<String, dynamic>.from(
      ingredient['analysis'] as Map<String, dynamic>,
    );
    analysis['bio_score'] = 14;
    analysis['form_evidence'] = {
      'evidence_level': 'moderate',
      'references_structured': [
        {
          'type': 'pubmed',
          'authority': 'NCBI PubMed',
          'pmid': '8604671',
          'title': 'Intestinal absorption of vitamin B2 compounds.',
          'url': 'https://pubmed.ncbi.nlm.nih.gov/8604671/',
        },
      ],
    };
    ingredient['analysis'] = analysis;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showIngredientExplainSheet(
                context,
                ingredient: ingredient,
                openEvidenceSource: (source) async => opened.add(source.url),
              ),
              child: const Text('Open ingredient'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open ingredient'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();

    expect(find.text('Sources for this form rating'), findsOneWidget);
    expect(find.text('Moderate supporting evidence'), findsOneWidget);
    expect(
      find.text('Intestinal absorption of vitamin B2 compounds.'),
      findsOneWidget,
    );
    expect(find.text('PMID 8604671'), findsOneWidget);

    final sourceTitle = find.text(
      'Intestinal absorption of vitamin B2 compounds.',
    );
    await tester.tap(sourceTitle);
    await tester.pump();

    expect(opened, ['https://pubmed.ncbi.nlm.nih.gov/8604671/']);
  });

  testWidgets('note collapses to the pipeline preview and expands on More', (
    tester,
  ) async {
    await _pumpAndOpenSheet(tester, riboflavinRow());

    expect(find.text(notePreview), findsOneWidget);
    expect(find.text(noteFull), findsNothing);
    expect(find.text('More'), findsOneWidget);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.text(noteFull), findsOneWidget);
    expect(find.text('Less'), findsOneWidget);

    await tester.tap(find.text('Less'));
    await tester.pumpAndSettle();
    expect(find.text(notePreview), findsOneWidget);
    expect(find.text(noteFull), findsNothing);
  });

  testWidgets('More control has a 44 by 44 point touch target', (tester) async {
    await _pumpAndOpenSheet(tester, riboflavinRow());

    final moreControl = find.ancestor(
      of: find.text('More'),
      matching: find.byType(InkWell),
    );
    final rect = tester.getRect(moreControl);

    expect(rect.width, greaterThanOrEqualTo(44));
    expect(rect.height, greaterThanOrEqualTo(44));
  });

  testWidgets('More control has an accessible action label', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpAndOpenSheet(tester, riboflavinRow());

    final node = tester.getSemantics(find.text('More'));
    expect(node.label, contains('Show more about Good form'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  testWidgets('no note renders no generic education block', (tester) async {
    await _pumpAndOpenSheet(tester, riboflavinRow(withNote: false));

    expect(find.text('Good form'), findsNothing);
    expect(find.text(genericGood), findsNothing);
    expect(find.text('More'), findsNothing);
  });

  // The state gate, not a null check. A stale or malformed blob can carry a
  // note on a row the pipeline no longer considers assessed; the sheet must
  // suppress it rather than explain a form it has not assessed.
  testWidgets('listed-not-assessed row suppresses a stale note', (
    tester,
  ) async {
    await _pumpAndOpenSheet(
      tester,
      riboflavinRow(formState: 'listed_not_assessed'),
    );

    expect(find.text(notePreview), findsNothing);
    expect(find.text(noteFull), findsNothing);
    expect(find.text('More'), findsNothing);
    expect(find.text('Good form'), findsNothing);
    // The label's own form text still shows — only the claim is withheld.
    expect(find.text("Riboflavin 5' Phosphate"), findsOneWidget);
  });

  testWidgets('identity-review row suppresses a stale note', (tester) async {
    await _pumpAndOpenSheet(
      tester,
      riboflavinRow(
        formState: 'needs_review',
        identityState: 'identity_conflict',
      ),
    );

    expect(find.text(notePreview), findsNothing);
    expect(find.text('More'), findsNothing);
  });

  testWidgets('unscored row suppresses a stale note', (tester) async {
    await _pumpAndOpenSheet(tester, riboflavinRow(scoreIncluded: false));

    expect(find.text(notePreview), findsNothing);
    expect(find.text('More'), findsNothing);
  });

  testWidgets('note without bio_score renders no headless explanation', (
    tester,
  ) async {
    await _pumpAndOpenSheet(tester, const {
      'label_display_name': 'Riboflavin',
      'label_display_form': "Riboflavin 5' Phosphate",
      'form_display_state': 'assessed',
      'score_included': true,
      'analysis': {'form_note': noteFull, 'form_note_preview': notePreview},
    });

    expect(find.text(notePreview), findsNothing);
    expect(find.text('More'), findsNothing);
  });

  testWidgets('missing preview falls back to the full note, still expandable', (
    tester,
  ) async {
    await _pumpAndOpenSheet(tester, const {
      'label_display_name': 'Riboflavin',
      'label_display_form': "Riboflavin 5' Phosphate",
      'form_display_state': 'assessed',
      'score_included': true,
      'analysis': {'bio_score': 10, 'form_note': noteFull},
    });

    expect(find.text(noteFull), findsOneWidget);
    // Preview == body, so there is nothing left to reveal.
    expect(find.text('More'), findsNothing);
  });
}
