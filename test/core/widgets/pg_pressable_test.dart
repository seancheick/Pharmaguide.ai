import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';

void main() {
  group('PGPressable', () {
    testWidgets('scales child below 1.0 on press-in', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PGPressable(
                onTap: () {},
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );

      // Start a gesture but don't release yet — scale should drop below 1.0.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PGPressable)),
      );
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));

      final scaleWidget = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale).first,
      );
      expect(scaleWidget.scale, lessThan(1.0));
      expect(scaleWidget.scale, greaterThanOrEqualTo(0.96));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('returns to scale 1.0 after release', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PGPressable(
                onTap: () {},
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(PGPressable));
      await tester.pumpAndSettle();

      final scaleWidget = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale).first,
      );
      expect(scaleWidget.scale, 1.0);
    });

    testWidgets('fires onTap once per tap', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PGPressable(
                onTap: () => taps++,
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(PGPressable));
      await tester.pumpAndSettle();
      expect(taps, 1);

      await tester.tap(find.byType(PGPressable));
      await tester.pumpAndSettle();
      expect(taps, 2);
    });

    testWidgets('does not animate scale when onTap is null (non-interactive)', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: PGPressable(child: SizedBox(width: 100, height: 100)),
            ),
          ),
        ),
      );

      // Try to press — without onTap, the gesture detector ignores tap-down.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PGPressable)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final scaleWidget = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale).first,
      );
      expect(scaleWidget.scale, 1.0, reason: 'no onTap → no press feedback');

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('skips scale animation under reduce-motion', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Center(
                child: PGPressable(
                  onTap: () {},
                  child: const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PGPressable)),
      );
      await tester.pump(const Duration(milliseconds: 80));

      final scaleWidget = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale).first,
      );
      expect(scaleWidget.scale, 1.0, reason: 'reduce-motion → no scale');

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('focus ring is invisible by default (opacity 0)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PGPressable(
                onTap: () {},
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );

      // The focus ring lives inside the AnimatedOpacity inside PGPressable.
      // Without keyboard focus, opacity should be 0.
      final fade = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(PGPressable),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(fade.opacity, 0.0);
    });

    testWidgets('Enter / Space activation fires onTap when focused', (
      tester,
    ) async {
      int taps = 0;
      final focusNode = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Focus(
                focusNode: focusNode,
                child: PGPressable(
                  onTap: () => taps++,
                  child: const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        ),
      );

      // Move focus into the PGPressable's FocusableActionDetector.
      focusNode.requestFocus();
      await tester.pumpAndSettle();
      // The detector grabs focus on next-traversable; the Focus parent
      // node we hold is just the harness anchor.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(taps, 1, reason: 'Enter on focused PGPressable should activate');

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(taps, 2, reason: 'Space on focused PGPressable should activate');

      focusNode.dispose();
    });

    testWidgets('long-press fires onLongPress without firing onTap', (
      tester,
    ) async {
      int taps = 0;
      int longPresses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PGPressable(
                onTap: () => taps++,
                onLongPress: () => longPresses++,
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );

      await tester.longPress(find.byType(PGPressable));
      await tester.pumpAndSettle();

      expect(longPresses, 1);
      expect(taps, 0);
    });
  });
}
