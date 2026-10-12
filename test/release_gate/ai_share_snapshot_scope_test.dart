// Release gate S4 (ADR-009): the consented snapshot payload IS the AI brief
// the user previewed, and an excluded category (medications, health profile)
// never reaches the payload, including findings derived from it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_settings_tile.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/features/ai_share/ai_share_consent_screen.dart';
import 'package:pharmaguide/features/ai_share/ai_share_providers.dart';
import 'package:pharmaguide/services/sharing/ai_brief_builder.dart';
import 'package:pharmaguide/services/sharing/ai_share_prefs_store.dart';
import 'package:pharmaguide/services/sharing/ai_share_scope.dart';
import 'package:pharmaguide/services/sharing/ai_share_snapshot_client.dart';
import 'package:pharmaguide/services/sharing/clinician_report_document_provider.dart';

import '../features/ai_share/ai_share_test_fixtures.dart';

Widget _consentApp(FakeAiShareBackend backend, AiSharePrefsStore prefs) {
  return ProviderScope(
    overrides: [
      clinicianReportDataProvider.overrideWith((ref) async => aiShareFixture()),
      aiShareSnapshotClientProvider.overrideWithValue(backend.client()),
      aiSharePrefsStoreProvider.overrideWithValue(prefs),
    ],
    child: MaterialApp(
      theme: V2Theme.light,
      home: AiShareConsentScreen(connection: aiConnectionFixture()),
    ),
  );
}

String _previewText(WidgetTester tester) => tester
    .widget<SelectableText>(find.byKey(const Key('ai_share_preview_text')))
    .data!;

Future<void> _tapShare(WidgetTester tester) async {
  final share = find.byKey(const Key('ai_share_submit'));
  await tester.ensureVisible(share);
  await tester.tap(share);
  await tester.pumpAndSettle();
}

