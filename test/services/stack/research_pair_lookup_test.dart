import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/stack/research_pair_lookup.dart';

ResearchPairsCompanion _researchPair({
  required String pairId,
  required String canonicalId,
  required String rxcui,
  required int paperCount,
  String entityAName = 'Vitamin K',
  String entityBName = 'Warfarin',
}) {
  return ResearchPairsCompanion.insert(
    pairId: pairId,
    cuiA: 'C0042878',
    cuiB: 'C0043031',
    entityAName: entityAName,
    entityBName: entityBName,
    entityAType: 'supplement',
    entityBType: 'drug',
    canonicalIdA: Value(canonicalId),
    canonicalIdB: const Value(null),
    rxcuiA: const Value(null),
    rxcuiB: Value(rxcui),
    paperCount: paperCount,
    humanStudyCount: 3,
    clinicalStudyCount: 2,
    topSentencesJson: jsonEncode([
      {
        'pmid': '12345',
        'sentence': 'Vitamin K and warfarin appeared together in patients.',
      },
    ]),
    topPmidsJson: jsonEncode(['12345']),
    latestPaperYear: const Value(2024),
    lastUpdated: '2026-05-17T00:00:00Z',
  );
}

UserStacksLocalData _medication({
  String? rxcui,
  String? genericRxcui,
  List<String> ingredientRxcuis = const <String>[],
}) {
  return UserStacksLocalData(
    id: 'med',
    type: 'medication',
    name: 'Warfarin',
    dsldId: null,
    rxcui: rxcui,
    ingredientKeys: null,
    drugClassesCol: null,
    genericRxcui: genericRxcui,
    ingredientRxcuisCol: ingredientRxcuis.isEmpty
        ? null
        : jsonEncode(ingredientRxcuis),
    dosage: null,
    frequency: null,
    addedAt: DateTime(2026),
    clientUpdatedAt: DateTime(2026),
    deletedAt: null,
    syncedAt: null,
  );
}

void main() {
  late InteractionDatabase db;

  setUp(() {
    db = InteractionDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  test('looks up product evidence by canonical id', () async {
    await db
        .into(db.researchPairs)
        .insert(
          _researchPair(
            pairId: 'C0042878-C0043031',
            canonicalId: 'vitamin_k',
            rxcui: '11289',
            paperCount: 10,
          ),
        );

    final results = await ResearchPairLookup(
      db,
    ).lookupForProduct(canonicalIds: const ['vitamin_k']);

    expect(results, hasLength(1));
    expect(results.single.pairLabel, 'Vitamin K + Warfarin');
    expect(results.single.topPmids, ['12345']);
  });

  test('prioritizes medication-context research evidence', () async {
    await db
        .into(db.researchPairs)
        .insert(
          _researchPair(
            pairId: 'C0042878-C0043031',
            canonicalId: 'vitamin_k',
            rxcui: '11289',
            paperCount: 2,
          ),
        );
    await db
        .into(db.researchPairs)
        .insert(
          _researchPair(
            pairId: 'C0042878-C9999999',
            canonicalId: 'vitamin_k',
            rxcui: '999',
            paperCount: 99,
            entityBName: 'Unrelated drug',
          ),
        );

    final results = await ResearchPairLookup(db).lookupForProduct(
      canonicalIds: const ['vitamin_k'],
      stack: [_medication(rxcui: '11289')],
    );

    expect(results.first.pairId, 'C0042878-C0043031');
    expect(results.first.involvesRxcui('11289'), isTrue);
  });

  test('matches generic and ingredient medication RxCUIs', () async {
    await db
        .into(db.researchPairs)
        .insert(
          _researchPair(
            pairId: 'C0042878-C0043031',
            canonicalId: 'vitamin_k',
            rxcui: '11289',
            paperCount: 5,
          ),
        );

    final results = await ResearchPairLookup(db).lookupForProduct(
      canonicalIds: const ['vitamin_k'],
      stack: [
        _medication(genericRxcui: '0', ingredientRxcuis: ['11289']),
      ],
    );

    expect(results.single.involvesRxcui('11289'), isTrue);
  });

  test(
    'does not convert Tier 2 evidence into severity-bearing results',
    () async {
      await db
          .into(db.researchPairs)
          .insert(
            _researchPair(
              pairId: 'C0042878-C0043031',
              canonicalId: 'vitamin_k',
              rxcui: '11289',
              paperCount: 10,
            ),
          );

      final evidence = await ResearchPairLookup(
        db,
      ).lookupForProduct(canonicalIds: const ['vitamin_k']);

      expect(evidence, hasLength(1));
      expect(evidence.single, isNot(isA<InteractionResult>()));
    },
  );

  test('drops malformed or display-empty evidence rows', () async {
    await db
        .into(db.researchPairs)
        .insert(
          ResearchPairsCompanion.insert(
            pairId: 'C0042878-C0043031',
            cuiA: 'C0042878',
            cuiB: 'C0043031',
            entityAName: 'Vitamin K',
            entityBName: 'Warfarin',
            entityAType: 'supplement',
            entityBType: 'drug',
            canonicalIdA: const Value('vitamin_k'),
            canonicalIdB: const Value(null),
            rxcuiA: const Value(null),
            rxcuiB: const Value('11289'),
            paperCount: 10,
            humanStudyCount: 3,
            clinicalStudyCount: 2,
            topSentencesJson: 'not-json',
            topPmidsJson: '[]',
            lastUpdated: '2026-05-17T00:00:00Z',
          ),
        );

    final evidence = await ResearchPairLookup(
      db,
    ).lookupForProduct(canonicalIds: const ['vitamin_k']);

    expect(evidence, isEmpty);
  });
}
