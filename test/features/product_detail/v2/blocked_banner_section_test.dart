// Simulator walkthrough 2026-10-01 (Nature's Way Organic Hemp, dsld 213005):
// with the detail blob unavailable the banner said only "Contains a banned,
// recalled, or otherwise prohibited substance" — no ingredient, no type,
// although the offline catalog row names both. With the blob loaded, the
// ingredient row was hidden whenever a one-liner existed, even one that
// never names the ingredient.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/blocked_banner_section.dart';

const _hempWarning = <String, dynamic>{
  'type': 'banned_substance',
  'severity': 'critical',
  'title': 'Banned substance: organic Hemp Oil extract',
};

const _hempDetail = <String, dynamic>{
  'substance_name': 'organic Hemp Oil extract',
  'safety_warning_one_liner':
      'Not lawful as a US dietary supplement. Talk to your doctor.',
  'safety_warning':
      'Under US law, CBD cannot lawfully be sold as a dietary supplement '
      'because it was first investigated as a drug.',
  'ban_context': 'substance',
};

Future<void> _pump(
  WidgetTester tester, {
  List<Map<String, dynamic>> topWarnings = const [_hempWarning],
  Map<String, dynamic>? detail,
  bool detailsUnavailable = false,
  String blockingReason = 'banned_ingredient',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Builder(
            builder: (context) => buildBlockedBannerSection(
              context: context,
              verdict: 'blocked',
              blockingReason: blockingReason,
              topWarnings: topWarnings,
              bannedSubstanceDetail: detail,
              detailsUnavailable: detailsUnavailable,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('offline: names the type and ingredient from the catalog row', (
    tester,
  ) async {
    await _pump(tester, detailsUnavailable: true);

    expect(
      find.text('Banned substance: organic Hemp Oil extract'),
      findsOneWidget,
    );
    expect(find.textContaining('otherwise prohibited'), findsNothing);
    expect(
      find.text('The full explanation and sources load when you\'re online.'),
      findsOneWidget,
    );
  });

  testWidgets('online: pipeline one-liner verbatim plus the ingredient', (
    tester,
  ) async {
    await _pump(tester, detail: _hempDetail);

    expect(
      find.text('Not lawful as a US dietary supplement. Talk to your doctor.'),
      findsOneWidget,
    );
    expect(find.text('Ingredient: organic Hemp Oil extract'), findsOneWidget);
    expect(find.textContaining('first investigated as a drug'), findsOneWidget);
    expect(find.textContaining('load when you\'re online'), findsNothing);
  });

  testWidgets('a one-liner that names the ingredient needs no extra row', (
    tester,
  ) async {
    await _pump(
      tester,
      detail: {
        ..._hempDetail,
        'safety_warning_one_liner':
            'Organic Hemp Oil Extract is not lawful as a supplement.',
      },
    );

    expect(find.text('Ingredient: organic Hemp Oil extract'), findsNothing);
  });

  testWidgets('no warning title falls back to the reason, never a raw code', (
    tester,
  ) async {
    await _pump(
      tester,
      topWarnings: const [],
      blockingReason: 'NON_ROUTINE_CHELATOR',
    );

    expect(find.textContaining('NON ROUTINE'), findsNothing);
    expect(find.text('Reason: Non routine chelator'), findsOneWidget);
  });
}
