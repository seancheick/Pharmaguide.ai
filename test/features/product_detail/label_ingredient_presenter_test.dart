import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_ingredient_data.dart';
import 'package:pharmaguide/features/product_detail/label_ingredient_presenter.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';

void main() {
  group('presentActiveIngredient', () {
    test(
      'uses label-first identity, exact dose, hierarchy, and score context',
      () {
        final active = presentActiveIngredient(const {
          'label_display_name': 'EPA',
          'display_label': 'EPA (Ethyl Esters)',
          'standard_name': 'Eicosapentaenoic Acid',
          'label_display_form': 'as Ethyl Esters',
          'exact_dose_text': '360 mg',
          'display_dose_label': '3 softgels',
          'form_display_state': 'assessed',
          'bio_score': 14,
          'label_order': 3,
          'raw_source_path': 'ingredientRows[0].nestedRows[1]',
          'nested_depth': 1,
          'parent_label': 'Fish Oil',
          'score_included': true,
          'display_disposition': 'scored',
        });

        expect(active.name, 'EPA');
        expect(active.dose, '360 mg');
        expect(active.formLabel, 'as Ethyl Esters');
        expect(active.formDisplayState, PGIngredientFormDisplayState.assessed);
        expect(active.formStatusLabel, isNull);
        expect(active.formQuality, FormQuality.excellent);
        expect(active.labelOrder, 3);
        expect(active.rawSourcePath, 'ingredientRows[0].nestedRows[1]');
        expect(active.nestedDepth, 1);
        expect(active.parentLabel, 'Fish Oil');
        expect(active.scoreIncluded, isTrue);
        expect(active.displayDisposition, 'scored');
      },
    );

    test('reads form quality from the ledger analysis namespace', () {
      final active = presentActiveIngredient(const {
        'label_display_name': 'Magnesium',
        'label_display_form': 'Magnesium Bisglycinate',
        'form_display_state': 'assessed',
        'exact_dose_text': '200 mg',
        'score_included': true,
        'analysis': {
          'standard_name': 'Magnesium',
          'bio_score': 14,
          'quantity': 200,
          'unit': 'mg',
          'is_safety_concern': false,
        },
      });

      expect(active.name, 'Magnesium');
      expect(active.formLabel, 'Magnesium Bisglycinate');
      expect(active.formQuality, FormQuality.excellent);
      expect(active.dose, '200 mg');
    });

    test('reads a low-dose callout from the ledger analysis namespace', () {
      final active = presentActiveIngredient(const {
        'label_display_name': 'Curcumin',
        'exact_dose_text': '50 mg',
        'score_included': true,
        'analysis': {
          'standard_name': 'Curcumin',
          'quantity': 50,
          'unit': 'mg',
          'below_clinical_dose': true,
        },
      });

      expect(active.dose, '50 mg');
      expect(active.doseCallOut, DoseCallOut.low);
    });

    test(
      'does not call a disclosed ledger dose undisclosed when UL is skipped',
      () {
        final active = presentActiveIngredient(
          const {
            'label_display_name': 'Vitamin A',
            'exact_dose_text': '900 mcg RAE',
            'score_included': true,
            'analysis': {
              'standard_name': 'Vitamin A',
              'quantity': 900,
              'unit': 'mcg RAE',
            },
          },
          ulEntry: const {'standard_name': 'Vitamin A', 'skip_ul_check': true},
        );

        expect(active.doseCallOut, DoseCallOut.withinLimits);
      },
    );

    test('not_disclosed does not silently claim a good or excellent form', () {
      final active = presentActiveIngredient(const {
        'label_display_name': 'Fish Oil',
        'exact_dose_text': '2400 mg',
        'form_display_state': 'not_disclosed',
        'bio_score': 14,
        'score_included': true,
      });

      expect(
        active.formDisplayState,
        PGIngredientFormDisplayState.notDisclosed,
      );
      expect(active.formStatusLabel, 'Form not disclosed');
      expect(active.formLabel, isNull);
      expect(active.formQuality, FormQuality.unknown);
    });

    test(
      'listed_not_assessed keeps disclosed label form but suppresses quality tier',
      () {
        final active = presentActiveIngredient(const {
          'label_display_name': 'Magnesium',
          'label_display_form': 'Bisglycinate Chelate',
          'form_display_state': 'listed_not_assessed',
          'bio_score': 14,
        });

        expect(
          active.formDisplayState,
          PGIngredientFormDisplayState.listedNotAssessed,
        );
        expect(active.formStatusLabel, 'Form listed · not yet assessed');
        expect(active.formLabel, 'Bisglycinate Chelate');
        expect(active.formQuality, FormQuality.unknown);
      },
    );

    test(
      'not_applicable keeps other-ingredient context without form claims',
      () {
        final active = presentActiveIngredient(const {
          'label_display_name': 'Gelatin',
          'raw_source_text': 'Gelatin',
          'form_display_state': 'not_applicable',
          'display_disposition': 'other_ingredient',
          'score_included': false,
        });

        expect(
          active.formDisplayState,
          PGIngredientFormDisplayState.notApplicable,
        );
        expect(active.formStatusLabel, isNull);
        expect(active.formLabel, isNull);
        expect(active.formQuality, FormQuality.unknown);
        expect(active.scoreIncluded, isFalse);
        expect(active.displayDisposition, 'other_ingredient');
      },
    );

    test(
      'preserves folate parenthetical amount without creating a second row',
      () {
        final active = presentActiveIngredient(const {
          'label_display_name': 'Folate',
          'exact_dose_text': '665 mcg DFE',
          'parenthetical_dose_text': '400 mcg folic acid',
          'form_display_state': 'listed_not_assessed',
          'label_display_form': 'folic acid',
          'score_included': true,
        });

        expect(active.name, 'Folate');
        expect(active.dose, '665 mcg DFE');
        expect(active.parentheticalDoseText, '400 mcg folic acid');
      },
    );

    test('needs_review keeps label dose and suppresses analysis claims', () {
      final active = presentActiveIngredient(const {
        'label_display_name': 'Marine Lipid Concentrate',
        'raw_source_text': 'Marine Lipid Concentrate',
        'identity_integrity_state': 'identity_conflict',
        'form_display_state': 'needs_review',
        'label_display_form': 'Triglyceride',
        'exact_dose_text': '660 mg',
        'display_dose_label': '660 mg',
        'bio_score': 14,
        'is_safety_concern': true,
        'score_included': true,
      });

      expect(active.formDisplayState, PGIngredientFormDisplayState.needsReview);
      expect(active.formStatusLabel, isNull);
      expect(active.identityNeedsReview, isTrue);
      expect(active.formLabel, isNull);
      expect(active.formQuality, FormQuality.unknown);
      expect(active.dose, '660 mg');
      expect(active.doseCallOut, DoseCallOut.withinLimits);
      expect(active.isSafetyConcern, isFalse);
    });

    test(
      'identity conflict uses literal label text instead of canonical identity',
      () {
        final active = presentActiveIngredient(const {
          'label_display_name': 'Interpreted Magnesium',
          'standard_name': 'Magnesium',
          'raw_source_text': 'TRAACS® Albion mineral chelate',
          'identity_integrity_state': 'identity_conflict',
          'form_display_state': 'needs_review',
          'score_included': true,
        });

        expect(active.name, 'TRAACS® Albion mineral chelate');
        expect(active.formStatusLabel, isNull);
        expect(active.identityNeedsReview, isTrue);
      },
    );

    test('missing display identity also suppresses every analysis claim', () {
      final active = presentActiveIngredient(const {
        'standard_name': 'Canonical identity must not leak',
        'raw_source_text': 'Unreadable label line',
        'identity_integrity_state': 'missing_display_label',
        'form_display_state': 'assessed',
        'label_display_form': 'Mapped form',
        'exact_dose_text': '100 mg',
        'bio_score': 14,
        'is_safety_concern': true,
        'score_included': true,
      });

      expect(active.name, 'Unreadable label line');
      expect(active.identityNeedsReview, isTrue);
      expect(active.formDisplayState, PGIngredientFormDisplayState.needsReview);
      expect(active.formStatusLabel, isNull);
      expect(active.formQuality, FormQuality.unknown);
      expect(active.formLabel, isNull);
      expect(active.dose, '100 mg');
      expect(active.isSafetyConcern, isFalse);
    });

    test('disclosed form paired with not_disclosed fails closed as review', () {
      final active = presentActiveIngredient(const {
        'label_display_name': 'Magnesium',
        'label_display_form': 'as Magnesium Bisglycinate',
        'form_display_state': 'not_disclosed',
        'bio_score': 14,
        'exact_dose_text': '200 mg',
        'is_safety_concern': true,
        'score_included': true,
      });

      expect(active.formDisplayState, PGIngredientFormDisplayState.needsReview);
      expect(active.formStatusLabel, isNull);
      expect(active.formLabel, isNull);
      expect(active.formQuality, FormQuality.unknown);
      expect(active.dose, '200 mg');
      expect(active.isSafetyConcern, isFalse);
    });

    test('legacy known form preserves its assessed quality behavior', () {
      final active = presentActiveIngredient(const {
        'display_label': 'Vitamin A',
        'display_form_label': 'Retinyl Palmitate',
        'form_status': 'known',
        'bio_score': 10,
      });

      expect(active.formDisplayState, PGIngredientFormDisplayState.assessed);
      expect(active.formStatusLabel, isNull);
      expect(active.formLabel, 'Retinyl Palmitate');
      expect(active.formQuality, FormQuality.good);
    });

    test('missing legacy dose status never resurrects quantity and unit', () {
      final active = presentActiveIngredient(const {
        'display_label': 'Vitamin C',
        'dose_status': 'missing',
        'quantity': 100,
        'unit': 'mg',
      });

      expect(active.dose, isNull);
    });

    test('undisclosed blend dose never resurrects quantity and unit', () {
      final active = presentActiveIngredient(const {
        'display_label': 'Proprietary Blend',
        'dose_status': 'not_disclosed_blend',
        'quantity': 50,
        'unit': 'mg',
      });

      expect(active.dose, isNull);
    });

    test('exact label dose wins over a stale missing dose status', () {
      final active = presentActiveIngredient(const {
        'display_label': 'Vitamin C',
        'exact_dose_text': '150 mg',
        'dose_status': 'missing',
        'quantity': 999,
        'unit': 'mg',
      });

      expect(active.dose, '150 mg');
    });

    test('display dose wins over a stale undisclosed-blend status', () {
      final active = presentActiveIngredient(const {
        'display_label': 'Proprietary Blend',
        'display_dose_label': '500 mg',
        'dose_status': 'not_disclosed_blend',
        'quantity': 999,
        'unit': 'mg',
      });

      expect(active.dose, '500 mg');
    });

    test(
      'legacy active row without ledger fields preserves high-dose analysis',
      () {
        final active = presentActiveIngredient(
          const {
            'display_label': 'Vitamin A',
            'standard_name': 'vitamin a',
            'quantity': 25000,
            'unit': 'IU',
          },
          ulEntry: const {
            'standard_name': 'vitamin a',
            'quantity': 25000,
            'ul_for_default_profile': 10000,
          },
        );

        expect(active.scoreIncluded, isTrue);
        expect(active.doseCallOut, DoseCallOut.high);
      },
    );

    test(
      'legacy active row without ledger fields preserves skipped-dose analysis',
      () {
        final active = presentActiveIngredient(
          const {'display_label': 'Magnesium', 'standard_name': 'magnesium'},
          ulEntry: const {'standard_name': 'magnesium', 'skip_ul_check': true},
        );

        expect(active.scoreIncluded, isTrue);
        expect(active.doseCallOut, DoseCallOut.notDisclosed);
      },
    );

    test(
      'legacy active row without ledger fields preserves low-dose analysis',
      () {
        final active = presentActiveIngredient(const {
          'display_label': 'Curcumin',
          'below_clinical_dose': true,
        });

        expect(active.scoreIncluded, isTrue);
        expect(active.doseCallOut, DoseCallOut.low);
      },
    );

    test('explicit score exclusion keeps a row out of dose analysis', () {
      final active = presentActiveIngredient(const {
        'label_display_name': 'Total Omega-3 Fatty Acids',
        'score_included': false,
        'below_clinical_dose': true,
      });

      expect(active.scoreIncluded, isFalse);
      expect(active.doseCallOut, DoseCallOut.withinLimits);
    });

    test('explicit context disposition keeps a row out of dose analysis', () {
      final active = presentActiveIngredient(const {
        'label_display_name': 'Total Omega-3 Fatty Acids',
        'display_disposition': 'label_context',
        'below_clinical_dose': true,
      });

      expect(active.scoreIncluded, isFalse);
      expect(active.doseCallOut, DoseCallOut.withinLimits);
    });

    test('explicit scored disposition opts a row into dose analysis', () {
      final active = presentActiveIngredient(const {
        'label_display_name': 'EPA',
        'display_disposition': 'scored',
        'below_clinical_dose': true,
      });

      expect(active.scoreIncluded, isTrue);
      expect(active.doseCallOut, DoseCallOut.low);
    });
  });

  // These pin the presenter's own state gate. The sheet has a second,
  // independent belt (a note needs a tier heading to sit under), so a widget
  // test can pass even with this gate removed — assert it directly here.
  group('form note state gate', () {
    const note = 'A reviewed sentence. And the rest of the explanation.';
    const preview = 'A reviewed sentence.';

    Map<String, dynamic> row({
      required String formState,
      bool scoreIncluded = true,
      String? identityState,
    }) {
      return {
        'label_display_name': 'Riboflavin',
        'label_display_form': "Riboflavin 5' Phosphate",
        'form_display_state': formState,
        'score_included': scoreIncluded,
        if (identityState != null) 'identity_integrity_state': identityState,
        'analysis': {
          'bio_score': 10,
          'form_note': note,
          'form_note_preview': preview,
        },
      };
    }

    test('assessed and scored row carries the note and its preview', () {
      final active = presentActiveIngredient(row(formState: 'assessed'));

      expect(active.formNote, note);
      expect(active.formNotePreview, preview);
    });

    test('listed-not-assessed row drops the note', () {
      final active = presentActiveIngredient(
        row(formState: 'listed_not_assessed'),
      );

      expect(active.formDisplayState,
          PGIngredientFormDisplayState.listedNotAssessed);
      expect(active.formNote, isNull);
      expect(active.formNotePreview, isNull);
    });

    test('needs-review row drops the note', () {
      final active = presentActiveIngredient(
        row(formState: 'needs_review', identityState: 'identity_conflict'),
      );

      expect(active.identityNeedsReview, isTrue);
      expect(active.formNote, isNull);
    });

    test('unscored row drops the note', () {
      final active = presentActiveIngredient(
        row(formState: 'assessed', scoreIncluded: false),
      );

      expect(active.formNote, isNull);
    });

    test('reads the note from the top level as well as from analysis', () {
      final active = presentActiveIngredient(const {
        'label_display_name': 'Riboflavin',
        'label_display_form': "Riboflavin 5' Phosphate",
        'form_display_state': 'assessed',
        'score_included': true,
        'bio_score': 10,
        'form_note': note,
        'form_note_preview': preview,
      });

      expect(active.formNote, note);
      expect(active.formNotePreview, preview);
    });

    test('preview absent falls back to the full note', () {
      final active = presentActiveIngredient(const {
        'label_display_name': 'Riboflavin',
        'label_display_form': "Riboflavin 5' Phosphate",
        'form_display_state': 'assessed',
        'score_included': true,
        'analysis': {'bio_score': 10, 'form_note': note},
      });

      expect(active.formNotePreview, note);
    });

    test('blank note is treated as absent', () {
      final active = presentActiveIngredient(const {
        'label_display_name': 'Riboflavin',
        'label_display_form': "Riboflavin 5' Phosphate",
        'form_display_state': 'assessed',
        'score_included': true,
        'analysis': {'bio_score': 10, 'form_note': '   '},
      });

      expect(active.formNote, isNull);
      expect(active.formNotePreview, isNull);
    });

    test('undisclosed form drops the note even when marked assessed', () {
      // No label_display_form / display_form_label. A row claiming "assessed"
      // with no disclosed form is internally inconsistent, so the presenter
      // routes it to needsReview — and a note describing a form is meaningless
      // when no form was disclosed.
      final active = presentActiveIngredient(const {
        'label_display_name': 'Riboflavin',
        'form_display_state': 'assessed',
        'score_included': true,
        'analysis': {
          'bio_score': 10,
          'form_note': note,
          'form_note_preview': preview,
        },
      });

      expect(active.formDisplayState, PGIngredientFormDisplayState.needsReview);
      expect(active.formNote, isNull);
    });
  });
}
