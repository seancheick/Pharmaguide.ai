import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';

void main() {
  group('PGModal.bottomSheet', () {
    testWidgets(
      'presents a sheet with the given child and dismisses to a value',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final result = await PGModal.bottomSheet<String>(
                      context: context,
                      builder: (ctx) => SizedBox(
                        height: 200,
                        child: Center(
                          child: TextButton(
                            onPressed: () => Navigator.of(ctx).pop('done'),
                            child: const Text('finish'),
                          ),
                        ),
                      ),
                    );
                    // Verify the result round-trips by writing it to a Text.
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text('result=$result')),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // Sheet is open — child rendered.
        expect(find.text('finish'), findsOneWidget);

        await tester.tap(find.text('finish'));
        await tester.pumpAndSettle();

        // Sheet closed; result snackbar shows the popped value.
        expect(find.text('result=done'), findsOneWidget);
      },
    );

    testWidgets('returns null when the user dismisses without a result', (
      tester,
    ) async {
      String? receivedResult = 'untouched';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  receivedResult = await PGModal.bottomSheet<String>(
                    context: context,
                    builder: (ctx) => const SizedBox(height: 200),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Tap above the sheet to dismiss (barrier).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(receivedResult, isNull);
    });
  });
}
