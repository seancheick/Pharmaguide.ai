import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/features/home/home_screen.dart';

void main() {
  Widget buildTestWidget() {
    return const ProviderScope(
      child: MaterialApp(home: HomeScreen()),
    );
  }

  group('HomeScreen', () {
    testWidgets('shows greeting', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Should have a greeting based on time of day
      expect(
        find.textContaining(RegExp('Good (morning|afternoon|evening)')),
        findsOneWidget,
      );
    });

    testWidgets('shows search bar placeholder', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('Search'), findsWidgets);
    });

    testWidgets('shows category filter chips', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Omega-3'), findsOneWidget);
      expect(find.text('Probiotics'), findsOneWidget);
    });

    testWidgets('shows profile completeness banner for incomplete profile',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Default profile is 0% complete, so banner should show
      expect(find.text('Complete your health profile'), findsOneWidget);
    });

    testWidgets('shows recent scans empty state', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Scroll the CustomScrollView to ensure the Recent scans section is
      // rendered — in the default 800×600 test viewport it starts below
      // the fold, and Flutter's sliver cache extent won't build it.
      await tester.scrollUntilVisible(
        find.text('Nothing scanned yet'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Nothing scanned yet'), findsOneWidget);
    });
  });
}
