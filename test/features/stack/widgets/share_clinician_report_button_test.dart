import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/features/stack/widgets/share_clinician_report_button.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

// Spec: INITIATIVE_STACK_INTELLIGENCE.md, Track C, C3.
//
// Heavy-lift integration (DB + every safety provider + ShareService) is
// covered transitively by:
//   - C1 unit tests on `ClinicianReportBuilder` (golden-string contract)
//   - C2 unit tests on `ShareService.shareClinicianReport`
//   - Real-device smoke (Sean's TestFlight pass)
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
  }) {
    return ProviderScope(
      overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        userDatabaseProvider.overrideWithValue(userDb),
        activeStackProvider.overrideWith((ref) async => const []),
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
