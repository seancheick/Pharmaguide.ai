import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'legacy_readers/pre_skip_repository.dart' as pre_skip;
import 'legacy_readers/skip_unknown_repository.dart' as skip_unknown;

const _medicationId = 'class:fake_test_medications';

final _feedBytes = File(
  'test/fixtures/safety_alerts/interaction_rule_feed.json',
).readAsBytesSync();

Map<String, Object?> _feedAlert(String eventType) {
  final feed = jsonDecode(utf8.decode(_feedBytes)) as Map<String, dynamic>;
  return Map<String, Object?>.from(
    (feed['alerts'] as List).cast<Map<String, dynamic>>().firstWhere(
      (alert) => alert['event_type'] == eventType,
    ),
  );
}

Map<String, Object?> _interactionWith(Map<String, Object?> changes) {
  final row = _feedAlert('interaction_rule');
  return {
    ...row,
    'interaction': {...(row['interaction'] as Map), ...changes},
  };
}

/// Serves [body] the way Supabase does, and records what the app asked for.
SupabaseClient _client(
  Object? Function() body, {
  List<http.Request>? requests,
}) {
  final client = SupabaseClient(
    'https://example.test',
    'test-key',
    httpClient: MockClient((request) async {
      requests?.add(request);
      final current = body();
      if (current == null) throw http.ClientException('offline');
      final bytes = current as List<int>;
      if (request.url.path.contains('/storage/')) {
        return http.Response.bytes(bytes, 200, request: request);
      }
      return http.Response(
        jsonEncode({
          'feed_path': 'safety/feed.json',
          'checksum': 'sha256:${sha256.convert(bytes)}',
        }),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
  );
  addTearDown(client.dispose);
  return client;
}

void main() {
  test('reads the same bytes the pipeline staged', () {
    // Two pins, one fixture: the pipeline pins this digest in
    // scripts/tests/test_safety_alerts_publisher.py. Regenerate there.
    expect(
      'sha256:${sha256.convert(_feedBytes)}',
      'sha256:7c17891cabd3e4fa495c19bd2d42765e229ef4bb46dd3176ce11d84e006b0219',
    );
  });

  group('interaction-rule alert', () {
    test('parses the ingredient, medication, reason and source', () {
      final alert = SafetyAlert.fromJson(_feedAlert('interaction_rule'));
      final interaction = alert.interaction!;

      expect(alert.eventType, SafetyAlertEventType.interactionRule);
      expect(interaction.ruleId, 'DSI_FAKE_TESTOPRILEX_FAKEROOT');
      expect(interaction.ingredientName, 'Fakeroot (fictional)');
      expect(interaction.medicationName, 'Testoprilex (fictional)');
      expect(interaction.medicationIds, contains(_medicationId));
      expect(interaction.severity, Severity.contraindicated);
      expect(interaction.evidenceLevel, EvidenceLevel.established);
      expect(alert.sourceUrl.host, 'example.org');
    });

    test('other event types carry no interaction', () {
      expect(
        SafetyAlert.fromJson(_feedAlert('ingredient_ban')).interaction,
        isNull,
      );
    });

    test('matches only someone taking the medication', () {
      final alert = SafetyAlert.fromJson(_feedAlert('interaction_rule'));
      final dsldId = alert.resolvedDsldIds.first;
      final ingredient = alert.ingredientCanonicalIds.first;

      for (final (id, ingredients) in [
        (dsldId, const <String>[]),
        ('not-in-the-set', [ingredient]),
      ]) {
        expect(
          alert.appliesTo(
            dsldId: id,
            ingredientCanonicalIds: ingredients,
            medicationIds: const {_medicationId},
          ),
          isTrue,
        );
        for (final medications in [
          const <String>{},
          const {'class:some_other_class'},
        ]) {
          expect(
            alert.appliesTo(
              dsldId: id,
              ingredientCanonicalIds: ingredients,
              medicationIds: medications,
            ),
            isFalse,
            reason: 'Nobody without the medication gets this notice.',
          );
        }
      }
    });

    test('still needs the product or ingredient to match', () {
      final alert = SafetyAlert.fromJson(_feedAlert('interaction_rule'));
      expect(
        alert.appliesTo(
          dsldId: 'not-in-the-set',
          ingredientCanonicalIds: const ['another_ingredient'],
          medicationIds: const {_medicationId},
        ),
        isFalse,
      );
    });

    test('a ban ignores medications, as it always has', () {
      final alert = SafetyAlert.fromJson(_feedAlert('ingredient_ban'));
      expect(
        alert.appliesTo(
          dsldId: alert.resolvedDsldIds.first,
          ingredientCanonicalIds: const [],
          medicationIds: const {},
        ),
        isTrue,
      );
    });

    for (final MapEntry(key: name, value: row) in {
      'no block': {..._feedAlert('interaction_rule')}..remove('interaction'),
      'null block': {..._feedAlert('interaction_rule'), 'interaction': null},
      'block of the wrong type': {
        ..._feedAlert('interaction_rule'),
        'interaction': 'contraindicated',
      },
      'null rule id': _interactionWith({'rule_id': null}),
      'null ingredient': _interactionWith({'ingredient_name': null}),
      'blank medication': _interactionWith({'medication_name': '  '}),
      'null medication ids': _interactionWith({'medication_ids': null}),
      'empty medication ids': _interactionWith({'medication_ids': <String>[]}),
      'non-text medication id': _interactionWith({
        'medication_ids': [42],
      }),
      'null severity': _interactionWith({'severity': null}),
      'unknown severity': _interactionWith({'severity': 'severe_future_tier'}),
      'informational severity': _interactionWith({'severity': 'informational'}),
    }.entries) {
      test('is skipped safely with $name', () {
        expect(
          () => SafetyAlert.fromJson(row),
          throwsA(isA<UnsupportedSafetyAlert>()),
        );
      });
    }

    for (final (name, value) in [
      ('null', null),
      ('a number', 3),
      ('unknown', 'future_tier'),
    ]) {
      test('shows evidence as not graded when it is $name', () {
        final alert = SafetyAlert.fromJson(
          _interactionWith({'evidence_level': value}),
        );
        expect(alert.interaction!.evidenceLevel, EvidenceLevel.ungraded);
      });
    }
  });

  group('repository', () {
    test('a malformed interaction block keeps the ban readable', () async {
      final bytes = utf8.encode(
        jsonEncode({
          'alerts': [
            _feedAlert('ingredient_ban'),
            _interactionWith({'medication_ids': null}),
          ],
        }),
      );
      final release = await SafetyAlertRepository(
        client: _client(() => bytes),
        preferences: _MemoryPreferences(),
      ).loadCurrent();

      expect(release.alerts.map((a) => a.eventType), [
        SafetyAlertEventType.ingredientBan,
      ]);
      expect(release.isComplete, isFalse);
    });

    test(
      'a rule already received stays after the phone goes offline',
      () async {
        Object? served = _feedBytes;
        final repository = SafetyAlertRepository(
          client: _client(() => served),
          preferences: _MemoryPreferences(),
        );
        await repository.loadCurrent();

        served = null;
        final release = await repository.loadCurrent();

        expect(release.isComplete, isFalse);
        expect(
          release.alerts.map((alert) => alert.interaction?.medicationName),
          contains('Testoprilex (fictional)'),
        );
      },
    );

    test('fetching the feed sends nothing about medications', () async {
      final requests = <http.Request>[];
      final release = await SafetyAlertRepository(
        client: _client(() => _feedBytes, requests: requests),
        preferences: _MemoryPreferences(),
      ).loadCurrent();

      expect(release.alerts, hasLength(2));
      expect(requests, isNotEmpty);
      for (final request in requests) {
        final sent = [
          request.url.toString(),
          request.body,
          request.headers.toString(),
        ].join(' ').toLowerCase();
        for (final private in ['medication', 'rxcui', 'drug', 'class:']) {
          expect(
            sent,
            isNot(contains(private)),
            reason: request.url.toString(),
          );
        }
      }
    });
  });

  group('builds already on phones, reading the new feed', () {
    late List<int> feed;
    setUp(() => feed = _feedBytes);

    final oldFeed = utf8.encode(
      jsonEncode({
        'alerts': [
          _feedAlert('ingredient_ban')
            ..['alert_id'] = 'SA_9999_0009'
            ..['headline'] = 'Earlier fake alert',
        ],
      }),
    );

    test('a build with the skip reads the ban, skips the rule, stays '
        'incomplete', () async {
      final repository = skip_unknown.SafetyAlertRepository(
        client: _client(() => feed),
        preferences: _MemoryPreferences(),
      );

      final release = await repository.loadCurrent();

      expect(release.alerts.map((a) => a.alertId), [
        _feedAlert('ingredient_ban')['alert_id'],
      ]);
      expect(release.isComplete, isFalse);
      expect(await repository.loadCachedAlerts(), hasLength(1));
    });

    test('a build before the skip keeps its last good copy and does not '
        'crash', () async {
      final preferences = _MemoryPreferences();
      final repository = pre_skip.SafetyAlertRepository(
        client: _client(() => feed),
        preferences: preferences,
      );
      feed = oldFeed;
      await repository.loadCurrent();

      feed = _feedBytes;
      final release = await repository.loadCurrent();

      expect(release.alerts.map((a) => a.alertId), ['SA_9999_0009']);
      expect(release.isComplete, isFalse);
    });

    test('LIMIT: a fresh install of a build before the skip gets no alerts '
        'at all', () async {
      final release = await pre_skip.SafetyAlertRepository(
        client: _client(() => feed),
        preferences: _MemoryPreferences(),
      ).loadCurrent();

      expect(release.alerts, isEmpty);
      expect(release.isComplete, isFalse);
    });

    test('the current build reads both', () async {
      final release = await SafetyAlertRepository(
        client: _client(() => feed),
        preferences: _MemoryPreferences(),
      ).loadCurrent();

      expect(release.alerts, hasLength(2));
      expect(release.isComplete, isTrue);
    });
  });
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
