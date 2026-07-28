// Unit tests for RxNormApiService (M4 §8.4).
//
// All HTTP is faked via the [RxNormHttpGet] typedef so the tests are
// hermetic — no real network calls. The integration test that hits the
// live RxNorm endpoints lives separately under
// test/integration/ and is opt-in via the `--tags live` flag.
//
// Coverage targets:
//   - Each public RPC parses the canned JSON shape we expect from the
//     real endpoint.
//   - Class-name slugifier matches the M2 pipeline output (so the ids
//     round-trip with the bundled DB without further translation).
//   - LRU cache evicts oldest after [cacheSize] entries and bubbles
//     hits to the back (true LRU semantics).
//   - Sliding 1-second rate limiter sleeps once we hit
//     [requestsPerSecond] in the same window.
//   - Network errors are swallowed (return null) so the medication-entry
//     flow can fall back to the offline class picker without exception
//     handling at the call site.
//   - offlineDrugClasses returns the bundled DB's class ids
//     alphabetically.
//
// Run:
//   flutter test test/services/medications/rxnorm_api_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/services/medications/rxnorm_api_service.dart';

/// Builds a [RxNormHttpGet] that returns canned responses keyed by the
/// request URL's path. Records every URL hit for assertion.
class _FakeHttp {
  _FakeHttp(this._responses);

  final Map<String, String> _responses;
  final List<Uri> hits = <Uri>[];
  int _calls = 0;

  int get callCount => _calls;

  Future<String> call(Uri url) async {
    _calls++;
    hits.add(url);
    final body = _responses[url.path];
    if (body == null) {
      throw StateError('No canned response for ${url.path}');
    }
    return body;
  }
}

/// Always-throws transport, for the offline / network-error path.
Future<String> _throwingHttp(Uri url) async {
  throw const _FakeNetworkError();
}

class _FakeNetworkError implements Exception {
  const _FakeNetworkError();
}

