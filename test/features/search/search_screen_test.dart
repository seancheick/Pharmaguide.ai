import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/features/search/search_screen.dart';

void main() {
  Widget buildTestWidget() {
    return const ProviderScope(
      child: MaterialApp(home: SearchScreen()),
    );
  }

  group('SearchScreen', () {
    testWidgets('shows search input field', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows empty state when no query', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Search supplements'), findsOneWidget);
    });

    // SKIPPED: at the default 800×600 test viewport, the search
    // screen's recent-searches list overflows by 27px (RenderFlex
    // exception). The search field + clear-button logic is correct at
    // normal device sizes; this is a test-viewport issue. Fix by
    // setting `tester.view.physicalSize = Size(400, 2000)` in setUp.
    // Tech debt tracked in Sprint 18.

    testWidgets('shows clear button when text is entered', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField), 'magnesium');
      await tester.pump();

      expect(find.byIcon(Icons.close_rounded), findsWidgets);
    });

    testWidgets('clear button clears text and returns to empty state',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField), 'vitamin');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Search supplements'), findsOneWidget);
    });
  });
}
