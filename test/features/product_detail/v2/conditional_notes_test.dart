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
  List<String> excludedProductForms = const [],
  List<String> flags = const [],
}) => {
  'gate_type': conditions.isEmpty ? 'drug_class' : 'condition',
  'requires': {
    'conditions_any': conditions,
    'drug_classes_any': drugClasses,
    'profile_flags_any': flags,
  },
  'excludes': {
    'conditions_any': <String>[],
    'drug_classes_any': excludedDrugClasses,
    'profile_flags_any': <String>[],
    'product_forms_any': excludedProductForms,
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
  List<String> excludedProductForms = const [],
  String evidence = 'established',
  List<String> sources = const [],
  List<String>? gateConditions,
  List<String> gateDrugClasses = const [],
  List<String> gateFlags = const [],
}) => {
  'type': drugClass != null ? 'drug_interaction' : 'interaction',
  'severity': severity,
  'display_mode_default': mode,
  'alert_headline': headline,
  'alert_body': 'Body for $headline.',
  'ingredient_name': "St. John's wort",
  'ingredient_canonical_id': 'st_johns_wort',
  'evidence_level': evidence,
  'sources': sources,
  'direction': 'harmful',
  'materiality': 'presence',
  'source': 'interaction_rules',
  'drug_class_id': ?drugClass,
  'condition_id': ?condition,
  'profile_gate': _gate(
    drugClasses: [?drugClass, ...gateDrugClasses],
    excludedDrugClasses: excludedDrugClasses,
    conditions: gateConditions ?? [?condition],
    excludedProductForms: excludedProductForms,
    flags: gateFlags,
  ),
};

