import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/features/settings/v2/delete_account_sheet.dart';
import 'package:pharmaguide/services/auth/account_deletion_service.dart';

void main() {
  testWidgets('requires two deliberate confirmations and exact DELETE text', (
    tester,
  ) async {
    String? confirmation;
    await tester.pumpWidget(
      MaterialApp(
        theme: V2Theme.light,
        home: Scaffold(
          body: DeleteAccountSheet(
            onDelete: (value) async {
              confirmation = value;
              return AccountDeletionResult.deleted;
            },
            onDeleted: () {},
          ),
        ),
      ),
    );

    expect(find.text('Delete account permanently?'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    expect(find.textContaining('submission photos'), findsOneWidget);
    expect(find.textContaining('health history'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.text('Type DELETE to confirm'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Delete forever'),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Delete forever'),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    await tester.tap(find.text('I understand this cannot be undone'));
    await tester.pump();
    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();

    expect(confirmation, 'DELETE');
  });

  testWidgets('remote failure keeps the sheet open with a retry message', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: V2Theme.light,
        home: Scaffold(
          body: DeleteAccountSheet(
            onDelete: (_) async => AccountDeletionResult.remoteFailed,
            onDeleted: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.tap(find.text('I understand this cannot be undone'));
    await tester.pump();
    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not be confirmed'), findsOneWidget);
    expect(find.textContaining('local data is still'), findsOneWidget);
  });

  testWidgets(
    'partial local cleanup keeps the modal open with recovery guidance',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var deletedCallbackCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: V2Theme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => DeleteAccountSheet(
                    onDelete: (_) async =>
                        AccountDeletionResult.deletedLocalCleanupIncomplete,
                    onDeleted: () => deletedCallbackCalled = true,
                  ),
                ),
                child: const Text('Open deletion'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open deletion'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.tap(find.text('I understand this cannot be undone'));
      await tester.pump();
      await tester.tap(find.text('Delete forever'));
      await tester.pumpAndSettle();

      expect(deletedCallbackCalled, isTrue);
      expect(find.byType(DeleteAccountSheet), findsOneWidget);
      expect(find.textContaining('online account was deleted'), findsOneWidget);
      expect(find.textContaining('reinstall the app'), findsOneWidget);
    },
  );

  testWidgets('confirmation field remains visible above the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: V2Theme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => PGModal.bottomSheet<void>(
                context: context,
                builder: (_) => DeleteAccountSheet(
                  onDelete: (_) async => AccountDeletionResult.deleted,
                  onDeleted: () {},
                ),
              ),
              child: const Text('Open deletion'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open deletion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    await tester.pumpAndSettle();

    final keyboardTop = tester.view.physicalSize.height - 360;
    expect(
      tester.getBottomRight(find.byType(TextField)).dy,
      lessThanOrEqualTo(keyboardTop),
    );
  });
}
