// Decision contract for the medication details sheet (2026-08-08 redesign).
//
// Pins the consumer-first structure: the complete identity state reads as
// neutral readiness ("Ready for supplement checks"), never as a safety
// endorsement; the user's own dose/schedule carries an Add/Edit action;
// RxNorm concepts stay collapsed under "Technical details"; and the four
// non-complete identity states KEEP their hedge copy — the sheet must never
// present an unresolved identity as an identified one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pharmaguide/core/data/drug_class_vocab.dart';
import 'package:pharmaguide/core/data/vocab_registry.dart';
import 'package:pharmaguide/features/stack/providers/medication_identity_providers.dart';
import 'package:pharmaguide/features/stack/v2/widgets/medication_details_sheet.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';

const _identity = MedicationIdentitySnapshot(
  name: 'Metformin',
  rxcui: '1161611',
  genericRxcui: '6809',
  ingredientRxcuis: ['6809'],
  drugClassIds: ['c1', 'c2', 'c3', 'c4', 'c5', 'c6'],
);

const _completeAssessment = MedicationIdentityAssessment(
  snapshot: _identity,
  curatedClassIds: ['metformin_group'],
  hasDirectRuleCoverage: true,
);

Future<void> _pumpSheet(
  WidgetTester tester, {
  String? dosage,
  String? frequency,
  String? reminderLabel,
  MedicationIdentitySnapshot? identity = _identity,
  MedicationIdentityAssessment? assessment = _completeAssessment,
  VoidCallback? onEditTracking,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MedicationDetailsSheet(
          name: 'Metformin',
          dosage: dosage,
          frequency: frequency,
          reminderLabel: reminderLabel,
          identity: identity,
          assessment: assessment,
          onEditTracking: onEditTracking,
        ),
      ),
    ),
  );
}

