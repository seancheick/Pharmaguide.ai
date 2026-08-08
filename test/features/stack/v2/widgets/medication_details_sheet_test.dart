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
      expect(
        find.text('6 saved medication-group identifiers'),
        findsOneWidget,
      );
      expect(find.text('1 reviewed interaction group'), findsOneWidget);
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
      expect(
        find.textContaining('may be'),
        findsWidgets,
      );
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
}
