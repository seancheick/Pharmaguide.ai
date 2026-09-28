import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/dev/glass_tab_bar_prototype.dart';

const _tabs = [
  PGGlassTab(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: 'Home',
  ),
  PGGlassTab(icon: Icons.qr_code, selectedIcon: Icons.qr_code, label: 'Scan'),
  PGGlassTab(
    icon: Icons.layers_outlined,
    selectedIcon: Icons.layers,
    label: 'Stack',
  ),
  PGGlassTab(
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    label: 'Profile',
  ),
];

Future<List<int>> _pumpBar(
  WidgetTester tester, {
  bool glass = true,
  bool reduceMotion = false,
}) async {
  final selections = <int>[];
  var index = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: V2Theme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(402, 874),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: StatefulBuilder(
                builder: (context, setState) => PGGlassTabBar(
                  tabs: _tabs,
                  selectedIndex: index,
                  glassOverride: glass,
                  onSelected: (i) => setState(() {
                    index = i;
                    selections.add(i);
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return selections;
}

void main() {
  testWidgets('a tap selects the tab', (tester) async {
    final selections = await _pumpBar(tester);
    await tester.tap(find.text('Stack'));
    await tester.pumpAndSettle();
    expect(selections, [2]);
  });

  testWidgets('touch-down grows a lens that follows the finger to release', (
    tester,
  ) async {
    final selections = await _pumpBar(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Home')),
    );
    // The spring starts inside the pointer event; its first tick is t=0.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(RawMagnifier), findsOneWidget);

    await gesture.moveTo(tester.getCenter(find.text('Stack')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(RawMagnifier), findsOneWidget);
    expect(selections, isEmpty, reason: 'selection commits on release');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(selections, [2]);
    expect(find.byType(RawMagnifier), findsNothing, reason: 'lens settles');
  });

  testWidgets('Reduce Motion drops the lens but still selects', (tester) async {
    final selections = await _pumpBar(tester, reduceMotion: true);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Scan')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(RawMagnifier), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selections, [1]);
  });

  testWidgets('the no-glass path (Increase Contrast, Android) has no blur', (
    tester,
  ) async {
    await _pumpBar(tester, glass: false);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Scan')),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(RawMagnifier), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('tabs are labelled buttons with selection and 44pt targets', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpBar(tester);
    expect(
      tester.getSemantics(find.text('Home')),
      matchesSemantics(
        label: 'Home',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    for (final label in ['Home', 'Scan', 'Stack', 'Profile']) {
      final box = find
          .ancestor(of: find.text(label), matching: find.byType(ConstrainedBox))
          .first;
      final size = tester.getSize(box);
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    }
    handle.dispose();
  });
}
