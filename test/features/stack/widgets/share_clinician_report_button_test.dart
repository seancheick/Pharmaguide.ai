import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/core/data/clinical_profile_schema.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart'
    as reference_data;
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/features/stack/providers/medication_identity_providers.dart';
import 'package:pharmaguide/features/stack/widgets/share_clinician_report_button.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';

// Spec: INITIATIVE_STACK_INTELLIGENCE.md, Track C, C3.
//
// Heavy-lift integration (DB + every safety provider + PDF share service) is
// covered by ClinicianPdfBuilder tests, ShareService PDF tests, and the
// real-device smoke pass.
//
// This widget test focuses on what only a widget test can prove:
//   1. The button mounts inside a Material app + ProviderScope without
//      throwing on the synchronous render path.
//   2. The icon + tooltip are present (a11y / discoverability).
//   3. Tapping doesn't crash on the synchronous codepath even when
//      every async input resolves to its empty-stack fallback.

void main() {
  Widget wrap(
    Widget child, {
    required CoreDatabase coreDb,
    required UserDatabase userDb,
    ReferenceDataRepository? referenceDataRepository,
    List<UserStacksLocalData> stack = const [],
    Map<String, MedicationIdentityAssessment> identityAssessments = const {},
  }) {
    return ProviderScope(
      overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        userDatabaseProvider.overrideWithValue(userDb),
        activeStackProvider.overrideWith((ref) async => stack),
        medicationIdentityAssessmentsProvider.overrideWith(
          (ref) async => identityAssessments,
        ),
        stackSafetyReportProvider.overrideWith(
          (ref) async => const StackSafetyReport(),
        ),
        synergyReportProvider.overrideWith(
          (ref) async => SynergyReport.empty(),
        ),
        recalledIngredientsReportProvider.overrideWith(
          (ref) async => RecalledIngredientsReport.empty(),
        ),
        stackDoseThresholdAlertsProvider.overrideWith((ref) async => const []),
        depletionReportProvider.overrideWith(
          (ref) async => (
            status: MedNutrientLoadStatus.loaded,
            matches: const <DepletionMatch>[],
          ),
        ),
        reference_data.referenceDataRepositoryProvider.overrideWithValue(
          referenceDataRepository ?? _AvailableReferenceDataRepository(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(appBar: AppBar(actions: [child])),
      ),
    );
  }

  testWidgets('renders the share icon + tooltip', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await tester.pumpWidget(
      wrap(const ShareClinicianReportButton(), coreDb: coreDb, userDb: userDb),
    );
    await tester.pump();

    expect(find.byType(IconButton), findsOneWidget);
    expect(find.byTooltip('Share with clinician'), findsOneWidget);
    expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  testWidgets('tap builds a PDF and sends it to the share service', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    List<int>? capturedPdf;
    var textShareReached = false;
    final fakeShareService = ShareService(
      shareOverride: (text, {subject}) async {
        textShareReached = true;
      },
      pdfShareOverride: (bytes, {required filename}) async {
        capturedPdf = bytes;
        return true;
      },
    );

    await tester.pumpWidget(
      wrap(
        ShareClinicianReportButton(shareService: fakeShareService),
        coreDb: coreDb,
        userDb: userDb,
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Share with clinician'));
    await tester.pumpAndSettle();

    expect(textShareReached, isFalse);
    expect(capturedPdf, isNotNull);
    expect(capturedPdf!.take(5), orderedEquals('%PDF-'.codeUnits));

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  testWidgets('missing provenance metadata does not block PDF sharing', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    List<int>? capturedPdf;
    final fakeShareService = ShareService(
      pdfShareOverride: (bytes, {required filename}) async {
        capturedPdf = bytes;
        return true;
      },
    );

    await tester.pumpWidget(
      wrap(
        ShareClinicianReportButton(shareService: fakeShareService),
        coreDb: coreDb,
        userDb: userDb,
        referenceDataRepository: _UnavailableReferenceDataRepository(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Share with clinician'));
    await tester.pumpAndSettle();

    expect(capturedPdf, isNotNull);
    expect(capturedPdf!.take(5), orderedEquals('%PDF-'.codeUnits));

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  testWidgets('PDF records unresolved medication identity coverage', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    final now = DateTime.utc(2026, 7, 29);
    final medication = UserStacksLocalData(
      id: 'med-unresolved',
      type: 'medication',
      name: 'Example medication',
      addedAt: now,
      clientUpdatedAt: now,
    );
    List<int>? capturedPdf;
    final fakeShareService = ShareService(
      pdfShareOverride: (bytes, {required filename}) async {
        capturedPdf = bytes;
        return true;
      },
    );

    await tester.pumpWidget(
      wrap(
        ShareClinicianReportButton(shareService: fakeShareService),
        coreDb: coreDb,
        userDb: userDb,
        stack: [medication],
        identityAssessments: {
          medication.id: const MedicationIdentityAssessment(
            snapshot: MedicationIdentitySnapshot(name: 'Example medication'),
            curatedClassIds: [],
            hasDirectRuleCoverage: false,
          ),
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Share with clinician'));
    await tester.pumpAndSettle();

    expect(capturedPdf, isNotNull);
    expect(capturedPdf!.take(5), orderedEquals('%PDF-'.codeUnits));

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  testWidgets('tap records report build failures before showing snackbar', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    final beforeCount = CrashReportingService().recordedErrors.length;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
          activeStackProvider.overrideWith(
            (ref) async => throw StateError('stack unavailable'),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ShareClinicianReportButton()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Share with clinician'));
    await tester.pumpAndSettle();

    final errors = CrashReportingService().recordedErrors;
    expect(errors.length, beforeCount + 1);
    expect(errors.last.hint, 'clinician_share_pdf:build_failed');
    expect(
      find.text('Could not build the report — try again in a moment.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });
}

abstract class _TestReferenceDataRepository extends ReferenceDataRepository {
  @override
  Future<ClinicalProfileSchema> loadClinicalProfileSchema() async {
    return const ClinicalProfileSchema(
      selectableConditions: <ClinicalProfileOption>[
        ClinicalProfileOption(
          id: 'pregnancy',
          label: 'Pregnancy',
          description: 'Currently pregnant.',
          displayPriority: 1,
        ),
      ],
      userSelectableFlags: <ClinicalProfileFlag>[],
      derivedFlagByCondition: <String, String>{'pregnancy': 'pregnant'},
    );
  }
}

class _UnavailableReferenceDataRepository extends _TestReferenceDataRepository {
  @override
  Future<({MedNutrientLoadStatus status, Map<String, dynamic> data})>
  loadMedicationDepletions() async {
    throw const FormatException('clinical metadata unavailable');
  }
}

class _AvailableReferenceDataRepository extends _TestReferenceDataRepository {
  @override
  Future<({MedNutrientLoadStatus status, Map<String, dynamic> data})>
  loadMedicationDepletions() async {
    return (
      status: MedNutrientLoadStatus.loaded,
      data: const <String, dynamic>{
        '_metadata': <String, dynamic>{
          'content_version': 'test-clinical-version',
          'content_hash': 'sha256:test-clinical-hash',
        },
        'depletions': <dynamic>[],
      },
    );
  }
}
