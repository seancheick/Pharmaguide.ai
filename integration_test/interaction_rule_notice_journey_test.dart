// The fictional reconnect journey on a simulator, with its screenshots as
// evidence. Serves the pipeline's fake feed from memory and uses in-memory
// databases, so nothing is published and no account data is read:
//
// VERIFY_EVIDENCE_DIR=<new folder> flutter drive \
//   --driver test_driver/native_catalog_driver.dart \
//   --target integration_test/interaction_rule_notice_journey_test.dart \
//   --dart-define=INTERACTION_FEED_BASE64="$(base64 < test/fixtures/safety_alerts/interaction_rule_feed.json)" \
//   --dart-define=INTERACTION_BASE_FEED_BASE64="$(base64 < test/fixtures/safety_alerts/interaction_rule_base_feed.json)" \
//   -d <device>

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/features/safety_alerts/interaction_rule_journey.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  var surfaceConverted = false;

  Future<void> journey(
    WidgetTester tester, {
    required String prefix,
    required Key notice,
    bool pregnant = false,
  }) async {
    final feedBytes = base64.decode(
      const String.fromEnvironment('INTERACTION_FEED_BASE64'),
    );
    final baseBytes = base64.decode(
      const String.fromEnvironment('INTERACTION_BASE_FEED_BASE64'),
    );
    expect(
      'sha256:${sha256.convert(feedBytes)}',
      'sha256:e0f20b54bcdf8aa77eef02c2c8420644adb390510546f8121e8e3359f3c1eb8f',
    );
    expect(
      'sha256:${sha256.convert(baseBytes)}',
      'sha256:7564e689beaa6fe47a794d3121ac715c211a487476098e3c80c6b0bde2a940c5',
    );

    if (!surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
    }
    await runInteractionRuleJourney(
      tester,
      baseBytes: baseBytes,
      feedBytes: feedBytes,
      pregnant: pregnant,
      settle: () async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
      },
      onStep: (step) async {
        if (step == 'after_reconnect') {
          await tester.ensureVisible(find.byKey(notice));
          await tester.pump(const Duration(milliseconds: 500));
        }
        await binding.takeScreenshot('$prefix$step');
        if (step == 'after_reconnect') {
          // The rest of the notice: reason, evidence grade and source.
          await tester.ensureVisible(find.text('View source'));
          await tester.pump(const Duration(milliseconds: 500));
          await binding.takeScreenshot('$prefix${step}_end');
        }
      },
    );
  }

  testWidgets('a new contraindication appears when the connection returns', (
    tester,
  ) async {
    await journey(tester, prefix: '', notice: noticeKey);
  });

  testWidgets('a pregnancy rule reaches someone taking no medication', (
    tester,
  ) async {
    await journey(
      tester,
      prefix: 'pregnancy_',
      notice: pregnancyNoticeKey,
      pregnant: true,
    );
  });
}
