// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.1, T1.
//
// Smoke-level widget tests for the fullscreen product-image viewer.
// We deliberately don't try to render the network image bytes — that
// path runs through CachedNetworkImage which needs a network or a
// fake provider in tests. Here we verify the structural invariants:
// the InteractiveViewer is mounted (so pinch-zoom works at runtime),
// the close button is present, and tapping it dismisses the route.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/product_image_viewer.dart';

void main() {
  group('ProductImageViewer', () {
    testWidgets('renders InteractiveViewer + close button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ProductImageViewer(
            imageUrl: 'https://example.com/img.png',
            heroTag: 'product-test',
            productName: 'Test Product',
          ),
        ),
      );

      // Pinch-zoom is the headline feature — InteractiveViewer must be
      // in the tree, not just any Stack/Center wrapper.
      expect(find.byType(InteractiveViewer), findsOneWidget);
      // Close affordance — required for one-handed dismissal on top
      // of the swipe-down route gesture.
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('close button pops the route', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => ProductImageViewer.show(
                    ctx,
                    imageUrl: 'https://example.com/img.png',
                    heroTag: 'product-test',
                    productName: 'Test Product',
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open the viewer.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductImageViewer), findsOneWidget);

      // Tap close → viewer should be popped off the stack.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(ProductImageViewer), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('show() pushes a fullscreen route on top', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ProductImageViewer.show(
                  ctx,
                  imageUrl: 'https://example.com/img.png',
                  heroTag: 'product-test',
                  productName: 'Test Product',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Viewer is mounted; underlying button is no longer hit-testable
      // because the viewer's Scaffold sits on top of the stack.
      expect(find.byType(ProductImageViewer), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });
  });
}
