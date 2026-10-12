// App-side golden for the engine portability spike.
//
// Runs the fixture through the REAL app path (Riverpod providers
// `safetyCheckForAddProvider` + `depletionReportProvider`, real Drift
// InteractionDatabase over a temp copy of the FULL bundled
// interaction_db.sqlite, real reference-data repository via rootBundle) and
// asserts the findings equal the server-side spike output in
// tool/engine_spike/golden/spike_findings.json (written by build.sh from the
// Dart VM run, which build.sh also proves byte-identical to AOT/Deno/Node).
//
// Run: flutter test tool/engine_spike/test/golden_parity_test.dart
// Needs: assets/db/interaction_db.sqlite (gitignored) and `make gen`.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';

import '../lib/findings_codec.dart';

const _fx = 'tool/engine_spike/fixtures';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app provider path == server-side spike findings', () async {
    final stackFx =
        jsonDecode(File('$_fx/stack.json').readAsStringSync())
            as Map<String, dynamic>;
    final products =
        jsonDecode(File('$_fx/products.json').readAsStringSync()) as List;

    final coreDb = CoreDatabase.memory();
    for (final p in products.cast<Map<String, dynamic>>()) {
      await coreDb
          .into(coreDb.productsCore)
          .insert(
            ProductsCoreCompanion.insert(
              dsldId: p['dsld_id'].toString(),
              productName: p['product_name'] as String,
              productStatus: const Value('active'),
              keyIngredientTags: Value(p['key_ingredient_tags'] as String?),
              ingredientFingerprint: Value(
                p['ingredient_fingerprint'] as String?,
              ),
              containsStimulants: Value(p['contains_stimulants'] as int?),
              containsSedatives: Value(p['contains_sedatives'] as int?),
              containsBloodThinners: Value(
                p['contains_blood_thinners'] as int?,
              ),
              mappedCoverage: Value((p['mapped_coverage'] as num?)?.toDouble()),
              exportVersion: 'spike',
              exportedAt: '2026-10-12T00:00:00Z',
            ),
          );
    }

    // Full real DB (not the fixture subset), on a temp copy so Drift can
    // never touch the bundled asset.
    final tmp = Directory.systemTemp.createTempSync('engine_spike_');
    final dbCopy = File('assets/db/interaction_db.sqlite')
        .copySync('${tmp.path}/interaction_db.sqlite');
    final interactionDb = InteractionDatabase(dbCopy);
    final userDb = UserDatabase.memory();
    addTearDown(() async {
      await coreDb.close();
      await interactionDb.close();
      await userDb.close();
      tmp.deleteSync(recursive: true);
    });

    final epoch = DateTime.utc(2026, 10, 12);
    final stack = [
      for (final e in (stackFx['stack'] as List).cast<Map<String, dynamic>>())
        UserStacksLocalData(
          id: e['id'] as String,
          type: e['type'] as String,
          name: e['name'] as String,
          dsldId: e['dsld_id'] as String?,
          rxcui: e['rxcui'] as String?,
          ingredientKeys: e['ingredient_keys'] as String?,
          drugClassesCol: e['drug_classes'] as String?,
          genericRxcui: e['generic_rxcui'] as String?,
          addedAt: epoch,
          clientUpdatedAt: epoch,
        ),
    ];

    final container = ProviderContainer(
      overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        interactionDatabaseProvider.overrideWithValue(interactionDb),
        userDatabaseProvider.overrideWithValue(userDb),
        activeStackProvider.overrideWith((ref) async => stack),
        // No detail blobs server-side in the spike; the app path then marks
        // dose-dependent checks incomplete, exactly as the spike does.
        detailBlobProvider.overrideWith((ref, dsldId) async => null),
      ],
    );
    addTearDown(container.dispose);

    final candidate = stackFx['candidate_dsld_id'] as String;
    final pre = await container.read(
      safetyCheckForAddProvider(candidate).future,
    );
    final dep = await container.read(depletionReportProvider.future);

    final app = jsonDecode(
      jsonEncode(
        encodeFindings(
          preAddResults: pre.results,
          preAddChecksIncomplete: pre.checksIncomplete,
          depletionStatus: dep.status.name,
          depletions: dep.matches,
        ),
      ),
    );
    final golden = jsonDecode(
      File('tool/engine_spike/golden/spike_findings.json').readAsStringSync(),
    );

    // Print a compact summary for the spike report.
    final results = (app['pre_add']['results'] as List)
        .map((r) => '${r['id']}:${r['severity']}:${r['evidence_level']}')
        .join(', ');
    // ignore: avoid_print
    print('APP pre_add=[$results] depletion=${app['depletion']['matches'].length}');

    expect(app, equals(golden));
  });
}