List<ConditionalNote> _notes(
  List<Map<String, dynamic>> rows, {
  Set<String> drugClasses = const {},
  Set<String> conditions = const {},
  String? sex,
  String? productForm,
  bool conditionsAnswered = false,
  bool drugClassesAnswered = false,
  Map<String, String> derivedFlagByCondition = const {},
}) => composeConditionalNotes(
  detailBlob: {'warnings': rows, 'product_form': ?productForm},
  personalizedWarnings: const [],
  shownWarnings: const [],
  userConditions: conditions,
  userDrugClasses: drugClasses,
  userProfileFlags: const {},
  sex: sex,
  conditionsAnswered: conditionsAnswered,
  drugClassesAnswered: drugClassesAnswered,
  derivedFlagByCondition: derivedFlagByCondition,
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

  group('a finding the product itself rules out is not a note', () {
    // The oral-aloe pregnancy rule: its gate excludes topical products, so it
    // can never apply to one, whatever the profile says.
    final oralAloe = [
      _row(
        headline: 'Avoid oral aloe during pregnancy',
        condition: 'pregnancy',
        excludedProductForms: const ['topical_only'],
      ),
    ];

    test('topical product: no note', () {
      expect(_notes(oralAloe, productForm: 'Topical cream'), isEmpty);
    });

    test('oral or unknown form: the note shows', () {
      expect(_notes(oralAloe, productForm: 'Capsule'), hasLength(1));
      expect(_notes(oralAloe), hasLength(1));
    });

    test('a medicine on the list that the gate excludes: no note', () {
      final pregnancy = [
        _row(
          headline: 'Avoid during pregnancy',
          condition: 'pregnancy',
          excludedDrugClasses: const ['statins'],
        ),
      ];
      expect(_notes(pregnancy), hasLength(1));
      expect(_notes(pregnancy, drugClasses: const {'statins'}), isEmpty);
    });
  });

  group('an explicit "none" answer is an answer', () {
    test('conditions answered "none": no condition note', () {
      final pregnancy = [
        _row(headline: 'Avoid during pregnancy', condition: 'pregnancy'),
      ];
      expect(_notes(pregnancy), hasLength(1));
      expect(_notes(pregnancy, conditionsAnswered: true), isEmpty);
      // The other axis is still unknown.
      expect(_notes(warfarinRows, conditionsAnswered: true), hasLength(1));
    });

    test('medicines answered "none": no medicine note', () {
      expect(_notes(warfarinRows, drugClassesAnswered: true), isEmpty);
      expect(
        _notes([
          _row(headline: 'Avoid during pregnancy', condition: 'pregnancy'),
        ], drugClassesAnswered: true),
        hasLength(1),
      );
    });
  });

  group('merging keeps every finding\'s evidence and citations', () {
    const headline = "Avoid St. John's wort with warfarin";
    const urlA = 'https://example.org/a';
    const urlB = 'https://example.org/b';
    const urlC = 'https://example.org/c';

    test('one message, different evidence: two notes', () {
      final notes = _notes([
        _row(
          headline: headline,
          drugClass: 'vitamin_k_antagonists',
          sources: const [urlA],
        ),
        _row(
          headline: headline,
          drugClass: 'anticoagulants',
          excludedDrugClasses: const ['doacs', 'vitamin_k_antagonists'],
          evidence: 'moderate',
          sources: const [urlB],
        ),
      ]);
      expect(notes, hasLength(2));
      expect(notes.map((n) => n.warning.evidenceLevel.label), [
        'Strong supporting evidence',
        'Moderate supporting evidence',
      ]);
      expect(notes.map((n) => n.sourceUrls), [
        {urlA},
        {urlB},
      ]);
      expect(notes.map((n) => n.drugClassIds), [
        {'vitamin_k_antagonists'},
        {'anticoagulants'},
      ]);
    });

    test('one message, same evidence: one note with every citation', () {
      final notes = _notes([
        _row(
          headline: headline,
          drugClass: 'vitamin_k_antagonists',
          sources: const [urlA, urlB],
        ),
        _row(
          headline: headline,
          drugClass: 'anticoagulants',
          excludedDrugClasses: const ['doacs', 'vitamin_k_antagonists'],
          sources: const [urlB, urlC],
        ),
      ]);
      expect(notes, hasLength(1));
      expect(notes.single.sourceUrls.toList(), [urlA, urlB, urlC]);
    });
  });

  group('the trial answers only the unknown axis', () {
    test('a medicine gate that also needs a flag the user lacks: no note', () {
      final notes = _notes([
        _row(
          headline: 'Avoid with MAOIs after bleeding',
          drugClass: 'maois',
          gateFlags: const ['bleeding_history'],
        ),
      ]);
      expect(notes, isEmpty);
    });

    test('a condition gate that also needs a medicine class: no note', () {
      final notes = _notes([
        _row(
          headline: 'Avoid with kidney disease on NSAIDs',
          condition: 'kidney_disease',
          gateDrugClasses: const ['nsaids'],
        ),
      ]);
      expect(notes, isEmpty);
    });

    test('a pregnancy rule gated on its derived flag is still a note', () {
      final notes = _notes(
        [
          _row(
            headline: 'Avoid during pregnancy',
            condition: 'pregnancy',
            gateConditions: const [],
            gateFlags: const ['pregnant'],
          ),
        ],
        derivedFlagByCondition: const {'pregnancy': 'pregnant'},
      );
      expect(notes.single.warning.displayHeadline, 'Avoid during pregnancy');
    });
  });

  test('the most severe row for one hazard sets the note\'s text', () {
    final notes = _notes([
      _row(
        headline: 'Avoid with MAOIs',
        drugClass: 'maois',
        sources: const ['https://example.org/a'],
      ),
      _row(
        headline: 'Do not use with MAOIs',
        drugClass: 'maois',
        severity: 'contraindicated',
        sources: const ['https://example.org/b'],
      ),
    ]);
    expect(notes, hasLength(1));
    expect(notes.single.warning.displayHeadline, 'Do not use with MAOIs');
    expect(notes.single.warning.alertBody, 'Body for Do not use with MAOIs.');
    expect(notes.single.sourceUrls, {
      'https://example.org/a',
      'https://example.org/b',
    });
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
