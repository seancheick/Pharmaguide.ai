// A release can never leave the phone worse off than it started.
//
// These run the real store against real SQLite files. A new ReleaseStore over
// the same folder is a relaunch; what it reads back is only what reached disk.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/release_store.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'release_fixtures.dart';

const _bundledCatalog = '2026.01.01.000000';
const _bundledRules = '1.0.10';
const _updateCatalog = '2026.03.01.000000';
const _updateRules = '1.0.11';

void main() {
  late Directory workspace;
  late Directory documents;
  late FakeReleaseBundle bundle;
  final open = <ReleaseGeneration>[];

  setUp(() async {
    await CrashReportingService().initialize();
    CrashReportingService().clearBuffersForTest();
    workspace = await Directory.systemTemp.createTemp('release-store');
    documents = Directory(p.join(workspace.path, 'documents'))..createSync();
    bundle = await FakeReleaseBundle.build(
      workspace,
      catalogVersion: _bundledCatalog,
      rulesVersion: _bundledRules,
    );
  });

  tearDown(() async {
    for (final generation in open) {
      try {
        await generation.close();
      } on Object {
        // Already closed.
      }
    }
    open.clear();
    await workspace.delete(recursive: true);
  });

  ReleaseStore store({
    FakeReleaseBundle? withBundle,
    Future<void> Function(ReleaseStep)? onStep,
  }) => ReleaseStore(
    documents: documents,
    bundle: withBundle ?? bundle,
    onStep: onStep,
  );

  Future<ReleaseGeneration> boot(ReleaseStore s) async {
    final generation = await s.open();
    open.add(generation);
    return generation;
  }

  Future<ReleaseCandidate> candidate({
    int sequence = 1,
    String catalogVersion = _updateCatalog,
    String? rulesVersion = _updateRules,
    String severity = 'contraindicated',
    String? stagedName,
  }) async {
    final name = stagedName ?? 's$sequence';
    final catalogFile = File(p.join(workspace.path, '$name.db'));
    await buildCatalog(catalogFile.path, version: catalogVersion);
    File? rulesFile;
    if (rulesVersion != null) {
      rulesFile = File(p.join(workspace.path, '$name.sqlite'));
      await buildRules(
        rulesFile.path,
        version: rulesVersion,
        severity: severity,
      );
    }
    return ReleaseCandidate(
      sequence: sequence,
      catalogVersion: catalogVersion,
      catalogSha256: sha256.convert(catalogFile.readAsBytesSync()).toString(),
      minRulesVersion: '1.0.0',
      stagedCatalog: catalogFile,
      stagedRules: rulesFile,
      rulesVersion: rulesVersion,
      rulesSha256: rulesFile == null
          ? null
          : sha256.convert(rulesFile.readAsBytesSync()).toString(),
    );
  }

  Future<ReleaseGeneration> activate(
    ReleaseStore s,
    ReleaseCandidate c, {
    ReleaseStackData? stackData,
  }) async {
    final result = await s.activate(c, stackData: stackData);
    expect(result, isA<ReleaseActivated>(), reason: '$result');
    final generation = (result as ReleaseActivated).generation;
    open.add(generation);
    return generation;
  }

  /// One complete generation: the catalog and rules that were released
  /// together, whichever pair that is.
  Future<void> expectPair(
    ReleaseGeneration generation, {
    required String catalog,
    required String rules,
  }) async {
    expect(await generation.core.validateCatalogSnapshot(), catalog);
    expect((await generation.rules!.getMetadata()).interactionDbVersion, rules);
    expect(generation.record.catalogVersion, catalog);
    expect(generation.record.rulesVersion, rules);
  }

  Map<String, dynamic> pointerOnDisk() =>
      jsonDecode(
            File(
              p.join(documents.path, 'releases', 'active.json'),
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  List<String> foldersOnDisk() => Directory(p.join(documents.path, 'releases'))
      .listSync()
      .whereType<Directory>()
      .map((d) => p.basename(d.path))
      .where((name) => name != 'staging')
      .toList();

  group('first launch', () {
    test('the bundled pair becomes one complete, confirmed release', () async {
      final generation = await boot(store());
      await expectPair(
        generation,
        catalog: _bundledCatalog,
        rules: _bundledRules,
      );
      expect(pointerOnDisk()['active'], generation.record.id);
      expect(pointerOnDisk()['confirmed'], isTrue);
    });

    test('with a broken bundled catalog, boot throws rather than limps, and '
        'an update can still install a release', () async {
      final broken = FakeReleaseBundle(
        catalog: Uint8List.fromList(utf8.encode('not a database')),
        rules: bundle.rules,
        catalogVersion: _bundledCatalog,
        rulesVersion: _bundledRules,
      );
      final s = store(withBundle: broken);
      await expectLater(s.open(), throwsA(anything));

      final c = await candidate(rulesVersion: null);
      final generation = await activate(s, c);
      await expectPair(
        generation,
        catalog: _updateCatalog,
        rules: _bundledRules,
      );
    });

    test('with broken bundled rules, the catalog still opens and interaction '
        'checks are unavailable', () async {
      final broken = FakeReleaseBundle(
        catalog: bundle.catalog,
        rules: Uint8List.fromList(utf8.encode('not a database')),
        catalogVersion: _bundledCatalog,
        rulesVersion: _bundledRules,
      );
      final generation = await boot(store(withBundle: broken));
      expect(generation.rules, isNull);
      expect(generation.rulesWithheld, isFalse);
      expect(await generation.core.validateCatalogSnapshot(), _bundledCatalog);
    });
  });

  group('immutable files', () {
    test('reading a release leaves every byte unchanged, and it cannot be '
        'written', () async {
      final generation = await boot(store());
      final folder = p.join(documents.path, 'releases', generation.record.id);
      final catalog = File(p.join(folder, 'catalog.db'));
      final rules = File(p.join(folder, 'rules.sqlite'));
      final before = [
        sha256.convert(catalog.readAsBytesSync()).toString(),
        sha256.convert(rules.readAsBytesSync()).toString(),
      ];

      await generation.core.countProducts();
      await severityIn(generation.rules);
      await expectLater(
        generation.core.customStatement(
          "UPDATE products_core SET product_name = 'x'",
        ),
        throwsA(anything),
      );
      await expectLater(
        generation.rules!.customStatement(
          "UPDATE interactions SET severity = 'x'",
        ),
        throwsA(anything),
      );
      await generation.close();
      open.remove(generation);

      final relaunched = await boot(store());
      await relaunched.core.countProducts();
      await relaunched.close();
      open.remove(relaunched);

      expect(sha256.convert(catalog.readAsBytesSync()).toString(), before[0]);
      expect(sha256.convert(rules.readAsBytesSync()).toString(), before[1]);
      expect(File('${catalog.path}-journal').existsSync(), isFalse);
      expect(File('${catalog.path}-wal').existsSync(), isFalse);
    });

    test('open-time columns and indexes are in the prepared file', () async {
      final generation = await boot(store());
      final folder = p.join(documents.path, 'releases', generation.record.id);
      final db = raw.sqlite3.open(p.join(folder, 'catalog.db'));
      addTearDown(db.close);
      final columns = db
          .select('PRAGMA table_info(products_core)')
          .map((row) => row['name'] as String);
      expect(columns, contains('supplement_type'));
      final indexes = db
          .select("SELECT name FROM sqlite_master WHERE type = 'index'")
          .map((row) => row['name'] as String);
      expect(indexes, contains('idx_core_upc_normalized'));
    });

    test(
      'changing the open-time work requires raising kReleasePreparation',
      () {
        final core = CoreDatabase.memory();
        final rules = InteractionDatabase.memory();
        addTearDown(core.close);
        addTearDown(rules.close);
        final fingerprint = sha256
            .convert(
              utf8.encode(
                jsonEncode([
                  CoreDatabase.compatColumns,
                  CoreDatabase.appIndexStatements,
                  InteractionDatabase.appIndexStatements,
                  core.schemaVersion,
                  rules.schemaVersion,
                ]),
              ),
            )
            .toString();
        expect(
          (kReleasePreparation, fingerprint),
          (1, _preparationFingerprint),
          reason:
              'The open-time work changed. Raise kReleasePreparation so phones '
              'rebuild their prepared files, then update this pin.',
        );
      },
    );

    test('a folder from an older build is rebuilt from the same files, and '
        'the old folder is not written', () async {
      final s = store();
      await boot(s);
      final generation = await activate(s, await candidate());
      final id = generation.record.id;
      final folder = p.join(documents.path, 'releases', id);
      final record = File(p.join(folder, 'release.json'));
      final json = jsonDecode(record.readAsStringSync()) as Map;
      final oldId = id.replaceFirst('_p1', '_p0');
      json['preparation'] = 0;
      json['id'] = oldId;
      await generation.close();
      open.remove(generation);
      record.writeAsStringSync(jsonEncode(json));
      final oldFolder = p.join(documents.path, 'releases', oldId);
      Directory(folder).renameSync(oldFolder);
      final pointerFile = File(
        p.join(documents.path, 'releases', 'active.json'),
      );
      final pointer = pointerOnDisk()..['active'] = oldId;
      pointerFile.writeAsStringSync(jsonEncode(pointer));
      final oldHash = sha256
          .convert(File(p.join(oldFolder, 'catalog.db')).readAsBytesSync())
          .toString();

      final rebuilt = await boot(store());
      expect(rebuilt.record.id, id);
      expect(rebuilt.record.preparation, kReleasePreparation);
      await expectPair(rebuilt, catalog: _updateCatalog, rules: _updateRules);
      expect(
        sha256
            .convert(File(p.join(oldFolder, 'catalog.db')).readAsBytesSync())
            .toString(),
        oldHash,
      );
    });
  });

  group('activation', () {
    test('a valid release activates both files together', () async {
      final s = store();
      final old = await boot(s);
      final generation = await activate(s, await candidate());
      await expectPair(
        generation,
        catalog: _updateCatalog,
        rules: _updateRules,
      );
      expect(await severityIn(generation.rules), 'contraindicated');
      expect(pointerOnDisk()['previous'], old.record.id);
      expect(pointerOnDisk()['confirmed'], isTrue);
    });

    test(
      'a running check finishes on the old release during a switch',
      () async {
        final s = store();
        final old = await boot(s);
        // A check that started before the update, and reads again after it.
        expect(await severityIn(old.rules), 'caution');
        final generation = await activate(s, await candidate());

        expect(await severityIn(old.rules), 'caution');
        expect(await old.core.countProducts(), 1);
        expect(await severityIn(generation.rules), 'contraindicated');
      },
    );

    test('a catalog that fails validation never activates and the last good '
        'pair stays', () async {
      final s = store();
      final old = await boot(s);
      final c = await candidate();
      final bad = File(p.join(workspace.path, 'empty.db'));
      await buildCatalog(bad.path, version: _updateCatalog, empty: true);

      final result = await s.activate(
        ReleaseCandidate(
          sequence: c.sequence,
          catalogVersion: c.catalogVersion,
          catalogSha256: c.catalogSha256,
          minRulesVersion: c.minRulesVersion,
          stagedCatalog: bad,
          stagedRules: c.stagedRules,
          rulesVersion: c.rulesVersion,
          rulesSha256: c.rulesSha256,
        ),
      );

      expect(result, isA<ReleaseNotActivated>());
      expect(pointerOnDisk()['active'], old.record.id);
      expect(await old.core.countProducts(), 1);
      await expectPair(
        await boot(store()),
        catalog: _bundledCatalog,
        rules: _bundledRules,
      );
    });

    test(
      'a catalog whose version disagrees with its release never activates',
      () async {
        final s = store();
        final old = await boot(s);
        final c = await candidate();
        final wrong = File(p.join(workspace.path, 'wrong.db'));
        await buildCatalog(wrong.path, version: '2026.04.04.000000');

        final result = await s.activate(
          ReleaseCandidate(
            sequence: c.sequence,
            catalogVersion: c.catalogVersion,
            catalogSha256: c.catalogSha256,
            minRulesVersion: c.minRulesVersion,
            stagedCatalog: wrong,
            stagedRules: c.stagedRules,
            rulesVersion: c.rulesVersion,
            rulesSha256: c.rulesSha256,
          ),
        );
        expect(result, isA<ReleaseNotActivated>());
        expect(pointerOnDisk()['active'], old.record.id);
      },
    );

    test('rules this build cannot read never activate', () async {
      final s = store();
      final old = await boot(s);
      final c = await candidate();
      final future = File(p.join(workspace.path, 'future.sqlite'));
      await buildRules(
        future.path,
        version: _updateRules,
        schemaVersion: '5.0.0',
      );

      final result = await s.activate(
        ReleaseCandidate(
          sequence: c.sequence,
          catalogVersion: c.catalogVersion,
          catalogSha256: c.catalogSha256,
          minRulesVersion: c.minRulesVersion,
          stagedCatalog: c.stagedCatalog,
          stagedRules: future,
          rulesVersion: c.rulesVersion,
          rulesSha256: c.rulesSha256,
        ),
      );
      expect(result, isA<ReleaseNotActivated>());
      expect(pointerOnDisk()['active'], old.record.id);
    });

    test('a catalog-only release keeps the phone\'s rules', () async {
      final s = store();
      await boot(s);
      final generation = await activate(s, await candidate(rulesVersion: null));
      await expectPair(
        generation,
        catalog: _updateCatalog,
        rules: _bundledRules,
      );
    });

    test('a rules-only release reuses the catalog on disk', () async {
      final s = store();
      final old = await boot(s);
      final generation = await activate(
        s,
        ReleaseCandidate(
          sequence: 2,
          catalogVersion: old.record.catalogVersion,
          catalogSha256: old.record.catalogSha256,
          minRulesVersion: '1.0.0',
          stagedRules: (await candidate()).stagedRules,
          rulesVersion: _updateRules,
        ),
      );
      await expectPair(
        generation,
        catalog: _bundledCatalog,
        rules: _updateRules,
      );
      expect(await severityIn(generation.rules), 'contraindicated');
    });

    test(
      'a stack blob that cannot be fetched leaves the phone on its release',
      () async {
        final s = store();
        final old = await boot(s);
        final result = await s.activate(
          await candidate(),
          stackData: (candidateDb) async {
            expect(
              await candidateDb.validateCatalogSnapshot(),
              _updateCatalog,
              reason: 'stack data is fetched for the new catalog',
            );
            throw StateError('offline');
          },
        );
        expect(result, isA<ReleaseNotActivated>());
        expect(pointerOnDisk()['active'], old.record.id);
        expect(await old.core.countProducts(), 1);
      },
    );

    test(
      'stack blobs are stored only once everything else succeeded',
      () async {
        final s = store();
        await boot(s);
        final order = <String>[];
        final result = await s.activate(
          await candidate(),
          stackData: (_) async {
            order.add('fetched');
            return () async {
              order.add('stored');
              expect(foldersOnDisk(), hasLength(2));
            };
          },
        );
        expect(result, isA<ReleaseActivated>());
        open.add((result as ReleaseActivated).generation);
        expect(order, ['fetched', 'stored']);
      },
    );
  });

  group('a crash at each activation step leaves one complete generation', () {
    for (final step in ReleaseStep.values) {
      test('$step', () async {
        final first = store();
        await boot(first);
        final crashing = store(
          onStep: (at) async {
            if (at == step) throw SimulatedReleaseCrash(at);
          },
        );
        await boot(crashing);
        await expectLater(
          crashing.activate(
            await candidate(),
            stackData: (_) async => () async {},
          ),
          throwsA(isA<SimulatedReleaseCrash>()),
        );

        final relaunched = await boot(store());
        final afterSwap = const {
          ReleaseStep.openNew,
          ReleaseStep.confirm,
        }.contains(step);
        await expectPair(
          relaunched,
          catalog: afterSwap ? _updateCatalog : _bundledCatalog,
          rules: afterSwap ? _updateRules : _bundledRules,
        );
        expect(pointerOnDisk()['confirmed'], isTrue);
        expect(
          foldersOnDisk(),
          contains(relaunched.record.id),
          reason: 'the pointer names a folder that exists',
        );

        // The phone can still take the update afterwards.
        if (!afterSwap) {
          final s = store();
          await boot(s);
          await expectPair(
            await activate(s, await candidate(stagedName: 'retry')),
            catalog: _updateCatalog,
            rules: _updateRules,
          );
        }
      });
    }

    test('dying during first-launch assembly repeats it', () async {
      final crashing = store(
        onStep: (at) async {
          if (at == ReleaseStep.publishFolder) {
            throw SimulatedReleaseCrash(at);
          }
        },
      );
      await expectLater(crashing.open(), throwsA(anything));
      await expectPair(
        await boot(store()),
        catalog: _bundledCatalog,
        rules: _bundledRules,
      );
    });
  });

  group('recovery', () {
    test('a confirmed release that later fails to open returns to the '
        'previous one, and is not selected again', () async {
      final s = store();
      final old = await boot(s);
      final bad = await activate(s, await candidate());
      await bad.close();
      open.remove(bad);
      File(
        p.join(documents.path, 'releases', bad.record.id, 'catalog.db'),
      ).writeAsStringSync('torn');

      final relaunched = await boot(store());
      expect(relaunched.record.id, old.record.id);
      expect(pointerOnDisk()['refused'], contains(bad.record.id));

      final again = await boot(store());
      expect(again.record.id, old.record.id);
    });

    test('with every release damaged, the bundled pair takes over', () async {
      final s = store();
      final old = await boot(s);
      final bad = await activate(s, await candidate());
      await bad.close();
      await old.close();
      open.clear();
      for (final record in [old.record, bad.record]) {
        File(
          p.join(documents.path, 'releases', record.id, 'catalog.db'),
        ).writeAsStringSync('torn');
      }

      await expectPair(
        await boot(store()),
        catalog: _bundledCatalog,
        rules: _bundledRules,
      );
    });

    test('an invalid pointer falls back to the newest kept release', () async {
      final s = store();
      await boot(s);
      final newest = await activate(s, await candidate(sequence: 7));
      File(
        p.join(documents.path, 'releases', 'active.json'),
      ).writeAsStringSync('{broken');

      final relaunched = await boot(store());
      expect(relaunched.record.id, newest.record.id);
      expect(pointerOnDisk()['highest_sequence'], 7);
    });

    test('a missing pointer falls back the same way', () async {
      final s = store();
      await boot(s);
      final newest = await activate(s, await candidate(sequence: 7));
      File(p.join(documents.path, 'releases', 'active.json')).deleteSync();

      final relaunched = await boot(store());
      expect(relaunched.record.id, newest.record.id);
    });

    test('a pointer naming a missing folder falls back', () async {
      final s = store();
      final old = await boot(s);
      final bad = await activate(s, await candidate());
      await bad.close();
      open.remove(bad);
      Directory(
        p.join(documents.path, 'releases', bad.record.id),
      ).deleteSync(recursive: true);

      final relaunched = await boot(store());
      expect(relaunched.record.id, old.record.id);
    });

    test('retention keeps only the active and previous releases', () async {
      final s = store();
      final first = await boot(s);
      final second = await activate(s, await candidate(sequence: 2));
      final third = await activate(
        s,
        await candidate(
          sequence: 3,
          catalogVersion: '2026.04.01.000000',
          rulesVersion: '1.0.12',
        ),
      );
      expect(foldersOnDisk(), hasLength(3));

      await boot(store());
      expect(foldersOnDisk().toSet(), {second.record.id, third.record.id});
      expect(foldersOnDisk(), isNot(contains(first.record.id)));
    });

    test('a later launch never reads the bundled databases', () async {
      await boot(store());
      bundle.databaseLoads = 0;
      await boot(store());
      expect(bundle.databaseLoads, 0);
    });

    test('opening again with nothing new changes nothing', () async {
      final s = store();
      await boot(s);
      final generation = await activate(s, await candidate());
      final pointer = pointerOnDisk();
      for (var launch = 0; launch < 3; launch++) {
        final relaunched = await boot(store());
        expect(relaunched.record.id, generation.record.id);
        expect(await severityIn(relaunched.rules), 'contraindicated');
      }
      expect(pointerOnDisk()['active'], pointer['active']);
      expect(pointerOnDisk()['previous'], pointer['previous']);
    });
  });

  group('rollback', () {
    test('known-good data republished under a newer sequence wins through a '
        'real restart, on older content versions', () async {
      final s = store();
      await boot(s);
      await activate(s, await candidate(sequence: 12));

      // The correction: an older catalog and older rules, under a newer
      // sequence, with the bad versions blocked.
      final rollback = await candidate(
        sequence: 13,
        catalogVersion: '2026.02.01.000000',
        rulesVersion: '1.0.9',
        severity: 'avoid',
      );
      await s.recordVerified(
        sequence: 13,
        blockedCatalog: {_updateCatalog},
        blockedRules: {_updateRules},
      );
      await activate(s, rollback);

      final relaunched = await boot(store());
      await expectPair(
        relaunched,
        catalog: '2026.02.01.000000',
        rules: '1.0.9',
      );
      expect(await severityIn(relaunched.rules), 'avoid');
      expect(pointerOnDisk()['highest_sequence'], 13);
    });

    test('a phone that skipped several releases takes the rollback', () async {
      final s = store();
      await boot(s);
      // Never saw sequences 1 to 8.
      final generation = await activate(
        s,
        await candidate(
          sequence: 9,
          catalogVersion: '2026.02.15.000000',
          rulesVersion: '1.0.9',
          severity: 'avoid',
        ),
      );
      await expectPair(
        generation,
        catalog: '2026.02.15.000000',
        rules: '1.0.9',
      );
      expect(await severityIn(generation.rules), 'avoid');
    });

    test('an interrupted rollback finishes on the next attempt', () async {
      final s = store();
      await boot(s);
      await activate(s, await candidate(sequence: 12));

      final crashing = store(
        onStep: (at) async {
          if (at == ReleaseStep.swapPointer) throw SimulatedReleaseCrash(at);
        },
      );
      await boot(crashing);
      await expectLater(
        crashing.activate(
          await candidate(
            sequence: 13,
            catalogVersion: '2026.02.01.000000',
            rulesVersion: '1.0.9',
            stagedName: 'first-try',
          ),
        ),
        throwsA(isA<SimulatedReleaseCrash>()),
      );

      final relaunched = store();
      await expectPair(
        await boot(relaunched),
        catalog: _updateCatalog,
        rules: _updateRules,
      );
      await expectPair(
        await activate(
          relaunched,
          await candidate(
            sequence: 13,
            catalogVersion: '2026.02.01.000000',
            rulesVersion: '1.0.9',
            stagedName: 'second-try',
          ),
        ),
        catalog: '2026.02.01.000000',
        rules: '1.0.9',
      );
      await expectPair(
        await boot(store()),
        catalog: '2026.02.01.000000',
        rules: '1.0.9',
      );
    });

    test(
      'a signed rollback is not undone by relaunching with the same bundle',
      () async {
        final s = store();
        await boot(s);
        await activate(
          s,
          await candidate(
            sequence: 13,
            catalogVersion: '2025.12.01.000000',
            rulesVersion: '1.0.9',
          ),
        );
        for (var launch = 0; launch < 2; launch++) {
          await expectPair(
            await boot(store()),
            catalog: '2025.12.01.000000',
            rules: '1.0.9',
          );
        }
      },
    );
  });

  group('an app update with a new bundled pair', () {
    Future<FakeReleaseBundle> newBundle(String catalog, String rules) =>
        FakeReleaseBundle.build(
          workspace,
          catalogVersion: catalog,
          rulesVersion: rules,
          severity: 'avoid',
        );

    test('newer on both sides replaces the release', () async {
      await boot(store());
      final updated = await newBundle('2026.05.01.000000', '1.0.20');
      await expectPair(
        await boot(store(withBundle: updated)),
        catalog: '2026.05.01.000000',
        rules: '1.0.20',
      );
    });

    test('a newer over-the-air catalog stays, and the bundled rule correction '
        'still arrives', () async {
      final s = store();
      await boot(s);
      await activate(s, await candidate(rulesVersion: null));
      final updated = await newBundle('2026.02.01.000000', '1.0.20');

      final generation = await boot(store(withBundle: updated));
      await expectPair(generation, catalog: _updateCatalog, rules: '1.0.20');
      expect(await severityIn(generation.rules), 'avoid');
    });

    test('older bundled rules never replace newer active rules', () async {
      final s = store();
      await boot(s);
      await activate(s, await candidate());
      final updated = await newBundle('2026.05.01.000000', '1.0.5');
      await expectPair(
        await boot(store(withBundle: updated)),
        catalog: '2026.05.01.000000',
        rules: _updateRules,
      );
    });

    test('a blocked bundled version is never picked', () async {
      final s = store();
      await boot(s);
      await s.recordVerified(
        sequence: 1,
        blockedCatalog: const {},
        blockedRules: {'1.0.20'},
      );
      final updated = await newBundle('2026.01.01.000000', '1.0.20');
      await expectPair(
        await boot(store(withBundle: updated)),
        catalog: _bundledCatalog,
        rules: _bundledRules,
      );
    });

    test(
      'a rule correction this release\'s pair rule refuses is not taken',
      () async {
        final s = store();
        await boot(s);
        final c = await candidate();
        await activate(
          s,
          ReleaseCandidate(
            sequence: 4,
            catalogVersion: c.catalogVersion,
            catalogSha256: c.catalogSha256,
            minRulesVersion: '1.1.0',
            stagedCatalog: c.stagedCatalog,
            stagedRules: c.stagedRules,
            rulesVersion: c.rulesVersion,
            rulesSha256: c.rulesSha256,
          ),
        );
        final updated = await newBundle('2026.01.01.000000', '1.0.20');
        await expectPair(
          await boot(store(withBundle: updated)),
          catalog: _updateCatalog,
          rules: _updateRules,
        );
      },
    );
  });

  group('blocked_versions', () {
    Future<void> block(
      ReleaseStore s, {
      Set<String> catalog = const {},
      Set<String> rules = const {},
    }) => s.recordVerified(
      sequence: 99,
      blockedCatalog: catalog,
      blockedRules: rules,
    );

    test('a phone on a blocked release returns to the previous one', () async {
      final s = store();
      final previous = await boot(s);
      final active = await activate(s, await candidate());
      await block(s, rules: {_updateRules});
      expect(s.isSettled(active), isFalse);

      final generation = await s.open();
      open.add(generation);
      expect(generation.record.id, previous.record.id);
      expect(generation.rules, isNotNull);
      expect(generation.rulesWithheld, isFalse);
      expect(s.isSettled(generation), isTrue);
    });

    test('blocked rules with nowhere to go withhold interaction checks only, '
        'through a restart while offline', () async {
      final s = store();
      await boot(s);
      await block(s, rules: {_bundledRules});

      // Offline relaunch: only what the phone stored.
      final generation = await boot(store());
      expect(generation.rulesWithheld, isTrue);
      expect(generation.rules, isNull);
      expect(await generation.core.countProducts(), 1);
      final product = await generation.core
          .customSelect(
            "SELECT quality_score_v4_100 AS score, product_safety_status AS status "
            "FROM products_core",
          )
          .getSingle();
      expect(product.read<double>('score'), 88);
      expect(product.read<String>('status'), 'caution');
    });

    test(
      'a blocked catalog with nowhere to go withholds only quality scores',
      () async {
        final s = store();
        await boot(s);
        await block(s, catalog: {_bundledCatalog});

        final reopened = store();
        final generation = await boot(reopened);
        expect(generation.qualityWithheld, isTrue);
        expect(reopened.isSettled(generation), isTrue);

        final product = (await generation.core.findById(kFixtureProduct))!;
        expect(product.productName, 'Fixture Product');
        expect(await generation.core.countProducts(), 1);
        expect(product.qualityScoreV4100, isNull);
        expect(catalogProductIsNotScored(product), isTrue);
        expect(catalogProductHasCompletePublicScore(product), isFalse);
        // The limit that matters: safety status and rules are never touched.
        expect(
          catalogProductSafetyStatus(product),
          CatalogProductSafetyStatus.caution,
        );
        expect(generation.rules, isNotNull);
        expect(await severityIn(generation.rules), 'caution');
      },
    );

    test('a safety-suppressed product keeps its status when scores are '
        'withheld', () async {
      final path = p.join(workspace.path, 'suppressed.db');
      await buildCatalog(path, version: '2026.02.02.000000');
      final db = raw.sqlite3.open(path);
      db.execute(
        "UPDATE products_core SET quality_score_status = 'suppressed_safety', "
        "product_safety_status = 'blocked', quality_score_v4_100 = NULL",
      );
      db.close();
      final core = CoreDatabase.open(path);
      addTearDown(core.close);
      await core.withholdQualityScores();
      final product = (await core.findById(kFixtureProduct))!;
      expect(product.qualityScoreStatus, 'suppressed_safety');
      expect(catalogProductIsBlocked(product), isTrue);
    });

    test('blocking never empties the catalog or disables a product', () async {
      final s = store();
      await boot(s);
      await block(s, catalog: {_bundledCatalog}, rules: {_bundledRules});
      final generation = await boot(store());
      expect(await generation.core.countProducts(), 1);
      expect(await generation.core.findById(kFixtureProduct), isNotNull);
    });

    test('a replacement ends the withholding', () async {
      final s = store();
      await boot(s);
      await block(s, catalog: {_bundledCatalog}, rules: {_bundledRules});
      final reopened = store();
      await boot(reopened);

      final c = await candidate();
      final generation = await activate(reopened, c);
      expect(generation.rulesWithheld, isFalse);
      expect(generation.qualityWithheld, isFalse);
      expect(
        (await generation.core.findById(kFixtureProduct))!.qualityScoreV4100,
        88,
      );
      expect(await severityIn(generation.rules), 'contraindicated');
    });

    test('a lifted block restores the file with its scores', () async {
      final s = store();
      await boot(s);
      await block(s, catalog: {_bundledCatalog});
      final withheld = store();
      expect((await boot(withheld)).qualityWithheld, isTrue);

      await withheld.recordVerified(
        sequence: 100,
        blockedCatalog: const {},
        blockedRules: const {},
      );
      final restored = await withheld.open();
      open.add(restored);
      expect(restored.qualityWithheld, isFalse);
      expect(
        (await restored.core.findById(kFixtureProduct))!.qualityScoreV4100,
        88,
      );
    });

    test('a release with removed scores is never the source of a reused '
        'catalog', () async {
      final s = store();
      await boot(s);
      await block(s, catalog: {_bundledCatalog});
      final withheld = store();
      final generation = await boot(withheld);
      final result = await withheld.activate(
        ReleaseCandidate(
          sequence: 200,
          catalogVersion: generation.record.catalogVersion,
          catalogSha256: generation.record.catalogSha256,
          minRulesVersion: '1.0.0',
          stagedRules: (await candidate()).stagedRules,
          rulesVersion: _updateRules,
        ),
      );
      expect(result, isA<ReleaseNotActivated>());
    });
  });

  group('existing installs', () {
    File root(String name) => File(p.join(documents.path, name));

    test('a newer over-the-air catalog moves into a release', () async {
      await buildCatalog(
        root('pharmaguide_core.db').path,
        version: _updateCatalog,
      );
      await buildRules(root('interaction_db.sqlite').path, version: '1.0.1');
      root('pharmaguide_core.db.bundle_marker.json').writeAsStringSync('{}');

      final generation = await boot(store());
      await expectPair(
        generation,
        catalog: _updateCatalog,
        rules: _bundledRules,
      );
      expect(root('pharmaguide_core.db').existsSync(), isFalse);
      expect(root('interaction_db.sqlite').existsSync(), isFalse);
      expect(
        root('pharmaguide_core.db.bundle_marker.json').existsSync(),
        false,
      );
    });

    test('an older root catalog gives way to the bundled one', () async {
      await buildCatalog(
        root('pharmaguide_core.db').path,
        version: '2025.01.01.000000',
      );
      await expectPair(
        await boot(store()),
        catalog: _bundledCatalog,
        rules: _bundledRules,
      );
    });

    test('a corrupt root catalog gives way to the bundled one', () async {
      root('pharmaguide_core.db').writeAsStringSync('torn');
      await expectPair(
        await boot(store()),
        catalog: _bundledCatalog,
        rules: _bundledRules,
      );
    });

    test(
      'a crash during migration repeats it from the same root files',
      () async {
        await buildCatalog(
          root('pharmaguide_core.db').path,
          version: _updateCatalog,
        );
        final crashing = store(
          onStep: (at) async {
            if (at == ReleaseStep.writeRecord) throw SimulatedReleaseCrash(at);
          },
        );
        await expectLater(crashing.open(), throwsA(anything));
        expect(root('pharmaguide_core.db').existsSync(), isTrue);

        await expectPair(
          await boot(store()),
          catalog: _updateCatalog,
          rules: _bundledRules,
        );
        expect(root('pharmaguide_core.db').existsSync(), isFalse);
      },
    );

    test('a swap interrupted by the old code restores its backup', () async {
      const backupVersion = '2026.02.01.000000';
      await buildCatalog(
        root('pharmaguide_core.db.backup').path,
        version: backupVersion,
      );
      await buildCatalog(
        root('pharmaguide_core.db').path,
        version: _updateCatalog,
        empty: true,
      );

      await expectPair(
        await boot(store()),
        catalog: backupVersion,
        rules: _bundledRules,
      );
      expect(root('pharmaguide_core.db.backup').existsSync(), isFalse);
    });

    test('a file the old swap refused is not adopted', () async {
      const backupVersion = '2026.02.01.000000';
      await buildCatalog(
        root('pharmaguide_core.db.backup').path,
        version: backupVersion,
      );
      await buildCatalog(
        root('pharmaguide_core.db').path,
        version: '2026.09.09.000000',
      );
      root('pharmaguide_core.db.activation.json').writeAsStringSync(
        jsonEncode({'expected': _updateCatalog, 'previous': backupVersion}),
      );

      await expectPair(
        await boot(store()),
        catalog: backupVersion,
        rules: _bundledRules,
      );
      expect(root('pharmaguide_core.db.activation.json').existsSync(), isFalse);
    });

    test('a good new file the old swap was waiting on is kept', () async {
      await buildCatalog(
        root('pharmaguide_core.db.backup').path,
        version: '2026.02.01.000000',
      );
      await buildCatalog(
        root('pharmaguide_core.db').path,
        version: _updateCatalog,
      );
      root('pharmaguide_core.db.activation.json').writeAsStringSync(
        jsonEncode({
          'expected': _updateCatalog,
          'previous': '2026.02.01.000000',
        }),
      );

      await expectPair(
        await boot(store()),
        catalog: _updateCatalog,
        rules: _bundledRules,
      );
    });

    test(
      'unreadable old intent with no backup falls to the bundled catalog',
      () async {
        await buildCatalog(
          root('pharmaguide_core.db').path,
          version: _updateCatalog,
        );
        root(
          'pharmaguide_core.db.activation.json',
        ).writeAsStringSync('{broken');

        await expectPair(
          await boot(store()),
          catalog: _bundledCatalog,
          rules: _bundledRules,
        );
      },
    );

    test('a leftover root staging file is dropped', () async {
      await buildCatalog(
        root('pharmaguide_core.db.staging').path,
        version: _updateCatalog,
      );
      await boot(store());
      expect(root('pharmaguide_core.db.staging').existsSync(), isFalse);
    });
  });
}

const _preparationFingerprint =
    'ad631fba03b41d375732aa42743bd5626183709765f364968cee4ee5ef8d66fe';