void main() {
  group('RxNormApiService.search', () {
    test('returns empty list for queries shorter than 2 chars', () async {
      final fake = _FakeHttp(const {});
      final svc = RxNormApiService(httpGet: fake.call);

      expect(await svc.search(''), isEmpty);
      expect(await svc.search('a'), isEmpty);
      expect(await svc.search('  '), isEmpty);
      expect(fake.callCount, 0); // never hit the wire
    });

    test('parses approximateGroup.candidate into ranked suggestions', () async {
      final fake = _FakeHttp(const {
        '/REST/approximateTerm.json': '''
        {
          "approximateGroup": {
            "candidate": [
              {"rxcui": "1191", "name": "aspirin", "score": "100", "rank": "1"},
              {"rxcui": "1234", "name": "aspirin EC", "score": "85", "rank": "2"},
              {"rxcui": "9999", "name": "aspirin gum", "score": "60", "rank": "3"}
            ]
          }
        }
        ''',
      });
      final svc = RxNormApiService(httpGet: fake.call);

      final out = await svc.search('aspirin');
      expect(out, hasLength(3));
      // Sorted by score descending.
      expect(out[0].name, 'aspirin');
      expect(out[0].score, 100);
      expect(out[1].score, 85);
      expect(out[2].score, 60);
      expect(fake.hits.single.queryParameters['option'], '1');
    });

    test(
      'keeps the named atom when an unnamed atom shares its rxcui',
      () async {
        final fake = _FakeHttp(const {
          '/REST/approximateTerm.json': '''
        {
          "approximateGroup": {
            "candidate": [
              {"rxcui": "6809", "score": "100", "source": "GS"},
              {
                "rxcui": "6809",
                "name": "metformin",
                "score": "100",
                "source": "RXNORM"
              }
            ]
          }
        }
        ''',
        });
        final svc = RxNormApiService(httpGet: fake.call);

        final out = await svc.search('metformin');

        expect(out, hasLength(1));
        expect(out.single.rxcui, '6809');
        expect(out.single.name, 'metformin');
      },
    );

    test('dedupes candidates by rxcui', () async {
      final fake = _FakeHttp(const {
        '/REST/approximateTerm.json': '''
        {
          "approximateGroup": {
            "candidate": [
              {"rxcui": "1191", "name": "aspirin", "score": "100"},
              {"rxcui": "1191", "name": "ASPIRIN", "score": "95"},
              {"rxcui": "1234", "name": "aspirin EC", "score": "85"}
            ]
          }
        }
        ''',
      });
      final svc = RxNormApiService(httpGet: fake.call);

      final out = await svc.search('aspirin');
      expect(out, hasLength(2));
      expect(out.map((s) => s.rxcui).toSet(), {'1191', '1234'});
    });

    test('returns empty list on malformed JSON without throwing', () async {
      final fake = _FakeHttp(const {'/REST/approximateTerm.json': 'not json'});
      final svc = RxNormApiService(httpGet: fake.call);

      expect(await svc.search('foo'), isEmpty);
    });

    test('returns empty list on missing approximateGroup', () async {
      final fake = _FakeHttp(const {'/REST/approximateTerm.json': '{}'});
      final svc = RxNormApiService(httpGet: fake.call);

      expect(await svc.search('foo'), isEmpty);
    });

    test('returns empty list on network error', () async {
      final svc = RxNormApiService(httpGet: _throwingHttp);
      expect(await svc.search('warfarin'), isEmpty);
    });
  });

  group('RxNormApiService.getRxcui', () {
    test('returns first rxnormId from idGroup', () async {
      final fake = _FakeHttp(const {
        '/REST/rxcui.json': '''
        {
          "idGroup": {
            "name": "Warfarin",
            "rxnormId": ["11289", "1234"]
          }
        }
        ''',
      });
      final svc = RxNormApiService(httpGet: fake.call);

      expect(await svc.getRxcui('warfarin'), '11289');
    });

    test('returns null when idGroup has no rxnormId', () async {
      final fake = _FakeHttp(const {
        '/REST/rxcui.json': '{"idGroup": {"name": "Unknown"}}',
      });
      final svc = RxNormApiService(httpGet: fake.call);

      expect(await svc.getRxcui('unknown'), isNull);
    });

    test('returns null on empty drug name without HTTP hit', () async {
      final fake = _FakeHttp(const {});
      final svc = RxNormApiService(httpGet: fake.call);

      expect(await svc.getRxcui(''), isNull);
      expect(await svc.getRxcui('   '), isNull);
      expect(fake.callCount, 0);
    });

    test('returns null on network error', () async {
      final svc = RxNormApiService(httpGet: _throwingHttp);
      expect(await svc.getRxcui('warfarin'), isNull);
    });
  });

  group('RxNormApiService.getClasses', () {
    test(
      'keeps MED-RT interaction categories but excludes diseases and PK',
      () async {
        Future<String> httpGet(Uri url) async {
          if (url.queryParameters['relaSource'] == 'ATC') {
            return '{}';
          }
          return '''
          {
            "rxclassDrugInfoList": {
              "rxclassDrugInfo": [
                {
                  "rela": "ci_with",
                  "rxclassMinConceptItem": {
                    "className": "Renal Insufficiency",
                    "classType": "DISEASE"
                  }
                },
                {
                  "rela": "may_treat",
                  "rxclassMinConceptItem": {
                    "className": "Diabetes Mellitus, Type 2",
                    "classType": "DISEASE"
                  }
                },
                {
                  "rela": "has_pk",
                  "rxclassMinConceptItem": {
                    "className": "Renal Excretion",
                    "classType": "PK"
                  }
                },
                {
                  "rela": "has_moa",
                  "rxclassMinConceptItem": {
                    "className": "Insulin Receptor Agonists",
                    "classType": "MOA"
                  }
                },
                {
                  "rela": "has_pe",
                  "rxclassMinConceptItem": {
                    "className": "Decreased Gluconeogenesis",
                    "classType": "PE"
                  }
                }
              ]
            }
          }
          ''';
        }

        final svc = RxNormApiService(httpGet: httpGet);
        final classes = await svc.getClasses('6809');

        expect(classes, [
          'class:decreased_gluconeogenesis',
          'class:insulin_receptor_agonists',
        ]);
      },
    );

    test('parses className list and slugifies to class:* form', () async {
      final fake = _FakeHttp(const {
        '/REST/rxclass/class/byRxcui.json': '''
        {
          "rxclassDrugInfoList": {
            "rxclassDrugInfo": [
              {
                "rxclassMinConceptItem": {
                  "classId": "ATC1",
                  "className": "ACE Inhibitors",
                  "classType": "ATC1-4"
                }
              },
              {
                "rxclassMinConceptItem": {
                  "classId": "ATC2",
                  "className": "Diuretics",
                  "classType": "ATC1-4"
                }
              }
            ]
          }
        }
        ''',
      });
      final svc = RxNormApiService(httpGet: fake.call);

      final classes = await svc.getClasses('11289');
      expect(classes, ['class:ace_inhibitors', 'class:diuretics']);
    });

    test('slugifies leading-digit and punctuation class names', () async {
      final fake = _FakeHttp(const {
        '/REST/rxclass/class/byRxcui.json': '''
        {
          "rxclassDrugInfoList": {
            "rxclassDrugInfo": [
              {"rxclassMinConceptItem": {"className": "5-HT3 Receptor Antagonists"}},
              {"rxclassMinConceptItem": {"className": "Anti-Inflammatory Agents, Non-Steroidal"}}
            ]
          }
        }
        ''',
      });
      final svc = RxNormApiService(httpGet: fake.call);

      final classes = await svc.getClasses('1234');
      expect(classes, [
        'class:5_ht3_receptor_antagonists',
        'class:anti_inflammatory_agents_non_steroidal',
      ]);
    });

    test('dedupes class slugs that collide after normalization', () async {
      final fake = _FakeHttp(const {
        '/REST/rxclass/class/byRxcui.json': '''
        {
          "rxclassDrugInfoList": {
            "rxclassDrugInfo": [
              {"rxclassMinConceptItem": {"className": "ACE Inhibitors"}},
              {"rxclassMinConceptItem": {"className": "ACE  Inhibitors"}},
              {"rxclassMinConceptItem": {"className": "Diuretics"}}
            ]
          }
        }
        ''',
      });
      final svc = RxNormApiService(httpGet: fake.call);

      final classes = await svc.getClasses('1234');
      expect(classes, ['class:ace_inhibitors', 'class:diuretics']);
    });

    test(
      'returns empty list when payload has no rxclassDrugInfoList',
      () async {
        final fake = _FakeHttp(const {
          '/REST/rxclass/class/byRxcui.json': '{}',
        });
        final svc = RxNormApiService(httpGet: fake.call);

        expect(await svc.getClasses('1234'), isEmpty);
      },
    );

    test('returns empty list on network error (offline)', () async {
      final svc = RxNormApiService(httpGet: _throwingHttp);
      expect(await svc.getClasses('1234'), isEmpty);
    });

    test('returns empty list on empty rxcui without HTTP hit', () async {
      final fake = _FakeHttp(const {});
      final svc = RxNormApiService(httpGet: fake.call);

      expect(await svc.getClasses(''), isEmpty);
      expect(await svc.getClasses('  '), isEmpty);
      expect(fake.callCount, 0);
    });
  });

  group('RxNormApiService.getDrugInfo', () {
    test('hydrates name + tty + synonym from properties payload', () async {
      final fake = _FakeHttp(const {
        '/REST/rxcui/11289/properties.json': '''
        {
          "properties": {
            "rxcui": "11289",
            "name": "Warfarin",
            "synonym": "Coumadin",
            "tty": "IN"
          }
        }
        ''',
      });
      final svc = RxNormApiService(httpGet: fake.call);

      final info = await svc.getDrugInfo('11289');
      expect(info, isNotNull);
      expect(info!.name, 'Warfarin');
      expect(info.synonym, 'Coumadin');
      expect(info.tty, 'IN');
      expect(info.rxcui, '11289');
    });

    test('returns null when properties block missing', () async {
      final fake = _FakeHttp(const {'/REST/rxcui/9999/properties.json': '{}'});
      final svc = RxNormApiService(httpGet: fake.call);

      expect(await svc.getDrugInfo('9999'), isNull);
    });

    test('returns null on network error', () async {
      final svc = RxNormApiService(httpGet: _throwingHttp);
      expect(await svc.getDrugInfo('11289'), isNull);
    });
  });

  group('LRU cache', () {
    test('reuses cached search response without a second HTTP hit', () async {
      final fake = _FakeHttp(const {
        '/REST/approximateTerm.json': '''
        {"approximateGroup": {"candidate": [{"rxcui": "1", "name": "x", "score": "1"}]}}
        ''',
      });
      final svc = RxNormApiService(httpGet: fake.call);

      await svc.search('foo');
      await svc.search('foo');
      await svc.search('FOO'); // case-insensitive cache key

      expect(fake.callCount, 1);
    });

    test('evicts oldest entry when cacheSize is exceeded', () async {
      final fake = _FakeHttp(const {
        '/REST/rxcui.json': '{"idGroup": {"rxnormId": ["1"]}}',
      });
      final svc = RxNormApiService(httpGet: fake.call, cacheSize: 3);

      await svc.getRxcui('a');
      await svc.getRxcui('b');
      await svc.getRxcui('c');
      // Cache full. Insert d → evict a.
      await svc.getRxcui('d');

      final snap = svc.debugCacheSnapshot();
      expect(snap.containsKey('rxcui:a'), isFalse);
      expect(snap.containsKey('rxcui:b'), isTrue);
      expect(snap.containsKey('rxcui:c'), isTrue);
      expect(snap.containsKey('rxcui:d'), isTrue);
      expect(fake.callCount, 4);
    });

    test(
      'hit re-bubbles entry to MRU position so it survives eviction',
      () async {
        final fake = _FakeHttp(const {
          '/REST/rxcui.json': '{"idGroup": {"rxnormId": ["1"]}}',
        });
        final svc = RxNormApiService(httpGet: fake.call, cacheSize: 3);

        await svc.getRxcui('a');
        await svc.getRxcui('b');
        await svc.getRxcui('c');
        // Touch 'a' so it bubbles to MRU.
        await svc.getRxcui('a');
        // Insert 'd' → should now evict 'b' (oldest after the bubble).
        await svc.getRxcui('d');

        final snap = svc.debugCacheSnapshot();
        expect(
          snap.containsKey('rxcui:a'),
          isTrue,
          reason: 'a was bubbled to MRU and should survive',
        );
        expect(
          snap.containsKey('rxcui:b'),
          isFalse,
          reason: 'b is oldest after the bubble and should be evicted',
        );
        expect(snap.containsKey('rxcui:c'), isTrue);
        expect(snap.containsKey('rxcui:d'), isTrue);
      },
    );
  });

  group('rate limiter', () {
    test(
      'throttles when requestsPerSecond cap is reached in 1s window',
      () async {
        // Set cap to 3 to keep the test fast — the throttle code path is
        // independent of the actual numeric value.
        final fake = _FakeHttp(const {
          '/REST/rxcui.json': '{"idGroup": {"rxnormId": ["1"]}}',
        });
        final svc = RxNormApiService(
          httpGet: fake.call,
          requestsPerSecond: 3,
          cacheSize: 100, // big enough that no eviction happens
        );

        final stopwatch = Stopwatch()..start();
        // 4 distinct queries to bypass the cache; the 4th must sleep
        // until the 1-second window slides forward.
        await svc.getRxcui('a');
        await svc.getRxcui('b');
        await svc.getRxcui('c');
        await svc.getRxcui('d');
        stopwatch.stop();

        expect(
          stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(900),
          reason: '4th request should have slept ~1s for the window',
        );
        expect(fake.callCount, 4);
      },
    );
  });

  group('offlineDrugClasses', () {
    test('returns alphabetically sorted ids from the bundled DB', () async {
      final db = InteractionDatabase.memory();
      addTearDown(db.close);

      // Seed the in-memory DB with a few class rows.
      await db
          .into(db.drugClassMap)
          .insert(
            DrugClassMapCompanion.insert(
              classId: 'class:statins',
              className: 'HMG-CoA Reductase Inhibitors',
              drugRxcuisJson: '[]',
              source: 'rxclass',
              lastUpdated: '2026-01-01',
            ),
          );
      await db
          .into(db.drugClassMap)
          .insert(
            DrugClassMapCompanion.insert(
              classId: 'class:ace_inhibitors',
              className: 'ACE Inhibitors',
              drugRxcuisJson: '[]',
              source: 'rxclass',
              lastUpdated: '2026-01-01',
            ),
          );
      await db
          .into(db.drugClassMap)
          .insert(
            DrugClassMapCompanion.insert(
              classId: 'class:beta_blockers',
              className: 'Beta Blockers',
              drugRxcuisJson: '[]',
              source: 'rxclass',
              lastUpdated: '2026-01-01',
            ),
          );

      final svc = RxNormApiService(httpGet: _throwingHttp, offlineDb: db);

      final ids = await svc.offlineDrugClasses();
      expect(ids, [
        'class:ace_inhibitors',
        'class:beta_blockers',
        'class:statins',
      ]);
    });

    test('returns empty list when no offlineDb is configured', () async {
      final svc = RxNormApiService(httpGet: _throwingHttp);
      expect(await svc.offlineDrugClasses(), isEmpty);
    });
  });

  group('caching across RPCs', () {
    test('different RPCs use independent cache namespaces', () async {
      final fake = _FakeHttp(const {
        '/REST/rxcui.json': '{"idGroup": {"rxnormId": ["1"]}}',
        '/REST/approximateTerm.json':
            '{"approximateGroup": {"candidate": [{"rxcui": "1", "name": "x", "score": "1"}]}}',
      });
      final svc = RxNormApiService(httpGet: fake.call);

      await svc.getRxcui('foo');
      await svc.search('foo');
      await svc.getRxcui('foo'); // cached
      await svc.search('foo'); // cached

      expect(fake.callCount, 2);
    });
  });
}
