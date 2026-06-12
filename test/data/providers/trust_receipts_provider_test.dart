// Tests for trustReceiptsProvider — live counts for the Trust Receipts
// sheet, gathered from in-memory CoreDatabase / InteractionDatabase
// fixtures.
//
// Run: flutter test test/data/providers/trust_receipts_provider_test.dart

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/trust_receipts_provider.dart';

ResearchPairsCompanion _researchPair(String pairId) {
  return ResearchPairsCompanion.insert(
    pairId: pairId,
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
    paperCount: 4,
    humanStudyCount: 3,
    clinicalStudyCount: 2,
    topSentencesJson: jsonEncode([
      {'pmid': '12345', 'sentence': 'Vitamin K and warfarin co-occurred.'},
    ]),
    topPmidsJson: jsonEncode(['12345']),
    latestPaperYear: const Value(2024),
    lastUpdated: '2026-05-17T00:00:00Z',
  );
}

void main() {
  late CoreDatabase coreDb;
  late InteractionDatabase interactionDb;
  late ProviderContainer container;

  setUp(() {
    coreDb = CoreDatabase.memory();
    interactionDb = InteractionDatabase.memory();
    container = ProviderContainer(
      overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        interactionDatabaseProvider.overrideWithValue(interactionDb),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await coreDb.close();
    await interactionDb.close();
  });

  test('gathers live counts from the databases', () async {
    // The in-memory CoreDatabase has the Drift schema but not the
    // pipeline's raw export_manifest table — create it like the
    // pipeline does and seed generated_at.
    await coreDb.customStatement(
      'CREATE TABLE export_manifest (key TEXT PRIMARY KEY, value TEXT)',
    );
    await coreDb.customStatement(
      "INSERT INTO export_manifest (key, value) "
      "VALUES ('generated_at', '2026-06-12T09:07:03.154167+00:00')",
    );
    await interactionDb
        .into(interactionDb.researchPairs)
        .insert(_researchPair('pair_1'));
    await interactionDb
        .into(interactionDb.researchPairs)
        .insert(_researchPair('pair_2'));

    final data = await container.read(trustReceiptsProvider.future);

    expect(data.productCount, 0); // empty products_core counts as 0, not null
    expect(data.interactionCount, 0);
    expect(data.researchPairCount, 2);
    expect(data.catalogGeneratedAt, isNotNull);
    expect(data.catalogGeneratedAt!.toUtc().year, 2026);
    expect(data.catalogGeneratedAt!.toUtc().month, 6);
  });

  test(
    'interactionCount counts only hand-reviewed rows — suppai excluded',
    () async {
      InteractionsCompanion row(String id, String source) {
        return InteractionsCompanion.insert(
          id: id,
          agent1Type: 'drug',
          agent1Name: 'Warfarin',
          agent1Id: '11289',
          agent2Type: 'supplement',
          agent2Name: 'Vitamin K',
          agent2Id: 'vitamin_k',
          severity: 'caution',
          mechanism: 'test mechanism',
          management: 'test management',
          sourceUrlsJson: '[]',
          sourcePmidsJson: '[]',
          typeAuthored: 'Med-Sup',
          source: source,
          provenance: 'nih_ods',
          versionAdded: '1.0.0',
          versionLastModified: '1.0.0',
          lastUpdated: '2026-06-12T00:00:00Z',
        );
      }

      await interactionDb
          .into(interactionDb.interactions)
          .insert(row('I1', 'curated'));
      await interactionDb
          .into(interactionDb.interactions)
          .insert(row('I2', 'suppai'));

      final data = await container.read(trustReceiptsProvider.future);

      // "Hand-reviewed, evidence-graded" must never count
      // machine-extracted suppai rows.
      expect(data.interactionCount, 1);
    },
  );

  test('a missing manifest table nulls only its own field', () async {
    // No export_manifest table at all — readManifestValue throws, the
    // guard catches it, and only catalogGeneratedAt comes back null.
    final data = await container.read(trustReceiptsProvider.future);

    expect(data.catalogGeneratedAt, isNull);
    expect(data.productCount, 0);
    expect(data.interactionCount, 0);
    expect(data.researchPairCount, 0);
  });

  test('unparseable generated_at yields null date, never a fake one', () async {
    await coreDb.customStatement(
      'CREATE TABLE export_manifest (key TEXT PRIMARY KEY, value TEXT)',
    );
    await coreDb.customStatement(
      "INSERT INTO export_manifest (key, value) "
      "VALUES ('generated_at', 'not-a-date')",
    );

    final data = await container.read(trustReceiptsProvider.future);

    expect(data.catalogGeneratedAt, isNull);
  });
}
