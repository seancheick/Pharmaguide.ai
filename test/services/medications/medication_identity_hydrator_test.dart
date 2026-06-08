import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/medications/medication_identity_hydrator.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';
import 'package:pharmaguide/services/medications/rxnorm_api_service.dart';

class _FakeHttp {
  _FakeHttp(this.responses);

  final Map<String, String> responses;

  Future<String> call(Uri url) async {
    final key = '${url.path}?${url.query}';
    final byFull = responses[key];
    if (byFull != null) return byFull;
    final byPath = responses[url.path];
    if (byPath != null) return byPath;
    throw StateError('No fake response for $key');
  }
}

void main() {
  group('MedicationIdentitySnapshot', () {
    test('classifies identity coverage from saved medication fields', () {
      expect(
        const MedicationIdentitySnapshot(
          name: 'Offline class',
          drugClassIds: ['class:statins'],
        ).status,
        MedicationIdentityStatus.classOnly,
      );
      expect(
        const MedicationIdentitySnapshot(name: 'Exact', rxcui: '123').status,
        MedicationIdentityStatus.exactOnly,
      );
      expect(
        const MedicationIdentitySnapshot(
          name: 'Partial',
          rxcui: '123',
          genericRxcui: '456',
        ).status,
        MedicationIdentityStatus.partial,
      );
      expect(
        const MedicationIdentitySnapshot(
          name: 'Complete',
          rxcui: '123',
          genericRxcui: '456',
          drugClassIds: ['class:ace_inhibitors'],
        ).status,
        MedicationIdentityStatus.complete,
      );
    });
  });

  group('MedicationIdentityHydrator', () {
    test(
      'rehydrates exact-only saved medication with generic and classes',
      () async {
        final userDb = UserDatabase.memory();
        addTearDown(userDb.close);

        await userDb.addToStack(
          UserStacksLocalCompanion.insert(
            id: 'med_xenical',
            type: const Value('medication'),
            name: 'Xenical',
            rxcui: const Value('312962'),
          ),
        );

        final fake = _FakeHttp(const {
          '/REST/rxcui/312962/related.json?tty=IN': '''
        {
          "relatedGroup": {
            "conceptGroup": [
              {
                "tty": "IN",
                "conceptProperties": [
                  {"rxcui": "37925", "name": "orlistat"}
                ]
              }
            ]
          }
        }
        ''',
          '/REST/rxclass/class/byRxcui.json?rxcui=312962&relaSource=ATC': '''
        {
          "rxclassDrugInfoList": {
            "rxclassDrugInfo": [
              {
                "rxclassMinConceptItem": {
                  "className": "Anti-Obesity Agents"
                }
              }
            ]
          }
        }
        ''',
          '/REST/rxclass/class/byRxcui.json?rxcui=312962&relaSource=MEDRT': '''
        {"rxclassDrugInfoList": {"rxclassDrugInfo": []}}
        ''',
        });
        final hydrator = MedicationIdentityHydrator(
          userDb: userDb,
          rxNorm: RxNormApiService(httpGet: fake.call),
        );

        expect(await hydrator.rehydrateActiveStackMedications(), 1);

        final row = (await userDb.getActiveStack()).single;
        expect(row.genericRxcui, '37925');
        expect(row.drugClassesCol, isNotNull);
        expect(
          jsonDecode(row.drugClassesCol!) as List,
          contains('class:anti_obesity_agents'),
        );
        expect(
          MedicationIdentitySnapshot.fromStackRow(row).status,
          MedicationIdentityStatus.complete,
        );
      },
    );

    test(
      'uses bundled class map when RxNorm class endpoints are empty',
      () async {
        final userDb = UserDatabase.memory();
        final interactionDb = InteractionDatabase.memory();
        addTearDown(userDb.close);
        addTearDown(interactionDb.close);

        await userDb.addToStack(
          UserStacksLocalCompanion.insert(
            id: 'med_lisinopril',
            type: const Value('medication'),
            name: 'Lisinopril',
            rxcui: const Value('29046'),
          ),
        );
        await interactionDb
            .into(interactionDb.drugClassMap)
            .insert(
              DrugClassMapCompanion.insert(
                classId: 'class:ace_inhibitors',
                className: 'ACE inhibitors',
                drugRxcuisJson: '["29046"]',
                source: 'manual',
                lastUpdated: '2026-06-08',
              ),
            );

        final fake = _FakeHttp(const {
          '/REST/rxcui/29046/related.json?tty=IN':
              '{"relatedGroup": {"conceptGroup": []}}',
          '/REST/rxclass/class/byRxcui.json?rxcui=29046&relaSource=ATC':
              '{"rxclassDrugInfoList": {"rxclassDrugInfo": []}}',
          '/REST/rxclass/class/byRxcui.json?rxcui=29046&relaSource=MEDRT':
              '{"rxclassDrugInfoList": {"rxclassDrugInfo": []}}',
        });
        final hydrator = MedicationIdentityHydrator(
          userDb: userDb,
          rxNorm: RxNormApiService(
            httpGet: fake.call,
            offlineDb: interactionDb,
          ),
        );

        expect(await hydrator.rehydrateActiveStackMedications(), 1);
        final row = (await userDb.getActiveStack()).single;
        expect(jsonDecode(row.drugClassesCol!) as List, [
          'class:ace_inhibitors',
        ]);
      },
    );
  });
}
