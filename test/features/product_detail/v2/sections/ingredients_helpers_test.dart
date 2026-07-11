import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/ingredients_helpers.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';

void main() {
  group('formChipLabel', () {
    test('row chips use the "{tier} form" vocabulary', () {
      expect(formChipLabel(FormQuality.excellent), 'Excellent form');
      expect(formChipLabel(FormQuality.good), 'Good form');
      expect(formChipLabel(FormQuality.fair), 'Fair form');
      expect(formChipLabel(FormQuality.poor), 'Poor form');
    });
  });

  group('activeFromMap label-first identity', () {
    test('label_display_name wins over the computed display_label and the '
        'canonical standard_name', () {
      final active = activeFromMap(const {
        'label_display_name': 'EPA',
        'display_label': 'EPA (Ethyl Esters)',
        'standard_name': 'Eicosapentaenoic Acid',
        'name': 'EPA',
      });

      expect(active.name, 'EPA');
    });

    test('label_display_form wins for the form and preserves casing '
        '(never lowercased)', () {
      final active = activeFromMap(const {
        'label_display_name': 'EPA',
        'label_display_form': 'as Ethyl Esters',
        'form_status': 'known',
        'display_form_label': 'Ethyl Esters',
        'bio_score': 18,
      });

      expect(active.formLabel, 'as Ethyl Esters');
    });

    test('display_form_label fallback also preserves casing (no lowercasing)', () {
      final active = activeFromMap(const {
        'display_label': 'Ashwagandha Root Extract',
        'form_status': 'known',
        'display_form_label': 'Root Extract',
      });

      expect(active.formLabel, 'Root Extract');
    });

    test('legacy blob without label fields keeps the existing display_label '
        'name behavior', () {
      final active = activeFromMap(const {
        'display_label': 'Magnesium Glycinate',
        'standard_name': 'Magnesium',
      });

      expect(active.name, 'Magnesium Glycinate');
    });
  });

  group('activeFromMap identity-review suppression', () {
    test('identity_conflict row shows the literal source label, flags review, '
        'and suppresses every quality/dose/safety claim', () {
      final active = activeFromMap(const {
        'identity_disposition': 'identity_conflict',
        'source_label_name': 'Marine Lipid Concentrate',
        'standard_name': 'Eicosapentaenoic Acid',
        'display_form_label': 'as Ethyl Esters',
        'form_status': 'known',
        'bio_score': 18,
        'is_safety_concern': true,
        'display_dose_label': '660 mg',
      });

      expect(active.identityNeedsReview, isTrue);
      expect(active.name, 'Marine Lipid Concentrate');
      expect(active.name, isNot('Eicosapentaenoic Acid'));
      expect(active.formQuality, FormQuality.unknown);
      expect(active.formLabel, isNull);
      expect(active.doseCallOut, DoseCallOut.withinLimits);
      expect(active.dose, isNull);
      expect(active.isSafetyConcern, isFalse);
    });

    test('missing_display_label row needs review and falls back to literal '
        'source text, never the canonical standard_name', () {
      final active = activeFromMap(const {
        'identity_disposition': 'missing_display_label',
        'raw_source_text': 'Proprietary Marine Oil',
        'standard_name': 'Fish Oil',
        'bio_score': 14,
      });

      expect(active.identityNeedsReview, isTrue);
      expect(active.name, 'Proprietary Marine Oil');
      expect(active.formQuality, FormQuality.unknown);
      expect(active.isSafetyConcern, isFalse);
    });

    test('a resolved (clean) row is never flagged for review', () {
      final active = activeFromMap(const {
        'identity_disposition': 'clean',
        'label_display_name': 'Magnesium',
        'bio_score': 18,
      });

      expect(active.identityNeedsReview, isFalse);
    });
  });

  group('inactiveFromMap', () {
    test('prefers label_display over normalized resolver display label', () {
      final inactive = inactiveFromMap(const {
        'name': 'Ascorbyl Palmitate',
        'label_display': 'Ascorbyl Palmitate',
        'display_label': 'Natural Preservatives',
        'display_role_label': 'Preservative natural',
      });

      expect(inactive.name, 'Ascorbyl Palmitate');
      expect(inactive.roleHelper, 'Preservative natural');
    });

    test('legacy blobs prefer label name over normalized display_label', () {
      final inactive = inactiveFromMap(const {
        'name': 'Ascorbyl Palmitate',
        'display_label': 'Natural Preservatives',
      });

      expect(inactive.name, 'Ascorbyl Palmitate');
    });

    test('falls back through display_label when no label field exists', () {
      final inactive = inactiveFromMap(const {
        'display_label': 'Hydroxypropyl Methylcellulose',
      });

      expect(inactive.name, 'Hydroxypropyl Methylcellulose');
    });
  });
}
