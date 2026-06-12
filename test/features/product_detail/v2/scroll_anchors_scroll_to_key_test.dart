// Prime-and-retry contract for ProductDetailScrollAnchors.scrollToKey.
//
// Lazy SliverList children far below the fold have no BuildContext —
// `key.currentContext == null` — so a plain ensureVisible would silently
// no-op every pillar deep-link to a far section. scrollToKey must prime
// the viewport toward the target fraction, wait a frame for the lazy
// child to build, then land the keyed ensureVisible.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/scroll_anchors.dart';

void main() {
  testWidgets('scrollToKey reaches a lazily-built section far below the '
      'initial viewport', (tester) async {
    final anchors = ProductDetailScrollAnchors();
    final targetKey = GlobalKey();
    const targetIndex = 90;

    // Small viewport so item 90 (of 100 × 100px) is far offscreen and
    // NOT built by the lazy delegate at first frame.
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: anchors.scrollController,
            slivers: [
              SliverList.builder(
                itemCount: 100,
                itemBuilder: (context, i) => i == targetIndex
                    ? SizedBox(
                        key: targetKey,
                        height: 100,
                        child: const Text('TARGET SECTION'),
                      )
                    : const SizedBox(height: 100),
              ),
            ],
          ),
        ),
      ),
    );

    // Precondition: the target is lazy — not built, context null. This is
    // exactly the state where a plain ensureVisible would dead-end.
    expect(targetKey.currentContext, isNull);
    expect(find.text('TARGET SECTION'), findsNothing);

    anchors.scrollToKey(targetKey, isMounted: () => true, primeFraction: 0.9);

    // Drive the post-frame retry loop + the 400ms ensureVisible animation.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(targetKey.currentContext, isNotNull);
    expect(find.text('TARGET SECTION'), findsOneWidget);
    // Landed: target's top is inside the viewport (alignment 0.1).
    final box = targetKey.currentContext!.findRenderObject()! as RenderBox;
    final top = box.localToGlobal(Offset.zero).dy;
    expect(top, greaterThanOrEqualTo(0));
    expect(top, lessThan(600));

    anchors.dispose();
  });

  testWidgets('scrollToKey gives up cleanly when the target never renders', (
    tester,
  ) async {
    final anchors = ProductDetailScrollAnchors();
    final neverKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: anchors.scrollController,
            slivers: const [SliverToBoxAdapter(child: SizedBox(height: 100))],
          ),
        ),
      ),
    );

    anchors.scrollToKey(neverKey, isMounted: () => true);
    // Pump past the capped retry budget — must terminate without throwing
    // and without leaving pending frame callbacks alive forever.
    for (var i = 0; i < 130; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(neverKey.currentContext, isNull);

    anchors.dispose();
  });
}
