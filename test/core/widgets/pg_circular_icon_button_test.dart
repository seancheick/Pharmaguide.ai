import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/widgets/pg_circular_icon_button.dart';

void main() {
  group('PGCircularIconButton', () {
    testWidgets('renders icon centered in a circle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PGCircularIconButton(
              icon: Icons.ios_share_rounded,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
    });

    testWidgets('fires onTap once per tap', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PGCircularIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => taps++,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(PGCircularIconButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('respects custom tone color', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PGCircularIconButton(
              icon: Icons.delete_outline_rounded,
              tone: Colors.red,
              onTap: () {},
            ),
          ),
        ),
      );
      final iconWidget = tester.widget<Icon>(find.byType(Icon));
      expect(iconWidget.color, Colors.red);
    });

    testWidgets('respects custom size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PGCircularIconButton(
              icon: Icons.close_rounded,
              size: 44,
              onTap: () {},
            ),
          ),
        ),
      );
      // Find the inner Container that PGCircularIconButton renders for the
      // circular surface; assert its width and height match `size`.
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(PGCircularIconButton),
          matching: find.byType(Container),
        ),
      );
      // The Container uses width/height directly, not constraints. Verify
      // by asserting the rendered RenderBox size is 44x44.
      final renderBox = tester.renderObject<RenderBox>(
        find.descendant(
          of: find.byType(PGCircularIconButton),
          matching: find.byType(Container),
        ),
      );
      expect(renderBox.size.width, 44);
      expect(renderBox.size.height, 44);
      // Also confirm the Container exists (silences unused_local_variable).
      expect(container, isNotNull);
    });
  });
}
