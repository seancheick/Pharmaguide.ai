import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_pillar_bar.dart';

void main() {
  group('PGPillarBar', () {
    testWidgets('renders label + percent text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PGPillarBar(
              label: 'Ingredient Quality',
              value: 22,
              max: 25,
            ),
          ),
        ),
      );
      expect(find.text('Ingredient Quality'), findsOneWidget);
      // 22/25 = 88% — rounded percent renders.
      expect(find.text('88%'), findsOneWidget);
    });

    testWidgets('null value renders placeholder dash', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PGPillarBar(
              label: 'Brand Trust',
              value: null,
              max: 5,
            ),
          ),
        ),
      );
      expect(find.text('Brand Trust'), findsOneWidget);
      // null state shows an em-dash, not a percent.
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('tone color derives from tier ladder (exceptional ≥ 85%)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PGPillarBar(
              label: 'X',
              value: 23, // 23/25 = 92% → exceptional tier
              max: 25,
            ),
          ),
        ),
      );
      // The percent Text should be tinted to the exceptional tone.
      final percentText = tester.widget<Text>(find.text('92%'));
      expect(percentText.style?.color, AppTheme.scoreExceptional);
    });

    testWidgets('tone color drops to low tier below 25%', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PGPillarBar(
              label: 'X',
              value: 4, // 4/25 = 16% → low tier
              max: 25,
            ),
          ),
        ),
      );
      final percentText = tester.widget<Text>(find.text('16%'));
      expect(percentText.style?.color, AppTheme.scoreLow);
    });

    testWidgets('value above max clamps to 100% (no overflow paint)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PGPillarBar(
              label: 'X',
              value: 30, // overshoot
              max: 25,
            ),
          ),
        ),
      );
      // Clamped to 100%.
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('compact variant renders shorter bar height', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: PGPillarBar(
                label: 'X',
                value: 20,
                max: 25,
                compact: true,
              ),
            ),
          ),
        ),
      );
      // Just verify it doesn't throw and the content still renders.
      expect(find.text('X'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
    });
  });
}