void main() {
  group('medication details sheet — consumer-first structure', () {
    testWidgets('complete identity reads as neutral readiness, not safety', (
      tester,
    ) async {
      await _pumpSheet(tester, onEditTracking: () {});

      // PGEyebrow renders its label uppercased.
      expect(find.text('READY FOR SUPPLEMENT CHECKS'), findsOneWidget);
      expect(
        find.textContaining(
          'can include Metformin in reviewed supplement and nutrient checks',
        ),
        findsOneWidget,
      );
      // The old presentation must not survive anywhere.
      expect(find.text('MATCHED FOR INTERACTION CHECKS'), findsNothing);
      expect(find.text('ABOUT THIS ENTRY'), findsNothing);
      expect(find.text('RECORDED IDENTITY'), findsNothing);
      expect(find.text('SAVED SCHEDULE'), findsNothing);
    });

    testWidgets('your details show dose, schedule, and reminder with Edit', (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        dosage: '500 mg',
        frequency: 'Twice daily',
        reminderLabel: 'Daily reminder at 8:00 AM',
        onEditTracking: () {},
      );

      expect(find.text('YOUR DETAILS'), findsOneWidget);
      expect(
        find.text('500 mg · Twice daily · Daily reminder at 8:00 AM'),
        findsOneWidget,
      );
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('missing details invite an Add action', (tester) async {
      await _pumpSheet(tester, onEditTracking: () {});

      expect(find.text('No dose or schedule saved.'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('RxNorm identity stays collapsed under Technical details', (
      tester,
    ) async {
      await _pumpSheet(tester);

      expect(find.text('Technical details'), findsOneWidget);
      expect(find.text('RxNorm concept 1161611'), findsNothing);

      await tester.tap(find.text('Technical details'));
      await tester.pump();

      expect(find.text('RxNorm concept 1161611'), findsOneWidget);
      expect(find.text('Generic ingredient concept 6809'), findsOneWidget);
      expect(find.text('6 saved medication-group identifiers'), findsOneWidget);
      expect(find.text('1 reviewed interaction group'), findsOneWidget);
    });

    testWidgets('Technical details is a 48px expandable semantic button', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpSheet(tester);

      final toggle = find.ancestor(
        of: find.text('Technical details'),
        matching: find.byType(InkWell),
      );
      expect(toggle, findsOneWidget);
      expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(find.text('Technical details')),
        matchesSemantics(
          label: 'Technical details',
          isButton: true,
          hasTapAction: true,
          hasExpandedState: true,
          isExpanded: false,
        ),
      );

      await tester.tap(find.text('Technical details'));
      await tester.pump();

      expect(
        tester.getSemantics(find.text('Technical details')),
        matchesSemantics(
          label: 'Technical details',
          isButton: true,
          hasTapAction: true,
          hasExpandedState: true,
          isExpanded: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('disclaimer and privacy footer are always present', (
      tester,
    ) async {
      await _pumpSheet(tester);

      expect(
        find.text(
          "PharmaGuide doesn't provide prescribing, side-effect, "
          'or dosing advice.',
        ),
        findsOneWidget,
      );
      expect(find.text('Saved only on this device.'), findsOneWidget);
    });
  });

  group('medication details sheet — identity guard states survive', () {
    testWidgets('unresolved identity keeps its hedge', (tester) async {
      await _pumpSheet(tester, identity: null, assessment: null);

      expect(find.text('MATCHING INCOMPLETE'), findsOneWidget);
      expect(
        find.textContaining('medication checks may be incomplete'),
        findsOneWidget,
      );
      expect(find.text('READY FOR SUPPLEMENT CHECKS'), findsNothing);
      // Nothing to disclose technically when no identity was saved.
      expect(find.text('Technical details'), findsNothing);
    });

    testWidgets('partial coverage keeps its hedge', (tester) async {
      const partial = MedicationIdentityAssessment(
        snapshot: MedicationIdentitySnapshot(
          name: 'Metformin',
          drugClassIds: ['c1'],
        ),
        curatedClassIds: ['metformin_group'],
        hasDirectRuleCoverage: false,
      );
      await _pumpSheet(tester, assessment: partial);

      expect(find.text('READY FOR SUPPLEMENT CHECKS'), findsNothing);
      expect(find.textContaining('may be'), findsWidgets);
    });
  });

  group('medication details sheet — edit hand-off', () {
    testWidgets('Edit closes the sheet before invoking the tracking editor', (
      tester,
    ) async {
      var editRequested = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showMedicationDetailsSheet(
                    context,
                    name: 'Metformin',
                    dosage: '500 mg',
                    identity: _identity,
                    assessment: _completeAssessment,
                    onEditTracking: () => editRequested = true,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('READY FOR SUPPLEMENT CHECKS'), findsOneWidget);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('READY FOR SUPPLEMENT CHECKS'), findsNothing);
      expect(editRequested, isTrue);
    });
  });

  group('medication details sheet — reviewed medication education', () {
    // Verbatim copy from the signed vocab v1.1.0 asset. If the pipeline copy
    // changes, this test SHOULD fail: these strings reach the user unedited,
    // and a paraphrase in the app would be unreviewed clinical copy.
    const anticoagulantSentence =
        'Commonly used to help prevent harmful blood clots, such as with '
        'atrial fibrillation or after a previous clot.';
    const warfarinSentence =
        'Commonly used to help prevent blood clots, such as with atrial '
        'fibrillation, mechanical heart valves, or after a previous clot.';

    DrugClassEntry entry(String id, {String? groupLabel, String? sentence}) {
      return DrugClassEntry(
        id: id,
        name: 'unused-in-sheet',
        groupLabel: groupLabel,
        commonlyUsedFor: sentence,
        notes: 'unused-in-sheet',
        examples: const ['warfarin (Coumadin)'],
        rxStatus: 'rx_only',
        userSelectable: false,
      );
    }

    tearDown(VocabRegistry.instance.debugReset);

    testWidgets('renders the reviewed group label and sentence verbatim', (
      tester,
    ) async {
      VocabRegistry.instance.debugSeed(
        drugClasses: {
          'anticoagulants': entry(
            'anticoagulants',
            groupLabel: 'Blood thinners',
            sentence: anticoagulantSentence,
          ),
        },
      );

      await _pumpSheet(
        tester,
        identity: const MedicationIdentitySnapshot(
          name: 'Warfarin',
          drugClassIds: ['anticoagulants'],
        ),
      );

      expect(find.text('MEDICATION GROUP'), findsOneWidget);
      expect(find.text('Blood thinners'), findsOneWidget);
      expect(find.text(anticoagulantSentence), findsOneWidget);

      // Education is orientation, not a safety verdict — the disclaimer and
      // the identity hedge must survive alongside it.
      expect(
        find.text(
          "PharmaGuide doesn't provide prescribing, side-effect, "
          'or dosing advice.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('omits the section entirely when the fields are absent', (
      tester,
    ) async {
      // A pre-v1.1.0 bundled asset: the entry resolves, but carries no
      // consumer copy. The parser yields nulls and the sheet must stay silent
      // rather than render an empty heading.
      VocabRegistry.instance.debugSeed(
        drugClasses: {'anticoagulants': entry('anticoagulants')},
      );

      await _pumpSheet(
        tester,
        identity: const MedicationIdentitySnapshot(
          name: 'Warfarin',
          drugClassIds: ['anticoagulants'],
        ),
      );

      expect(find.text('MEDICATION GROUP'), findsNothing);
      expect(find.text('Blood thinners'), findsNothing);
      expect(find.textContaining('Commonly used'), findsNothing);
      // The rest of the sheet is unaffected.
      expect(find.text('YOUR DETAILS'), findsOneWidget);
    });

    testWidgets('half-populated copy renders nothing, not a stray label', (
      tester,
    ) async {
      VocabRegistry.instance.debugSeed(
        drugClasses: {
          'anticoagulants': entry(
            'anticoagulants',
            groupLabel: 'Blood thinners',
          ),
        },
      );

      await _pumpSheet(
        tester,
        identity: const MedicationIdentitySnapshot(
          name: 'Warfarin',
          drugClassIds: ['anticoagulants'],
        ),
      );

      expect(find.text('MEDICATION GROUP'), findsNothing);
      expect(find.text('Blood thinners'), findsNothing);
    });

    testWidgets('multi-class medication shows one primary group, not a pile', (
      tester,
    ) async {
      // Warfarin is both anticoagulants and vitamin_k_antagonists, which share
      // the "Blood thinners" bucket by design. The sheet takes the first id
      // carrying both fields; the shared label must not render twice.
      VocabRegistry.instance.debugSeed(
        drugClasses: {
          'anticoagulants': entry(
            'anticoagulants',
            groupLabel: 'Blood thinners',
            sentence: anticoagulantSentence,
          ),
          'vitamin_k_antagonists': entry(
            'vitamin_k_antagonists',
            groupLabel: 'Blood thinners',
            sentence: warfarinSentence,
          ),
        },
      );

      await _pumpSheet(
        tester,
        identity: const MedicationIdentitySnapshot(
          name: 'Warfarin',
          drugClassIds: ['anticoagulants', 'vitamin_k_antagonists'],
        ),
      );

      expect(find.text('MEDICATION GROUP'), findsOneWidget);
      expect(find.text('Blood thinners'), findsOneWidget);
      expect(find.text(anticoagulantSentence), findsOneWidget);
      expect(find.text(warfarinSentence), findsNothing);
    });

    testWidgets('skips unresolved ids and uses the first reviewed one', (
      tester,
    ) async {
      VocabRegistry.instance.debugSeed(
        drugClasses: {
          'anticoagulants': entry(
            'anticoagulants',
            groupLabel: 'Blood thinners',
            sentence: anticoagulantSentence,
          ),
        },
      );

      await _pumpSheet(
        tester,
        identity: const MedicationIdentitySnapshot(
          name: 'Warfarin',
          drugClassIds: ['not_in_vocab', 'anticoagulants'],
        ),
      );

      expect(find.text('Blood thinners'), findsOneWidget);
      expect(find.text(anticoagulantSentence), findsOneWidget);
    });

    testWidgets('uninitialized registry renders no education', (tester) async {
      // Boot window: init() has not completed. Sync lookups return null and
      // the section must simply not appear.
      VocabRegistry.instance.debugReset();

      await _pumpSheet(
        tester,
        identity: const MedicationIdentitySnapshot(
          name: 'Warfarin',
          drugClassIds: ['anticoagulants'],
        ),
      );

      expect(find.text('MEDICATION GROUP'), findsNothing);
      expect(find.textContaining('Commonly used'), findsNothing);
    });

    testWidgets('no saved identity renders no education', (tester) async {
      VocabRegistry.instance.debugSeed(
        drugClasses: {
          'anticoagulants': entry(
            'anticoagulants',
            groupLabel: 'Blood thinners',
            sentence: anticoagulantSentence,
          ),
        },
      );

      await _pumpSheet(tester, identity: null, assessment: null);

      expect(find.text('MEDICATION GROUP'), findsNothing);
      expect(find.text('MATCHING INCOMPLETE'), findsOneWidget);
    });
  });
}
