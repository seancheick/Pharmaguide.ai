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

/// What `feed_path` names: what every installed build reads.
final _baseBytes = File(
  'test/fixtures/safety_alerts/interaction_rule_base_feed.json',
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

const _extendedPath = 'safety/extended.json';

/// Serves [body] the way Supabase does, and records what the app asked for.
/// With [extended], the release names a superset feed too. [manifest] replaces
/// that entry, for a release whose manifest is damaged.
SupabaseClient _client(
  Object? Function() body, {
  List<http.Request>? requests,
  Object? Function()? extended,
  Object? manifest,
}) {
  final client = SupabaseClient(
    'https://example.test',
    'test-key',
    httpClient: MockClient((request) async {
      requests?.add(request);
      final current = body();
      if (current == null) throw http.ClientException('offline');
      final bytes = current as List<int>;
      if (request.url.path.contains(_extendedPath)) {
        final superset = extended!();
        if (superset == null) throw http.ClientException('missing');
        return http.Response.bytes(
          superset as List<int>,
          200,
          request: request,
        );
      }
      if (request.url.path.contains('/storage/')) {
        return http.Response.bytes(bytes, 200, request: request);
      }
      return http.Response(
        jsonEncode({
          'feed_path': 'safety/feed.json',
          'checksum': 'sha256:${sha256.convert(bytes)}',
          'manifest':
              manifest ??
              {
                if (extended != null)
                  'extended_feed': {
                    'path': _extendedPath,
                    'checksum': 'sha256:${sha256.convert(_feedBytes)}',
                  },
              },
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
    // Two pins, one fixture: the pipeline pins these digests in
    // scripts/tests/test_safety_alerts_publisher.py. Regenerate there.
    expect(
      'sha256:${sha256.convert(_feedBytes)}',
      'sha256:e0f20b54bcdf8aa77eef02c2c8420644adb390510546f8121e8e3359f3c1eb8f',
    );
    expect(
      'sha256:${sha256.convert(_baseBytes)}',
      'sha256:7564e689beaa6fe47a794d3121ac715c211a487476098e3c80c6b0bde2a940c5',
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

    group('for pregnancy, lactation or a condition', () {
      Map<String, Object?> pregnancyRow() {
        final feed =
            jsonDecode(utf8.decode(_feedBytes)) as Map<String, dynamic>;
        return Map<String, Object?>.from(
          (feed['alerts'] as List).cast<Map<String, dynamic>>().firstWhere(
            (alert) => alert['alert_id'] == 'SA_9999_0003',
          ),
        );
      }

      Map<String, Object?> withGate(
        Map<String, Object?> Function(Map<String, dynamic> gate) change,
      ) {
        final row = pregnancyRow();
        final block = Map<String, dynamic>.from(row['interaction'] as Map);
        final gate =
            jsonDecode(jsonEncode(block['profile_gate']))
                as Map<String, dynamic>;
        return {
          ...row,
          'interaction': {...block, 'profile_gate': change(gate)},
        };
      }

      Map<String, Object?> requiring(String key, List<String> ids) =>
          withGate((gate) {
            (gate['requires'] as Map)['profile_flags_any'] = <String>[];
            (gate['requires'] as Map)[key] = ids;
            gate['gate_type'] = key == 'conditions_any'
                ? 'condition'
                : 'profile_flag';
            return gate;
          });

      bool matches(Map<String, Object?> row, DeviceSafetyProfile device) =>
          SafetyAlert.fromJson(row).appliesTo(
            dsldId: 'not-in-the-set',
            ingredientCanonicalIds: const ['fake_fakeroot'],
            device: device,
          );

      test('matches only someone it is for', () {
        expect(
          matches(
            pregnancyRow(),
            const DeviceSafetyProfile(profileFlags: {'pregnant'}),
          ),
          isTrue,
        );
        for (final device in const [
          DeviceSafetyProfile(),
          DeviceSafetyProfile(profileFlags: {'breastfeeding'}),
          DeviceSafetyProfile(conditions: {'liver_disease'}),
          DeviceSafetyProfile(medicationIds: {_medicationId}),
        ]) {
          expect(matches(pregnancyRow(), device), isFalse);
        }
      });

      test('still needs the product or ingredient to match', () {
        expect(
          SafetyAlert.fromJson(pregnancyRow()).appliesTo(
            dsldId: 'not-in-the-set',
            ingredientCanonicalIds: const ['another_ingredient'],
            device: const DeviceSafetyProfile(profileFlags: {'pregnant'}),
          ),
          isFalse,
        );
      });

      test('lactation and a condition match the same way', () {
        final lactation = requiring('profile_flags_any', ['breastfeeding']);
        expect(
          matches(
            lactation,
            const DeviceSafetyProfile(profileFlags: {'breastfeeding'}),
          ),
          isTrue,
        );
        expect(
          matches(
            lactation,
            const DeviceSafetyProfile(profileFlags: {'pregnant'}),
          ),
          isFalse,
        );

        final condition = requiring('conditions_any', ['liver_disease']);
        expect(
          matches(
            condition,
            const DeviceSafetyProfile(conditions: {'liver_disease'}),
          ),
          isTrue,
        );
        expect(
          matches(
            condition,
            const DeviceSafetyProfile(conditions: {'diabetes'}),
          ),
          isFalse,
        );
      });

      test('an excluded person is not told', () {
        final row = withGate((gate) {
          (gate['excludes'] as Map)['conditions_any'] = ['liver_disease'];
          return gate;
        });
        expect(
          matches(
            row,
            const DeviceSafetyProfile(
              profileFlags: {'pregnant'},
              conditions: {'liver_disease'},
            ),
          ),
          isFalse,
        );
      });

      test('the notice names who it is for, the reason and the evidence', () {
        final notice = SafetyAlert.fromJson(pregnancyRow()).interactionNotice!;
        expect(notice, contains('Ingredient: Fakeroot (fictional)'));
        expect(notice, contains('Applies to: Pregnancy'));
        expect(notice, isNot(contains('Medication:')));
        expect(notice, contains('not for use during pregnancy'));
        expect(notice, contains(EvidenceLevel.established.label));
      });

      final refused = <String, Map<String, Object?> Function()>{
        'no one': () => withGate((gate) {
          (gate['requires'] as Map)['profile_flags_any'] = <String>[];
          return gate;
        }),
        'a dose': () => withGate((gate) {
          gate['dose'] = {'threshold': 1};
          return gate;
        }),
        'a product form': () => withGate((gate) {
          (gate['excludes'] as Map)['product_forms_any'] = ['topical'];
          return gate;
        }),
        'a nutrient form': () => withGate((gate) {
          (gate['excludes'] as Map)['nutrient_forms_any'] = ['retinol'];
          return gate;
        }),
        'a key this build does not know': () => withGate((gate) {
          (gate['requires'] as Map)['ages_any'] = ['adult'];
          return gate;
        }),
        'both targets': () {
          final row = pregnancyRow();
          return {
            ...row,
            'interaction': {
              ...(row['interaction'] as Map),
              'medication_name': 'Fake',
              'medication_ids': ['0000001'],
            },
          };
        },
        'no target': () {
          final row = pregnancyRow();
          return {
            ...row,
            'interaction': Map<String, dynamic>.from(row['interaction'] as Map)
              ..remove('profile_gate')
              ..remove('profile_context'),
          };
        },
        'no label': () {
          final row = pregnancyRow();
          return {
            ...row,
            'interaction': Map<String, dynamic>.from(row['interaction'] as Map)
              ..remove('profile_context'),
          };
        },
      };
      for (final entry in refused.entries) {
        test('skips one with ${entry.key}, without costing the feed', () {
          expect(
            () => SafetyAlert.fromJson(entry.value()),
            throwsA(isA<UnsupportedSafetyAlert>()),
          );
        });
      }
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
            device: const DeviceSafetyProfile(medicationIds: {_medicationId}),
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
              device: DeviceSafetyProfile(medicationIds: medications),
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
          device: const DeviceSafetyProfile(medicationIds: {_medicationId}),
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
          device: const DeviceSafetyProfile(),
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
      'no scope': {..._feedAlert('interaction_rule')}..remove('scope'),
      'no scope ingredients': {
        ..._feedAlert('interaction_rule'),
        'scope': <String, Object?>{'dsld_ids': <String>[]},
      },
      'null resolved products': {
        ..._feedAlert('interaction_rule'),
        'resolved_dsld_ids': null,
      },
      'blank reason': {..._feedAlert('interaction_rule'), 'body': ' '},
      'insecure source': {
        ..._feedAlert('interaction_rule'),
        'source_url': 'http://example.org/fake',
      },
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
        Object? served = _baseBytes;
        final repository = SafetyAlertRepository(
          client: _client(() => served, extended: () => _feedBytes),
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

    test('a damaged ban still rejects the feed, as it always has', () {
      expect(
        () => SafetyAlert.fromJson({
          ..._feedAlert('ingredient_ban'),
          'source_url': 'http://example.org/fake',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fetching the feed sends nothing about medications', () async {
      final requests = <http.Request>[];
      final release = await SafetyAlertRepository(
        client: _client(
          () => _baseBytes,
          extended: () => _feedBytes,
          requests: requests,
        ),
        preferences: _MemoryPreferences(),
      ).loadCurrent();

      expect(release.alerts, hasLength(4));
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

  group('the extended feed', () {
    List<String> ids(SafetyAlertRelease release) =>
        release.alerts.map((alert) => alert.alertId).toList()..sort();

    test('this build reads every alert when the release names it', () async {
      final release = await SafetyAlertRepository(
        client: _client(() => _baseBytes, extended: () => _feedBytes),
        preferences: _MemoryPreferences(),
      ).loadCurrent();

      expect(ids(release), [
        'SA_9999_0001',
        'SA_9999_0002',
        'SA_9999_0003',
        'SA_9999_0004',
      ]);
      expect(release.isComplete, isTrue);
    });

    test('a release that names none is read as it always was', () async {
      final release = await SafetyAlertRepository(
        client: _client(() => _baseBytes),
        preferences: _MemoryPreferences(),
      ).loadCurrent();

      expect(ids(release), ['SA_9999_0002', 'SA_9999_0004']);
      expect(release.isComplete, isTrue);
    });

    test('unavailable: bans and recalls still load, and it is not a complete '
        'check', () async {
      final release = await SafetyAlertRepository(
        client: _client(() => _baseBytes, extended: () => null),
        preferences: _MemoryPreferences(),
      ).loadCurrent();

      expect(ids(release), ['SA_9999_0002', 'SA_9999_0004']);
      expect(release.isComplete, isFalse);
    });

    test('tampered bytes count as unavailable', () async {
      final release = await SafetyAlertRepository(
        client: _client(() => _baseBytes, extended: () => utf8.encode('{}')),
        preferences: _MemoryPreferences(),
      ).loadCurrent();

      expect(ids(release), ['SA_9999_0002', 'SA_9999_0004']);
      expect(release.isComplete, isFalse);
    });

    test('a damaged manifest entry counts as unavailable', () async {
      final release = await SafetyAlertRepository(
        client: _client(
          () => _baseBytes,
          manifest: {'extended_feed': 'not a location'},
        ),
        preferences: _MemoryPreferences(),
      ).loadCurrent();

      expect(ids(release), ['SA_9999_0002', 'SA_9999_0004']);
      expect(release.isComplete, isFalse);
    });

    test('unavailable later: a new ban arrives and rules already held stay, '
        'through a second failure too', () async {
      Object? superset = _feedBytes;
      Object? base = _baseBytes;
      final repository = SafetyAlertRepository(
        client: _client(() => base, extended: () => superset),
        preferences: _MemoryPreferences(),
      );
      await repository.loadCurrent();

      superset = null;
      base = utf8.encode(
        jsonEncode({
          'alerts': [
            _feedAlert('ingredient_ban')..['alert_id'] = 'SA_9999_0009',
          ],
        }),
      );
      for (var i = 0; i < 2; i++) {
        final release = await repository.loadCurrent();
        expect(ids(release), ['SA_9999_0001', 'SA_9999_0003', 'SA_9999_0009']);
        expect(release.isComplete, isFalse);
      }
    });

    test('offline, the rules come back from the verified copy', () async {
      Object? base = _baseBytes;
      final repository = SafetyAlertRepository(
        client: _client(() => base, extended: () => _feedBytes),
        preferences: _MemoryPreferences(),
      );
      await repository.loadCurrent();

      base = null;
      final release = await repository.loadCurrent();

      expect(release.alerts, hasLength(4));
      expect(release.isComplete, isFalse);
    });
  });

  group('builds already on phones, on the real old path', () {
    const banAndRecall = ['SA_9999_0002', 'SA_9999_0004'];
    List<String> ids(Iterable<String> alertIds) => alertIds.toList()..sort();

    test('the feed they read has no rule in it', () {
      final feed = jsonDecode(utf8.decode(_baseBytes)) as Map<String, dynamic>;
      expect(feed['schema_version'], '1.0.0');
      expect(
        (feed['alerts'] as List).map((alert) => (alert as Map)['event_type']),
        unorderedEquals(['ingredient_ban', 'product_recall']),
      );
    });

    test('a fresh install before the skip gets the ban and the recall, '
        'complete', () async {
      final release = await pre_skip.SafetyAlertRepository(
        client: _client(() => _baseBytes, extended: () => _feedBytes),
        preferences: _MemoryPreferences(),
      ).loadCurrent();

      expect(ids(release.alerts.map((a) => a.alertId)), banAndRecall);
      expect(release.isComplete, isTrue);
    });

    test('a fresh install with the skip gets the ban and the recall, '
        'complete', () async {
      final repository = skip_unknown.SafetyAlertRepository(
        client: _client(() => _baseBytes, extended: () => _feedBytes),
        preferences: _MemoryPreferences(),
      );

      final release = await repository.loadCurrent();

      expect(ids(release.alerts.map((a) => a.alertId)), banAndRecall);
      expect(release.isComplete, isTrue);
      expect(await repository.loadCachedAlerts(), hasLength(2));
    });

    test('an install with an earlier copy moves on to the ban and the '
        'recall', () async {
      late List<int> feed;
      final repository = pre_skip.SafetyAlertRepository(
        client: _client(() => feed, extended: () => _feedBytes),
        preferences: _MemoryPreferences(),
      );
      feed = utf8.encode(
        jsonEncode({
          'alerts': [
            _feedAlert('ingredient_ban')
              ..['alert_id'] = 'SA_9999_0009'
              ..['headline'] = 'Earlier fake alert',
          ],
        }),
      );
      await repository.loadCurrent();

      feed = _baseBytes;
      final release = await repository.loadCurrent();

      expect(ids(release.alerts.map((a) => a.alertId)), banAndRecall);
      expect(release.isComplete, isTrue);
    });

    test('WHY: a rule on that path would cost a fresh install every '
        'alert', () async {
      final release = await pre_skip.SafetyAlertRepository(
        client: _client(() => _feedBytes),
        preferences: _MemoryPreferences(),
      ).loadCurrent();

      expect(release.alerts, isEmpty);
      expect(release.isComplete, isFalse);
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
