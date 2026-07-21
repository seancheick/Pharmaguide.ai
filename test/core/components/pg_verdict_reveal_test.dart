// Regression: PGVerdictReveal must invoke onDismiss at most once per reveal.
//
// The scan→verdict flash exposes THREE dismissal triggers — the ~900ms
// auto-dismiss timer plus two tap paths (Semantics.onTap + GestureDetector
// .onTap). Before the one-shot `_dismissed` guard, a tap overlapping the
// timer fired the caller's completion twice; on the scanner that reset
// `_hasScanned` while the first navigation's `context.push` was still
// pending, re-arming detection mid-navigation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_verdict_reveal.dart';

Future<void> _pumpReveal(
  WidgetTester tester,
  VoidCallback onDismiss,
) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PGVerdictReveal(
          kind: PGVerdictKind.success,
          playHaptic: false, // keep the haptic channel out of the test
          onDismiss: onDismiss,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('tap then the auto-dismiss timer fires onDismiss only once', (
    tester,
  ) async {
    var dismissals = 0;
    await _pumpReveal(tester, () => dismissals++);
    await tester.pump(const Duration(milliseconds: 100)); // entrance frame

    // User taps to dismiss.
    await tester.tap(find.byType(PGVerdictReveal));
    await tester.pump();
    expect(dismissals, 1);

    // The 900ms auto-dismiss timer still fires — the one-shot guard must
    // swallow it rather than invoke onDismiss a second time.
    await tester.pump(const Duration(milliseconds: 1000));
    expect(dismissals, 1);
  });

  testWidgets('two rapid taps fire onDismiss only once', (tester) async {
    var dismissals = 0;
    await _pumpReveal(tester, () => dismissals++);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byType(PGVerdictReveal));
    await tester.tap(find.byType(PGVerdictReveal));
    await tester.pump();
    expect(dismissals, 1);

    // Drain the pending auto-dismiss timer (also guarded).
    await tester.pump(const Duration(milliseconds: 1000));
    expect(dismissals, 1);
  });

  testWidgets('auto-dismiss timer alone fires onDismiss exactly once', (
    tester,
  ) async {
    var dismissals = 0;
    await _pumpReveal(tester, () => dismissals++);

    await tester.pump(const Duration(milliseconds: 1000)); // past the 900ms
    expect(dismissals, 1);
  });
}
