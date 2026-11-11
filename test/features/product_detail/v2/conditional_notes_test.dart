// Controls for Dr. Pham G4 conditional notes (composeConditionalNotes); the
// page-level cases are in conditional_notes_on_page_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/data/drug_class_vocab.dart';
import 'package:pharmaguide/core/data/vocab_registry.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_section.dart';
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';

Map<String, dynamic> _gate({
  List<String> drugClasses = const [],
  List<String> excludedDrugClasses = const [],
  List<String> conditions = const [],
}) => {
  'gate_type': conditions.isEmpty ? 'drug_class' : 'condition',
  'requires': {
    'conditions_any': conditions,
    'drug_classes_any': drugClasses,
    'profile_flags_any': <String>[],
  },
  'excludes': {
    'conditions_any': <String>[],
    'drug_classes_any': excludedDrugClasses,
    'profile_flags_any': <String>[],
    'product_forms_any': <String>[],
    'nutrient_forms_any': <String>[],
  },
  'dose': null,
};

Map<String, dynamic> _row({
  required String headline,
  String severity = 'avoid',
  String mode = 'informational',
  String? drugClass,
  List<String> excludedDrugClasses = const [],
  String? condition,
}) => {
  'type': drugClass != null ? 'drug_interaction' : 'interaction',
  'severity': severity,
  'display_mode_default': mode,
  'alert_headline': headline,
  'alert_body': 'Body for $headline.',
  'ingredient_name': "St. John's wort",
  'ingredient_canonical_id': 'st_johns_wort',
  'evidence_level': 'established',
  'direction': 'harmful',
  'materiality': 'presence',
  'source': 'interaction_rules',
  'drug_class_id': ?drugClass,
  'condition_id': ?condition,
  'profile_gate': _gate(
    drugClasses: [?drugClass],
    excludedDrugClasses: excludedDrugClasses,
    conditions: [?condition],
  ),
};

List<ConditionalNote> _notes(
  List<Map<String, dynamic>> rows, {
  Set<String> drugClasses = const {},
  Set<String> conditions = const {},
  String? sex,
}) => composeConditionalNotes(
  detailBlob: {'warnings': rows},
  personalizedWarnings: const [],
  shownWarnings: const [],
  userConditions: conditions,
  userDrugClasses: drugClasses,
  userProfileFlags: const {},
  sex: sex,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    VocabRegistry.instance.debugSeed(drugClasses: await loadDrugClassVocab());
  });
  tearDownAll(VocabRegistry.instance.debugReset);

  const warfarin = "Avoid St. John's wort with warfarin";
  final warfarinRows = [
    _row(headline: warfarin, drugClass: 'vitamin_k_antagonists'),
    _row(
      headline: warfarin,
      drugClass: 'anticoagulants',
      excludedDrugClasses: const ['doacs', 'vitamin_k_antagonists'],
    ),
  ];

  test(
    'the warfarin-type and unidentified blood-thinner rows make one note',
    () {
      final notes = _notes(warfarinRows);
      expect(notes.map((n) => n.warning.displayHeadline), [warfarin]);
      // The merged note keeps both classes it is relevant to.
      expect(notes.single.drugClassIds, {
        'vitamin_k_antagonists',
        'anticoagulants',
      });
      expect(
        conditionalNoteScope(notes.single),
        'Relevant if you take: Warfarin-type blood thinners or Blood thinners. '
        'Add your medicines to check whether it applies to you.',
      );
    },
  );

  test('a medicine user whose medicines have no class is told to ask', () {
    expect(
      conditionalNoteScope(_notes(warfarinRows).single, medicinesEntered: true),
      'Relevant if you take: Warfarin-type blood thinners or Blood thinners. '
      "We couldn't match your medicines to a group; ask your pharmacist "
      'whether this applies to you.',
    );
  });

  test('pregnancy and breastfeeding rows with one message keep both', () {
    const headline = 'Unresolved ingredient identity — avoid';
    final notes = _notes([
      _row(headline: headline, condition: 'pregnancy'),
      _row(headline: headline, condition: 'lactation'),
    ]);
    expect(notes, hasLength(1));
    expect(notes.single.conditionIds, {'pregnancy', 'lactation'});
    expect(conditionalNoteScope(notes.single), startsWith('Relevant to: '));
    expect(conditionalNoteScope(notes.single), contains(' or '));
  });

  test('a contraindicated finding is a note too (G4 covers both)', () {
    final notes = _notes([
      _row(
        headline: 'Do not combine with transplant medicines',
        severity: 'contraindicated',
        drugClass: 'immunosuppressants',
      ),
    ]);
    expect(notes, hasLength(1));
  });

  test('entered medicines make the medicine axis known: no note', () {
    expect(_notes(warfarinRows, drugClasses: const {'statins'}), isEmpty);
  });

  test('a matching medicine gives the warning, not a note', () {
    expect(
      _notes(
        warfarinRows,
        drugClasses: const {'anticoagulants', 'vitamin_k_antagonists'},
      ),
      isEmpty,
    );
  });

  test('caution and monitor findings stay hidden without a match', () {
    expect(
      _notes([
        _row(
          headline: 'May raise INR on warfarin',
          severity: 'caution',
          mode: 'suppress',
          drugClass: 'vitamin_k_antagonists',
        ),
      ]),
      isEmpty,
    );
  });

  test('a pregnancy note shows while conditions and sex are unknown', () {
    final pregnancy = [
      _row(headline: 'Avoid during pregnancy', condition: 'pregnancy'),
    ];
    expect(_notes(pregnancy), hasLength(1));
    expect(_notes(pregnancy, sex: 'Female'), hasLength(1));
    expect(_notes(pregnancy, sex: 'Male'), isEmpty);
    expect(_notes(pregnancy, conditions: const {'kidney_disease'}), isEmpty);
  });

  test('a male profile still gets a non-life-stage condition note', () {
    expect(
      _notes([
        _row(
          headline: 'Avoid with kidney disease',
          condition: 'kidney_disease',
        ),
      ], sex: 'Male'),
      hasLength(1),
    );
  });

  test('a note that repeats a warning already on the page is dropped', () {
    final shown = parseBlobWarnings({'warnings': warfarinRows});
    final notes = composeConditionalNotes(
      detailBlob: {'warnings': warfarinRows},
      personalizedWarnings: const [],
      shownWarnings: shown,
      userConditions: const {},
      userDrugClasses: const {},
      userProfileFlags: const {},
    );
    expect(notes, isEmpty);
  });
}
