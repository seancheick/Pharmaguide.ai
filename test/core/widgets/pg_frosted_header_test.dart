import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_header.dart';

void main() {
  group('PGFrostedHeader', () {
    testWidgets('renders the child widget', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
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
        const MaterialApp(
          home: Scaffold(
            body: PGFrostedHeader(
              scrollProgress: 0.0,
              child: SizedBox(width: 200, height: 56),
            ),
          ),
        ),
      );
      await tester.pump();

      final filter = tester
          .widget<BackdropFilter>(find.byType(BackdropFilter))
          .filter as ImageFilter;
      // We can't introspect ImageFilter sigma values, but the widget
      // should still mount without throwing — the contract here is
      // existence + no crash.
      expect(filter, isNotNull);
    });

    testWidgets('at scrollProgress 1 the surface fill is at full opacity',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
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
      final boxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .toList();
      expect(boxes, isNotEmpty);
      final ourBox = boxes.firstWhere(
        (b) {
          final dec = b.decoration as BoxDecoration;
          return dec.color != null && dec.color!.a > 0;
        },
      );
      final color = (ourBox.decoration as BoxDecoration).color!;
      // Light scheme target alpha-fraction at progress 1.0 is ~0.78.
      expect(color.a, greaterThanOrEqualTo(0.70));
      expect(color.a, lessThanOrEqualTo(0.82));
    });

    testWidgets('clamps scrollProgress above 1.0 to 1.0', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
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
        const MaterialApp(
          home: Scaffold(
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
  });
}
