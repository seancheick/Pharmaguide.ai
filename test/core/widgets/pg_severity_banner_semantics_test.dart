import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';

void main() {
  // Severity must not rely on colour or an unlabeled icon alone: a screen
  // reader announces the tone before the title (roadmap 1.2, accessibility).
  testWidgets('every banner tone is announced to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    const expected = {
      PGBannerTone.info: 'Information',
      PGBannerTone.caution: 'Caution',
      PGBannerTone.danger: 'Safety warning',
      PGBannerTone.success: 'Confirmed',
      PGBannerTone.neutral: 'Not enough information',
    };
    for (final MapEntry(key: tone, value: label) in expected.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PGSeverityBanner(tone: tone, title: 'Title', body: 'Body'),
          ),
        ),
      );
      // The banner reads as one unit: tone first, then title and body.
      expect(
        find.bySemanticsLabel(RegExp('^$label\nTitle\nBody\$')),
        findsOneWidget,
        reason: '$tone',
      );
    }
    handle.dispose();
  });
}
