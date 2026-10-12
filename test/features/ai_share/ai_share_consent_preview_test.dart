// S4 consent preview (ADR-009): destination, categories, duration, the three
// data locations and the revocation path are all on screen before Share.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_settings_tile.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/features/ai_share/ai_share_consent_screen.dart';
import 'package:pharmaguide/features/ai_share/ai_share_providers.dart';
import 'package:pharmaguide/services/sharing/ai_share_prefs_store.dart';
import 'package:pharmaguide/services/sharing/clinician_report_document_provider.dart';

import 'ai_share_test_fixtures.dart';

void main() {
  late FakeAiShareBackend backend;

  setUp(() => backend = FakeAiShareBackend());

  Widget app() => ProviderScope(
    overrides: [
      clinicianReportDataProvider.overrideWith((ref) async => aiShareFixture()),
      aiShareSnapshotClientProvider.overrideWithValue(backend.client()),
      aiSharePrefsStoreProvider.overrideWithValue(
        AiSharePrefsStore(MemoryPreferencesStore()),
      ),
    ],
    child: MaterialApp(
      theme: V2Theme.light,
      home: AiShareConsentScreen(connection: aiConnectionFixture()),
    ),
  );

  String card(WidgetTester tester) {
    final texts = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('ai_share_consent_card')),
        matching: find.byType(Text),
      ),
    );
    return texts.map((t) => t.data ?? '').join('\n');
  }

  testWidgets('names destination, categories, data locations and how to stop', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final text = card(tester);
    expect(text, contains('claude-ai'));
    expect(text, contains('Included: supplements, PharmaGuide findings.'));
    expect(text, contains('Not included: medications, health profile.'));
    expect(text, contains('PharmaGuide stores this snapshot encrypted'));
    expect(text, contains('not end-to-end encrypted'));
    expect(text, contains('may keep it in your chat history'));
    expect(text, contains('cannot erase what the assistant already kept'));
    expect(text, contains('pharmaguide.io/account/connections'));
    expect(text, isNot(contains('safe')));
    expect(find.text('24 hours'), findsOneWidget);
  });

  testWidgets('switching a category on updates the card before sharing', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final profileSwitch = find.descendant(
      of: find.widgetWithText(PGSettingsTile, 'Health profile'),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(profileSwitch);
    await tester.tap(profileSwitch);
    await tester.pumpAndSettle();

    expect(card(tester), contains('health profile'));
    expect(card(tester), contains('Not included: medications.'));
    expect(backend.calls, isEmpty, reason: 'nothing leaves before Share');
  });

  testWidgets('the chosen duration is the one uploaded', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('30 days'));
    await tester.pumpAndSettle();
    final share = find.byKey(const Key('ai_share_submit'));
    await tester.ensureVisible(share);
    await tester.tap(share);
    await tester.pumpAndSettle();

    expect(backend.uploads.single.body['ttl_hours'], 720);
  });

  testWidgets('a guest share fails visibly and nothing is sent', (
    tester,
  ) async {
    backend.signedIn = false;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final share = find.byKey(const Key('ai_share_submit'));
    await tester.ensureVisible(share);
    await tester.tap(share);
    await tester.pumpAndSettle();

    expect(find.text('Sign in to share with an assistant.'), findsOneWidget);
    expect(backend.calls, isEmpty);
    expect(find.byType(AiShareConsentScreen), findsOneWidget);
  });
}
