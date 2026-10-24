// S4 consent preview (ADR-009): destination, categories, duration, the three
// data locations and the revocation path are all on screen before Share.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pharmaguide/services/sharing/ai_share_scope.dart';
import 'package:pharmaguide/services/sharing/report_text.dart';
import 'package:pharmaguide/services/sharing/ai_share_snapshot_client.dart';
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

  Widget app({AiShareSnapshotClient? client, AiSharePrefsStore? preferences}) =>
      ProviderScope(
        overrides: [
          clinicianReportDataProvider.overrideWith(
            (ref) async => aiShareFixture(),
          ),
          aiShareSnapshotClientProvider.overrideWithValue(
            client ?? backend.client(),
          ),
          aiSharePrefsStoreProvider.overrideWithValue(
            preferences ?? AiSharePrefsStore(MemoryPreferencesStore()),
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

  for (final stop in ['forget', 'clear', 'disable']) {
    testWidgets('completed upload cannot undo $stop during sharing', (
      tester,
    ) async {
      final prefs = AiSharePrefsStore(MemoryPreferencesStore());
      final id = aiConnectionFixture().connectionId;
      await prefs.recordShare(id, AiShareScope.detailedReport, 24);
      await prefs.setKeepUpdated(id, true);
      final response = Completer<AiShareInvokeResponse>();
      final client = AiShareSnapshotClient(
        isSignedIn: () => true,
        invoke: (_, _) => response.future,
      );
      await tester.pumpWidget(app(client: client, preferences: prefs));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai_share_submit')));
      await tester.pumpAndSettle();
      switch (stop) {
        case 'forget':
          await prefs.forget(id);
        case 'clear':
          await prefs.clear();
        case 'disable':
          await prefs.setKeepUpdated(id, false);
      }
      response.complete(
        const AiShareInvokeResponse(
          status: 201,
          data: {'snapshot_id': 's1', 'expires_at': '2026-10-14T00:00:00Z'},
        ),
      );
      await tester.pumpAndSettle();
      final saved = await prefs.read(id);
      if (stop == 'disable') {
        expect(saved?.keepUpdated, false);
      } else {
        expect(saved, isNull);
      }
    });
  }

  testWidgets('disabled snapshot endpoint gives honest availability guidance', (
    tester,
  ) async {
    backend.failWith = const AiShareSnapshotRequestFailed(503);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai_share_submit')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Sharing is currently unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('Shared. Available'), findsNothing);
  });

  testWidgets('invalid snapshot request does not blame the device clock', (
    tester,
  ) async {
    backend.failWith = const AiShareSnapshotRequestFailed(400);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai_share_submit')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('The share request was not accepted'),
      findsOneWidget,
    );
  });

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

  testWidgets('maximum duration explains the actual connection expiry cap', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final connection = tester
        .widget<AiShareConsentScreen>(find.byType(AiShareConsentScreen))
        .connection;
    expect(find.text('Additional details available for'), findsOneWidget);
    expect(find.text('Available to the assistant for'), findsNothing);
    final expiry = formatReportDate(connection.expiresAt!.toLocal());
    final clarification = find.text(
      'Access to this additional copy ends after this time or when your assistant connection expires '
      'on $expiry, whichever comes first.',
    );
    expect(clarification, findsOneWidget);
    await tester.ensureVisible(find.text('30 days'));
    await tester.tap(find.text('30 days'));
    await tester.pumpAndSettle();
    expect(clarification, findsOneWidget);
    expect(
      backend.calls,
      isEmpty,
      reason: 'expiry is explained before sharing',
    );
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
