import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/widgets/share_clinician_report_button.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';

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

  testWidgets('tap completes without throwing and either reaches the share '
      'service or surfaces the failure snackbar — never hangs', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    String? capturedMarkdown;
    final fakeShareService = ShareService(
      shareOverride: (text, {subject}) async {
        capturedMarkdown = text;
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

    // With empty memory DBs one of two outcomes is acceptable:
    //   (a) every provider resolves to its empty-stack fallback and
    //       the share service captures the builder output, OR
    //   (b) one of the deep providers (e.g. interaction DB asset
    //       loading) errors and the catch-block snackbar fires.
    // The contract under test is: the button never crashes and never
    // hangs on tap. Markdown shape is verified by C1's golden test;
    // share invocation by C2's unit tests.
    final shareReached = capturedMarkdown != null;
    final snackbarShown = find
        .text('Could not build the report — try again in a moment.')
        .evaluate()
        .isNotEmpty;

    expect(
      shareReached || snackbarShown,
      isTrue,
      reason:
          'tap must result in ONE of: share-service invocation '
          'OR a user-visible failure snackbar — silent hang is the '
          'one outcome we forbid',
    );

    if (shareReached) {
      // When the empty-stack codepath did succeed end-to-end, the
      // captured payload should be the builder output (not a
      // placeholder).
      expect(
        capturedMarkdown!,
        contains('# My Supplement Stack — Clinician Summary'),
      );
      expect(capturedMarkdown!, contains('Generated on device'));
      expect(capturedMarkdown!, contains('not medical advice'));
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });
}
