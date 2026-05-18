// Tests for `PGContextChips` + `PGWhyThisFitsExpander` — the v2
// components that close the v1 ForYouSection gap (context chips
// header + "Why this fits you" expandable). Locks in:
//   • Empty chips list → SizedBox.shrink (no padding leak)
//   • Snake_case humanization
//   • Expander defaults collapsed → tap reveals up to 4 bullets

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_for_you_extras.dart';

Future<void> _pumpChips(WidgetTester tester, List<String> chips) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: PGContextChips(chips: chips)),
    ),
  );
}

Future<void> _pumpExpander(WidgetTester tester, List<String> reasons) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: PGWhyThisFitsExpander(reasons: reasons)),
    ),
  );
}

void main() {
  group('PGContextChips', () {
    testWidgets('empty list renders SizedBox.shrink', (tester) async {
      await _pumpChips(tester, const []);
      await tester.pumpAndSettle();
      expect(find.byType(Wrap), findsNothing);
    });

    testWidgets('humanizes snake_case labels', (tester) async {
      await _pumpChips(tester, const [
        'sleep_quality',
        'GOAL_INCREASE_ENERGY',
        'diabetes',
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Sleep Quality'), findsOneWidget);
      // ALL_CAPS_SNAKE → "ALL CAPS SNAKE" (first letter upper of each
      // already-upper segment stays upper).
      expect(find.text('GOAL INCREASE ENERGY'), findsOneWidget);
      expect(find.text('Diabetes'), findsOneWidget);
    });
  });

  group('PGWhyThisFitsExpander', () {
    testWidgets('empty reasons → SizedBox.shrink', (tester) async {
      await _pumpExpander(tester, const []);
      await tester.pumpAndSettle();
      expect(find.text('Why this fits you'), findsNothing);
    });

    testWidgets('collapsed by default; tap reveals bullets', (tester) async {
      await _pumpExpander(tester, const [
        'Supports your sleep quality goal',
        'Contains magnesium glycinate at clinical dose',
        'Free from your allergens',
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Why this fits you'), findsOneWidget);
      // Pre-tap: bullets hidden.
      expect(find.text('Supports your sleep quality goal'), findsNothing);

      await tester.tap(find.text('Why this fits you'));
      await tester.pumpAndSettle();

      // Post-tap: all 3 bullets visible.
      expect(find.text('Supports your sleep quality goal'), findsOneWidget);
      expect(find.text('Contains magnesium glycinate at clinical dose'),
          findsOneWidget);
      expect(find.text('Free from your allergens'), findsOneWidget);
    });

    testWidgets('caps at 4 bullets even if more reasons supplied', (
      tester,
    ) async {
      await _pumpExpander(tester, const [
        'reason 1',
        'reason 2',
        'reason 3',
        'reason 4',
        'reason 5',
        'reason 6',
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Why this fits you'));
      await tester.pumpAndSettle();

      expect(find.text('reason 1'), findsOneWidget);
      expect(find.text('reason 4'), findsOneWidget);
      expect(find.text('reason 5'), findsNothing);
      expect(find.text('reason 6'), findsNothing);
    });
  });
}
