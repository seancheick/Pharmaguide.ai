// Sprint: docs/sprints/product_detail_page_sprint.md — T4C.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/ingredients_helpers.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';

void main() {
  group('resolveFormQuality', () {
    test('null → unknown', () {
      expect(resolveFormQuality(null), FormQuality.unknown);
    });
    test('non-numeric → unknown', () {
      expect(resolveFormQuality('high'), FormQuality.unknown);
    });
    test('negative → unknown', () {
      expect(resolveFormQuality(-1), FormQuality.unknown);
    });
    test('0..3 → poor', () {
      expect(resolveFormQuality(0), FormQuality.poor);
      expect(resolveFormQuality(3), FormQuality.poor);
    });
    test('4..7 → fair', () {
      expect(resolveFormQuality(4), FormQuality.fair);
      expect(resolveFormQuality(7), FormQuality.fair);
    });
    test('8..11 → good', () {
      expect(resolveFormQuality(8), FormQuality.good);
      expect(resolveFormQuality(11), FormQuality.good);
    });
    test('12..15 → excellent', () {
      expect(resolveFormQuality(12), FormQuality.excellent);
      expect(resolveFormQuality(15), FormQuality.excellent);
    });
  });

  group('resolveDoseCallOut', () {
    test('exceeds UL → high', () {
      // resolveDoseSafety compares quantity > ul on the UL entry.
      final out = resolveDoseCallOut(
        ingredient: const {
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
      expect(out, DoseCallOut.high);
    });

    test('skip on missing-dose ingredient → not disclosed', () {
      final out = resolveDoseCallOut(
        ingredient: const {'standard_name': 'magnesium'},
        ulEntry: const {'standard_name': 'magnesium', 'skip_ul_check': true},
      );
      expect(out, DoseCallOut.notDisclosed);
    });

    test(
      'skip with a real dose (e.g. Vitamin A 1.05 mg) → withinLimits, no chip',
      () {
        // Sean 2026-05-05 — pipeline marks skip_ul_check=true for
        // retinyl Vitamin A "unknown_vitamin_form" even when the dose
        // is disclosed. Don't chip "Dose not disclosed" against a
        // visible dose.
        final out = resolveDoseCallOut(
          ingredient: const {
            'standard_name': 'vitamin a',
            'quantity': 1.05,
            'unit': 'mg',
          },
          ulEntry: const {'standard_name': 'vitamin a', 'skip_ul_check': true},
        );
        expect(out, DoseCallOut.withinLimits);
      },
    );

    test('within limits → withinLimits', () {
      final out = resolveDoseCallOut(
        ingredient: const {
          'standard_name': 'magnesium',
          'quantity': 200,
          'unit': 'mg',
        },
      );
      expect(out, DoseCallOut.withinLimits);
    });

    test('below_clinical_dose on ingredient → low', () {
      final out = resolveDoseCallOut(
        ingredient: const {
          'standard_name': 'curcumin',
          'below_clinical_dose': true,
        },
      );
      expect(out, DoseCallOut.low);
    });

    test('below_clinical_dose on ul entry → low', () {
      final out = resolveDoseCallOut(
        ingredient: const {'standard_name': 'curcumin'},
        ulEntry: const {
          'standard_name': 'curcumin',
          'below_clinical_dose': true,
        },
      );
      expect(out, DoseCallOut.low);
    });

    test('low takes precedence over UL skip when both signals present', () {
      // Belt-and-braces: if pipeline emits both, low-dose is the more
      // useful answer.
      final out = resolveDoseCallOut(
        ingredient: const {
          'standard_name': 'curcumin',
          'below_clinical_dose': true,
          'skip_ul_check': true,
        },
      );
      expect(out, DoseCallOut.low);
    });
  });

  group('buildIngredientExplain', () {
    test('assessed row and sheet share label-native form truth', () {
      const ingredient = <String, dynamic>{
        'label_display_name': 'EPA',
        'standard_name': 'Eicosapentaenoic Acid',
        'label_display_form': 'as Ethyl Esters',
        'form_display_state': 'assessed',
        'exact_dose_text': '360 mg',
        'parenthetical_dose_text': 'from 2,400 mg fish oil',
        'bio_score': 14,
        'score_included': true,
      };

      final row = activeFromMap(ingredient);
      final sheet = buildIngredientExplain(ingredient: ingredient);

      expect(sheet.title, row.name);
      expect(sheet.formName, row.formLabel);
      expect(sheet.formQuality, row.formQuality);
      expect(sheet.formStatusLabel, row.formStatusLabel);
      expect(sheet.doseLabel, row.dose);
      expect(sheet.parentheticalDoseText, row.parentheticalDoseText);
      expect(sheet.scoreIncluded, row.scoreIncluded);
      expect(sheet.formHeading, 'Excellent form');
    });

    test(
      'ordinary undisclosed form stays quiet and never inherits quality',
      () {
        const ingredient = <String, dynamic>{
          'label_display_name': 'Fish Oil',
          'form_display_state': 'not_disclosed',
          'exact_dose_text': '2400 mg',
          'bio_score': 14,
          'score_included': true,
        };

        final row = activeFromMap(ingredient);
        final sheet = buildIngredientExplain(ingredient: ingredient);

        expect(row.formQuality, FormQuality.unknown);
        expect(sheet.formQuality, FormQuality.unknown);
        expect(sheet.formStatusLabel, isNull);
        expect(sheet.formHeading, isNull);
        expect(sheet.formExplanation, isNull);
      },
    );

    test('pipeline-marked material form disclosure remains visible', () {
      final sheet = buildIngredientExplain(
        ingredient: const {
          'label_display_name': 'Fish Oil',
          'form_display_state': 'not_disclosed',
          'exact_dose_text': '1200 mg',
          'form_disclosure_material': true,
          'score_included': true,
        },
      );

      expect(sheet.formStatusLabel, 'Form not disclosed');
      expect(sheet.formHeading, 'Form not disclosed');
      expect(sheet.formExplanation, contains('label does not disclose'));
    });

    test('listed but unmapped form remains visible without a quality tier', () {
      const ingredient = <String, dynamic>{
        'label_display_name': 'Magnesium',
        'label_display_form': 'TRAACS® Albion Chelate',
        'form_display_state': 'listed_not_assessed',
        'bio_score': 14,
      };

      final row = activeFromMap(ingredient);
      final sheet = buildIngredientExplain(ingredient: ingredient);

      expect(sheet.formName, row.formLabel);
      expect(sheet.formName, 'TRAACS® Albion Chelate');
      expect(row.formQuality, FormQuality.unknown);
      expect(sheet.formQuality, FormQuality.unknown);
      expect(sheet.formStatusLabel, isNull);
      expect(sheet.formHeading, isNull);
    });

    test('needs_review keeps label dose but suppresses analysis claims', () {
      const ingredient = <String, dynamic>{
        'raw_source_text': 'Marine Lipid Concentrate',
        'label_display_name': 'EPA',
        'identity_integrity_state': 'identity_conflict',
        'form_display_state': 'needs_review',
        'label_display_form': 'Triglyceride',
        'exact_dose_text': '660 mg',
        'bio_score': 14,
        'is_safety_concern': true,
        'score_included': true,
      };

      final row = activeFromMap(ingredient);
      final sheet = buildIngredientExplain(ingredient: ingredient);

      expect(sheet.title, row.name);
      expect(sheet.identityNeedsReview, isTrue);
      expect(sheet.formStatusLabel, isNull);
      expect(sheet.formHeading, isNull);
      expect(sheet.formName, isNull);
      expect(sheet.formQuality, FormQuality.unknown);
      expect(sheet.doseLabel, '660 mg');
      expect(sheet.doseCallOut, DoseCallOut.withinLimits);
    });

    test('exact dose and Folate parenthetical stay on one logical row', () {
      const ingredient = <String, dynamic>{
        'label_display_name': 'Folate',
        'label_display_form': 'folic acid',
        'form_display_state': 'listed_not_assessed',
        'exact_dose_text': '665 mcg DFE',
        'parenthetical_dose_text': '400 mcg folic acid',
        'score_included': true,
      };

      final row = activeFromMap(ingredient);
      final sheet = buildIngredientExplain(ingredient: ingredient);

      expect(sheet.title, 'Folate');
      expect(sheet.doseLabel, row.dose);
      expect(sheet.doseLabel, '665 mcg DFE');
      expect(sheet.parentheticalDoseText, row.parentheticalDoseText);
      expect(sheet.parentheticalDoseText, '400 mcg folic acid');
    });

    test('uses display_label, falls back to standard_name', () {
      final a = buildIngredientExplain(
        ingredient: const {
          'display_label': 'Magnesium Bisglycinate',
          'standard_name': 'magnesium',
        },
      );
      expect(a.title, 'Magnesium Bisglycinate');

      final b = buildIngredientExplain(
        ingredient: const {'standard_name': 'magnesium'},
      );
      expect(b.title, 'magnesium');
    });

    test('null form → formName null', () {
      final out = buildIngredientExplain(
        ingredient: const {'standard_name': 'magnesium'},
      );
      expect(out.formName, isNull);
    });

    test('form="bisglycinate" + bio_score=14 → excellent + glycinate copy', () {
      final out = buildIngredientExplain(
        ingredient: const {
          'standard_name': 'magnesium',
          'display_form_label': 'bisglycinate',
          'form_status': 'known',
          'bio_score': 14,
        },
      );
      expect(out.formQuality, FormQuality.excellent);
      expect(out.formExplanation, contains('Glycinate'));
      expect(out.formExplanation, contains('chelated'));
    });

    test('form="oxide" + bio_score=2 → poor + oxide copy', () {
      final out = buildIngredientExplain(
        ingredient: const {
          'standard_name': 'magnesium',
          'display_form_label': 'oxide',
          'form_status': 'known',
          'bio_score': 2,
        },
      );
      expect(out.formQuality, FormQuality.poor);
      expect(out.formExplanation, contains('Oxide'));
    });

    test('exceeds UL → high dose explanation', () {
      final out = buildIngredientExplain(
        ingredient: const {
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
      expect(out.doseCallOut, DoseCallOut.high);
      expect(out.doseExplanation, contains('Upper Limit'));
    });

    test('skip with no dose keeps generic disclosure analysis silent', () {
      final out = buildIngredientExplain(
        ingredient: const {'standard_name': 'm'},
        ulEntry: const {'standard_name': 'm', 'skip_ul_check': true},
      );
      expect(out.doseCallOut, DoseCallOut.notDisclosed);
      expect(out.doseExplanation, isEmpty);
    });

    test('skip with disclosed dose → withinLimits (no chip)', () {
      final out = buildIngredientExplain(
        ingredient: const {
          'standard_name': 'vitamin a',
          'quantity': 1.05,
          'unit': 'mg',
        },
        ulEntry: const {'standard_name': 'vitamin a', 'skip_ul_check': true},
      );
      expect(out.doseCallOut, DoseCallOut.withinLimits);
      expect(out.doseExplanation, isEmpty);
    });

    test('within limits → empty dose explanation', () {
      final out = buildIngredientExplain(
        ingredient: const {'standard_name': 'm', 'quantity': 200, 'unit': 'mg'},
      );
      expect(out.doseCallOut, DoseCallOut.withinLimits);
      expect(out.doseExplanation, isEmpty);
    });

    test('below clinical → low dose explanation', () {
      final out = buildIngredientExplain(
        ingredient: const {
          'standard_name': 'curcumin',
          'below_clinical_dose': true,
        },
      );
      expect(out.doseCallOut, DoseCallOut.low);
      expect(out.doseExplanation, contains('below'));
    });

    test('display_dose_label preferred over quantity+unit', () {
      final out = buildIngredientExplain(
        ingredient: const {
          'standard_name': 'm',
          'display_dose_label': 'Amount not disclosed',
          'quantity': 100,
          'unit': 'mg',
        },
      );
      expect(out.doseLabel, 'Amount not disclosed');
    });

    test('evidence_level surfaced when present', () {
      final out = buildIngredientExplain(
        ingredient: const {'standard_name': 'm', 'evidence_level': 'Strong'},
      );
      expect(out.evidenceLabel, 'Strong');
    });
  });

  group('label helpers', () {
    test('formChipLabel matches vocabulary contract', () {
      expect(formChipLabel(FormQuality.excellent), 'Excellent form');
      expect(formChipLabel(FormQuality.good), 'Good form');
      expect(formChipLabel(FormQuality.fair), 'Fair form');
      expect(formChipLabel(FormQuality.poor), 'Poor form');
      expect(formChipLabel(FormQuality.unknown), '');
    });

    test('formBlockHeading appends "form"', () {
      expect(formBlockHeading(FormQuality.excellent), 'Excellent form');
      expect(formBlockHeading(FormQuality.poor), 'Poor form');
      // Unknown is intercepted upstream; the exhaustiveness fallback no longer
      // emits the confusing "Form unknown" string.
      expect(formBlockHeading(FormQuality.unknown), '');
    });

    test('doseChipLabel and doseBlockHeading match', () {
      expect(doseChipLabel(DoseCallOut.high), 'High dose');
      expect(doseChipLabel(DoseCallOut.low), 'Low dose');
      expect(doseChipLabel(DoseCallOut.notDisclosed), '');
      expect(doseChipLabel(DoseCallOut.withinLimits), '');
      expect(doseBlockHeading(DoseCallOut.high), 'High dose');
      expect(doseBlockHeading(DoseCallOut.notDisclosed), '');
    });
  });
}