void main() {
  group('consent screen uploads exactly the preview', () {
    testWidgets('default scope: payload equals preview; no medication or '
        'profile data, derived findings included', (tester) async {
      final backend = FakeAiShareBackend();
      final prefs = AiSharePrefsStore(MemoryPreferencesStore());
      await tester.pumpWidget(_consentApp(backend, prefs));
      await tester.pumpAndSettle();

      final preview = _previewText(tester);
      await _tapShare(tester);

      final body = backend.uploads.single.body;
      expect(body.keys.toSet(), {
        'connection_id',
        'scope',
        'stack_revision',
        'ttl_hours',
        'format',
        'payload',
      });
      expect(body['payload'], preview);
      expect(body['format'], 'pharmaguide-brief-markdown/v1');
      expect(body['connection_id'], aiConnectionFixture().connectionId);
      expect(body['ttl_hours'], 24);
      expect(body['stack_revision'], isA<String>());
      expect((body['stack_revision']! as String).isNotEmpty, isTrue);
      expect(body['scope'], AiShareScope.detailedReport.normalized.toJson());
      final payload = body['payload']! as String;
      expect(payload, contains('Iron Bisglycinate'));
      for (final sensitive in aiShareSensitiveStrings) {
        expect(payload, isNot(contains(sensitive)), reason: sensitive);
      }
      // The scope the user saw is remembered for an opt-in refresh.
      expect(
        (await prefs.read(aiConnectionFixture().connectionId))?.scope,
        AiShareScope.detailedReport.normalized,
      );
    });

    testWidgets('medications switched on: they and their findings are in '
        'both preview and payload; profile stays out', (tester) async {
      final backend = FakeAiShareBackend();
      final prefs = AiSharePrefsStore(MemoryPreferencesStore());
      await tester.pumpWidget(_consentApp(backend, prefs));
      await tester.pumpAndSettle();

      final medicationSwitch = find.descendant(
        of: find.widgetWithText(PGSettingsTile, 'Medications'),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(medicationSwitch);
      await tester.tap(medicationSwitch);
      await tester.pumpAndSettle();

      final preview = _previewText(tester);
      expect(preview, contains('Lisinopril'));
      await _tapShare(tester);

      final body = backend.uploads.single.body;
      expect(body['payload'], preview);
      expect(body['payload'], contains('Levothyroxine'));
      expect(body['payload'], isNot(contains('Pregnan')));
      expect((body['scope']! as Map)['medication_names'], isTrue);
      expect((body['scope']! as Map)['profile'], isFalse);
    });
  });

  test('every scope combination: an excluded category never reaches the '
      'payload, including findings derived from it', () {
    const builder = AiBriefBuilder();
    final data = aiShareFixture();
    for (var bits = 0; bits < 1 << 7; bits++) {
      bool on(int i) => bits & (1 << i) != 0;
      final scope = AiShareScope(
        supplementNames: on(0),
        supplementAmounts: on(1),
        supplementSchedule: on(2),
        medicationNames: on(3),
        medicationSchedule: on(4),
        profile: on(5),
        findings: on(6),
      );
      final payload = builder.build(data, scope);
      if (!scope.medicationNames) {
        for (final s in ['Lisinopril', '10 mg', 'Levothyroxine', 'Metformin']) {
          expect(payload, isNot(contains(s)), reason: '$s with $bits');
        }
      }
      if (!scope.profile) {
        for (final s in ['Pregnan', 'Vitamin A']) {
          expect(payload, isNot(contains(s)), reason: '$s with $bits');
        }
      }
    }
  });

  test('stack_revision ignores medication rows unless medications are '
      'shared, so an unshared change is not even signalled', () {
    final base = [aiShareEntry('s-1', 'Iron Bisglycinate', 'supplement')];
    final withMed = [...base, aiShareEntry('m-1', 'Lisinopril', 'medication')];
    const medsOff = AiShareScope.detailedReport;
    const medsOn = AiShareScope(medicationNames: true);

    expect(
      AiShareSnapshotClient.stackRevisionForScope(withMed, medsOff),
      AiShareSnapshotClient.stackRevisionForScope(base, medsOff),
    );
    expect(
      AiShareSnapshotClient.stackRevisionForScope(withMed, medsOn),
      isNot(AiShareSnapshotClient.stackRevisionForScope(base, medsOn)),
    );
  });

  group('AiShareSnapshotClient', () {
    test('a guest cannot upload: typed failure and nothing is sent', () async {
      final backend = FakeAiShareBackend(signedIn: false);
      final client = backend.client();
      await expectLater(
        client.upload(
          connectionId: 'c-1',
          scope: AiShareScope.detailedReport,
          stackRevision: 'r1',
          ttlHours: 24,
          payload: 'brief',
        ),
        throwsA(isA<AiShareNotSignedIn>()),
      );
      await expectLater(
        client.delete('c-1'),
        throwsA(isA<AiShareNotSignedIn>()),
      );
      await expectLater(client.deleteAll(), throwsA(isA<AiShareNotSignedIn>()));
      expect(backend.calls, isEmpty);
    });

    test('ttl_hours is clamped to 24..720', () async {
      final backend = FakeAiShareBackend();
      final client = backend.client();
      for (final ttl in [0, 1, 24, 168, 720, 721, 100000]) {
        await client.upload(
          connectionId: 'c-1',
          scope: AiShareScope.detailedReport,
          stackRevision: 'r1',
          ttlHours: ttl,
          payload: 'brief',
        );
      }
      expect(backend.uploads.map((c) => c.body['ttl_hours']).toList(), [
        24,
        24,
        24,
        168,
        720,
        720,
        720,
      ]);
    });

    test(
      'an empty scope or empty payload is refused before any request',
      () async {
        final backend = FakeAiShareBackend();
        final client = backend.client();
        await expectLater(
          client.upload(
            connectionId: 'c-1',
            scope: const AiShareScope(supplementNames: false, findings: false),
            stackRevision: 'r1',
            ttlHours: 24,
            payload: 'brief',
          ),
          throwsArgumentError,
        );
        await expectLater(
          client.upload(
            connectionId: 'c-1',
            scope: AiShareScope.detailedReport,
            stackRevision: 'r1',
            ttlHours: 24,
            payload: '  ',
          ),
          throwsArgumentError,
        );
        expect(backend.calls, isEmpty);
      },
    );

    test('scope JSON is booleans only and parses fail-closed', () {
      final json = const AiShareScope(medicationNames: true).toJson();
      expect(json, isA<Map<String, bool>>());
      expect(
        AiShareScope.fromJson(json),
        const AiShareScope(medicationNames: true),
      );
      // Missing or malformed fields never switch a category on.
      final parsed = AiShareScope.fromJson({'medication_names': 'yes'});
      expect(parsed.medicationNames, isFalse);
      expect(parsed.profile, isFalse);
      expect(parsed.supplementNames, isFalse);
    });

    test(
      'delete targets one connection; deleteAll sends {all: true}',
      () async {
        final backend = FakeAiShareBackend();
        final client = backend.client();
        await client.delete('c-1');
        await client.deleteAll();
        expect(backend.deletes.map((c) => c.body).toList(), [
          {'connection_id': 'c-1'},
          {'all': true},
        ]);
      },
    );
  });
}
