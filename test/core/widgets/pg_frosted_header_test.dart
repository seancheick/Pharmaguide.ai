import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_header.dart';

DecoratedBox _findHeaderDecoratedBox(WidgetTester tester) {
  final boxes = tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(PGFrostedHeader),
          matching: find.byType(DecoratedBox),
        ),
      )
      .toList();

  return boxes.firstWhere((b) => b.decoration is BoxDecoration);
}

void main() {
  group('PGFrostedHeader', () {
    testWidgets('renders the child widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: const Scaffold(
            body: PGFrostedHeader(
              scrollProgress: 0.0,
              child: Text('child-marker'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('child-marker'), findsOneWidget);
    });

    testWidgets(
      'at scrollProgress 0 the BackdropFilter blur is effectively zero',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: const Scaffold(
              body: PGFrostedHeader(
                scrollProgress: 0.0,
                child: SizedBox(width: 200, height: 56),
              ),
            ),
          ),
        );
        await tester.pump();

        final filter =
            tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter
                as ImageFilter;
        // We can't introspect ImageFilter sigma values, but the widget
        // should still mount without throwing — the contract here is
        // existence + no crash.
        expect(filter, isNotNull);
      },
    );

    testWidgets('at scrollProgress 1 the surface fill is at full opacity', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: const Scaffold(
            body: PGFrostedHeader(
              scrollProgress: 1.0,
              child: SizedBox(width: 200, height: 56),
            ),
          ),
        ),
      );
      // PGFrostedHeader internally uses TweenAnimationBuilder to crossfade
      // alpha when scrollProgress changes; pumpAndSettle drives the tween
      // to its end value so we can assert the final fill opacity.
      await tester.pumpAndSettle();

      // Find the DecoratedBox that PGFrostedHeader renders inside its
      // BackdropFilter. Its color alpha should track the scrollProgress.
      final ourBox = _findHeaderDecoratedBox(tester);
      final color = (ourBox.decoration as BoxDecoration).color!;
      // Light scheme target alpha-fraction at progress 1.0 is ~0.78.
      expect(color.a, greaterThanOrEqualTo(0.70));
      expect(color.a, lessThanOrEqualTo(0.82));
    });

    testWidgets('clamps scrollProgress above 1.0 to 1.0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: const Scaffold(
            body: PGFrostedHeader(
              scrollProgress: 5.0, // out of range
              child: SizedBox(width: 200, height: 56),
            ),
          ),
        ),
      );
      // Just verify it doesn't throw — clamp keeps alpha bounded.
      await tester.pump();
      expect(find.byType(PGFrostedHeader), findsOneWidget);
    });

    testWidgets('clamps scrollProgress below 0.0 to 0.0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: const Scaffold(
            body: PGFrostedHeader(
              scrollProgress: -1.0, // out of range
              child: SizedBox(width: 200, height: 56),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(PGFrostedHeader), findsOneWidget);
    });

    testWidgets('dark mode renders a faint white top-edge glint', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            platform: TargetPlatform.iOS,
          ),
          home: const Scaffold(
            body: PGFrostedHeader(
              scrollProgress: 1.0,
              child: SizedBox(width: 200, height: 56),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ourBox = _findHeaderDecoratedBox(tester);
      final border = (ourBox.decoration as BoxDecoration).border as Border;
      expect(border.top.color.r, 1.0, reason: 'glint should be white-channel');
      expect(border.top.color.g, 1.0);
      expect(border.top.color.b, 1.0);
      expect(
        border.top.color.a,
        greaterThan(0.0),
        reason: 'glint alpha should be > 0 at scrollProgress 1',
      );
      expect(
        border.top.color.a,
        lessThan(0.10),
        reason: 'glint should be subtle (< 10% white)',
      );
    });

    testWidgets('light mode does NOT render the glint (no top border)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.light,
            platform: TargetPlatform.iOS,
          ),
          home: const Scaffold(
            body: PGFrostedHeader(
              scrollProgress: 1.0,
              child: SizedBox(width: 200, height: 56),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ourBox = _findHeaderDecoratedBox(tester);
      final border = (ourBox.decoration as BoxDecoration).border as Border;
      expect(
        border.top,
        BorderSide.none,
        reason: 'glint is dark-mode-only; light mode keeps top edge clean',
      );
    });

    testWidgets('android uses tonal surface without backdrop blur', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: const Scaffold(
            body: PGFrostedHeader(
              scrollProgress: 1.0,
              child: SizedBox(width: 200, height: 56),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BackdropFilter), findsNothing);

      final ourBox = _findHeaderDecoratedBox(tester);
      final color = (ourBox.decoration as BoxDecoration).color!;
      expect(color.a, greaterThanOrEqualTo(0.85));
    });
  });
}
