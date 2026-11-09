import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';

void main() {
  testWidgets('stored messenger without a scaffold does not throw', (
    tester,
  ) async {
    final key = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(scaffoldMessengerKey: key, home: const SizedBox()),
    );
    expect(
      () => PGToast.showWith(key.currentState, 'Signed out'),
      returnsNormally,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposed stored messenger does not throw', (tester) async {
    final key = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(scaffoldMessengerKey: key, home: const Scaffold()),
    );
    final messenger = key.currentState;
    await tester.pumpWidget(const SizedBox());
    expect(() => PGToast.showWith(messenger, 'Signed out'), returnsNormally);
  });

  testWidgets('normal toast remains visible', (tester) async {
    final key = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(scaffoldMessengerKey: key, home: const Scaffold()),
    );
    PGToast.showWith(key.currentState, 'Saved');
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
  });
}
