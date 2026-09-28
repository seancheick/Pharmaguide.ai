import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/reduce_transparency.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';

Future<void> _pumpBar(WidgetTester tester, {required bool reduce}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: V2Theme.light,
      home: ReduceTransparencyScope(
        notifier: ValueNotifier(reduce),
        child: Scaffold(
          bottomNavigationBar: PGFrostedNavBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the bar blurs the content behind it by default', (tester) async {
    await _pumpBar(tester, reduce: false);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('Reduce Transparency gives an opaque bar with no blur', (
    tester,
  ) async {
    await _pumpBar(tester, reduce: true);
    expect(find.byType(BackdropFilter), findsNothing);

    final box = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(PGFrostedNavBar),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .first;
    expect(box.gradient, isNull);
    expect(box.color!.a, 1.0);
  });
}
