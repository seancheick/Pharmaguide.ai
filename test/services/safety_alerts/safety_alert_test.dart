import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';

void main() {
  final record = <String, Object?>{
    'alert_id': 'SA_2026_0001',
    'revision': 2,
    'event_type': 'ingredient_ban',
    'source_url': 'https://www.fda.gov/example',
    'headline': 'Regulatory safety update',
    'body': 'This product contains a prohibited substance.',
    'action': 'Stop taking this product and contact your clinician.',
    'consumer_disposition': 'block',
    'resolved_dsld_ids': ['306237'],
    'scope': {
      'ingredient_canonical_ids': ['tianeptine'],
      'dsld_ids': <String>[],
    },
  };

  test(
    'matches frozen product identity or exact canonical ingredient identity',
    () {
      final alert = SafetyAlert.fromJson(record);

      expect(
        alert.appliesTo(dsldId: '306237', ingredientCanonicalIds: const []),
        isTrue,
      );
      expect(
        alert.appliesTo(
          dsldId: '999999',
          ingredientCanonicalIds: const ['tianeptine'],
        ),
        isTrue,
      );
      expect(
        alert.appliesTo(
          dsldId: '999999',
          ingredientCanonicalIds: const ['tianeptine sodium'],
        ),
        isFalse,
      );
    },
  );

  test(
    'rejects an unapproved disposition and malformed operational record',
    () {
      expect(
        () => SafetyAlert.fromJson({
          ...record,
          'consumer_disposition': 'good_to_know',
        }),
        throwsFormatException,
      );
      expect(
        () => SafetyAlert.fromJson({...record, 'revision': 0}),
        throwsFormatException,
      );
    },
  );

  group('a revision this build cannot read', () {
    late String? feed;
    late _MemoryPreferences preferences;
    late SafetyAlertRepository repository;

    void publish(List<Map<String, Object?>> alerts) {
      feed = jsonEncode({'alerts': alerts});
    }

    setUp(() {
      feed = null;
      preferences = _MemoryPreferences();
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        httpClient: MockClient((request) async {
          final body = feed;
          if (body == null) throw http.ClientException('offline');
          if (request.url.path.contains('/storage/')) {
            return http.Response(body, 200, request: request);
          }
          return http.Response(
            jsonEncode({
              'feed_path': 'safety/feed.json',
              'checksum': 'sha256:${sha256.convert(utf8.encode(body))}',
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      repository = SafetyAlertRepository(
        client: client,
        preferences: preferences,
      );
    });

    final known = record['revision'] as int;
    final unreadable = {
      ...record,
      'revision': known + 1,
      'event_type': 'future_kind',
    };

    for (final currentRows in [
      [
        {...record, 'revision': known + 1},
      ],
      <Map<String, Object?>>[],
    ]) {
      test(
        'cached carry respects current feed with ${currentRows.length} alerts',
        () async {
          final bytes = utf8.encode(jsonEncode({'alerts': currentRows}));
          final kept = jsonEncode([record]);
          preferences.values['safety_alert_release_v1'] = jsonEncode({
            'feed': base64Encode(bytes),
            'checksum': 'sha256:${sha256.convert(bytes)}',
            'kept': kept,
            'kept_checksum': 'sha256:${sha256.convert(utf8.encode(kept))}',
          });
          expect(
            (await repository.loadCachedAlerts()).map((a) => a.revision),
            currentRows.map((row) => row['revision']),
          );
          expect(
            (await repository.loadCurrent()).alerts.map((a) => a.revision),
            currentRows.map((row) => row['revision']),
          );
        },
      );
    }

    test('keeps the warning the device already had', () async {
      publish([record]);
      await repository.loadCurrent();

      publish([unreadable]);
      final release = await repository.loadCurrent();

      expect(release.alerts.map((a) => (a.alertId, a.revision)), [
        ('SA_2026_0001', known),
      ]);
      expect(release.isComplete, isFalse);
      expect((await repository.loadCachedAlerts()).single.revision, known);
    });

    test(
      'still keeps it offline, and across another unreadable feed',
      () async {
        publish([record]);
        await repository.loadCurrent();
        publish([unreadable]);
        await repository.loadCurrent();
        publish([unreadable]);
        await repository.loadCurrent();

        feed = null;
        final offline = await repository.loadCurrent();

        expect(offline.alerts.single.revision, known);
        expect(offline.isComplete, isFalse);
      },
    );

    test('is replaced once a readable revision arrives', () async {
      publish([record]);
      await repository.loadCurrent();
      publish([unreadable]);
      await repository.loadCurrent();

      publish([
        {...record, 'revision': known + 2},
      ]);
      final release = await repository.loadCurrent();

      expect(release.alerts.single.revision, known + 2);
      expect(release.isComplete, isTrue);
    });

    test('a withdrawn alert still goes away', () async {
      publish([record]);
      await repository.loadCurrent();
      publish([unreadable]);
      await repository.loadCurrent();

      publish([]);
      final release = await repository.loadCurrent();

      expect(release.alerts, isEmpty);
      expect(await repository.loadCachedAlerts(), isEmpty);
    });

    test('never invents a warning the device did not have', () async {
      publish([unreadable]);

      final release = await repository.loadCurrent();

      expect(release.alerts, isEmpty);
      expect(release.isComplete, isFalse);
    });
  });

  group('a feed written for a newer app', () {
    Future<SafetyAlertRelease> load(Map<String, Object?> extra) async {
      final feed = jsonEncode({
        'alerts': [record, extra],
      });
      final checksum = 'sha256:${sha256.convert(utf8.encode(feed))}';
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        httpClient: MockClient((request) async {
          if (request.url.path.contains('/storage/')) {
            return http.Response(feed, 200, request: request);
          }
          return http.Response(
            jsonEncode({'feed_path': 'safety/feed.json', 'checksum': checksum}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      return SafetyAlertRepository(
        client: client,
        preferences: _MemoryPreferences(),
      ).loadCurrent();
    }

    final later = {...record, 'alert_id': 'SA_2026_0002'};

    test('an unknown event type does not lose the alerts this build can '
        'read', () async {
      final release = await load({...later, 'event_type': 'interaction_rule'});

      expect(release.alerts.map((a) => a.alertId), ['SA_2026_0001']);
      expect(
        release.isComplete,
        isFalse,
        reason: 'an alert this build could not read must not count as checked',
      );
    });

    test('an unknown disposition does not lose them either', () async {
      final release = await load({...later, 'consumer_disposition': 'future'});

      expect(release.alerts.map((a) => a.alertId), ['SA_2026_0001']);
      expect(release.isComplete, isFalse);
    });

    test('a malformed alert of a known type still rejects the feed', () async {
      final release = await load({...later, 'revision': 0});

      expect(
        release.alerts,
        isEmpty,
        reason: 'damage is not forward compatibility; it stays fail-closed',
      );
      expect(release.isComplete, isFalse);
    });
  });

  test(
    'verified production feed survives cache-only/offline reads and rejects tampering',
    () async {
      // The pipeline ships a full, indented feed with metadata and a newline.
      // Its checksum must cover these exact bytes, not a reconstructed model.
      final feed =
          '${const JsonEncoder.withIndent('  ').convert({
            'schema_version': '1.0.0',
            'generated_at': '2026-10-01',
            'alert_count': 1,
            'alerts': [record],
          })}\n';
      final checksum = 'sha256:${sha256.convert(utf8.encode(feed))}';
      final preferences = _MemoryPreferences();
      var offline = false;
      var requests = 0;
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        httpClient: MockClient((request) async {
          requests++;
          if (offline) throw http.ClientException('offline');
          if (request.url.path.contains('/storage/')) {
            return http.Response(feed, 200, request: request);
          }
          return http.Response(
            jsonEncode({'feed_path': 'safety/feed.json', 'checksum': checksum}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final repository = SafetyAlertRepository(
        client: client,
        preferences: preferences,
      );
      final current = await repository.loadCurrent();
      expect(current.isComplete, isTrue);
      expect(current.alerts.single.alertId, 'SA_2026_0001');
      final beforeCacheRead = requests;
      expect(
        (await repository.loadCachedAlerts()).single.alertId,
        'SA_2026_0001',
      );
      expect(
        requests,
        beforeCacheRead,
        reason: 'Cache-only scan admission makes no HTTP request',
      );
      offline = true;
      final fallback = await repository.loadCurrent();
      expect(fallback.isComplete, isFalse);
      expect(fallback.alerts.single.alertId, 'SA_2026_0001');
      expect(fallback.baselineRevisions, current.baselineRevisions);

      // A cached byte mutation remains rejected against the release checksum.
      final payload =
          jsonDecode(preferences.values['safety_alert_release_v1']!)
              as Map<String, dynamic>;
      payload['feed'] = base64Encode(utf8.encode('$feed '));
      preferences.values['safety_alert_release_v1'] = jsonEncode(payload);
      final beforeTamperRead = requests;
      expect(await repository.loadCachedAlerts(), isEmpty);
      expect(
        requests,
        beforeTamperRead,
        reason: 'Corrupt cache must not trigger HTTP in scan admission',
      );
      expect((await repository.loadCurrent()).alerts, isEmpty);
    },
  );
}

class _MemoryPreferences implements SharedPreferencesAsync {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
