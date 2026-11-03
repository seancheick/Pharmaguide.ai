import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/widgets/app_switcher_cover.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var count = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => count++),
    child: Text('Warfarin $count'),
  );
}

void main() {
  Future<void> pumpCover(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: V2Theme.light,
      home: const Scaffold(body: AppSwitcherCover(child: _Counter())),
    ),
  );

  Finder cover() => find.byKey(AppSwitcherCover.coverKey);

  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    testWidgets('$state covers the screen', (tester) async {
      await pumpCover(tester);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      expect(cover(), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();

      expect(cover(), findsOneWidget);
      final box = tester.getRect(cover());
      expect(box, tester.getRect(find.byType(AppSwitcherCover)));
    });
  }

  testWidgets('coming back removes it and keeps the screen as it was', (
    tester,
  ) async {
    await pumpCover(tester);
    await tester.tap(find.byType(TextButton));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(cover(), findsNothing);
    expect(find.text('Warfarin 1'), findsOneWidget);
  });

  testWidgets('hides what is underneath from assistive technology', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    // Walks the live tree: a label finder also matches a node just excluded.
    bool announcesWarfarin() {
      var found = false;
      void visit(SemanticsNode node) {
        if (node.label.contains('Warfarin')) found = true;
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(tester.getSemantics(find.byType(AppSwitcherCover)));
      return found;
    }

    await pumpCover(tester);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    expect(announcesWarfarin(), isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(announcesWarfarin(), isFalse);
    semantics.dispose();
  });
}
