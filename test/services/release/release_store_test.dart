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
    String minRulesVersion = '1.0.0',
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
      minRulesVersion: minRulesVersion,
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
          (2, _preparationFingerprint),
          reason:
              'The open-time work changed. Raise kReleasePreparation so phones '
              'rebuild their prepared files, then update this pin.',
        );
      },
    );

    // Seeds the active release as a folder an older build prepared, without the
    // column that build never added. Returns the old folder's path.
    Future<String> seedOlderFolder(int preparation) async {
      final s = store();
      await boot(s);
      final generation = await activate(s, await candidate());
      final id = generation.record.id;
      final folder = p.join(documents.path, 'releases', id);
      final record = File(p.join(folder, 'release.json'));
      final json = jsonDecode(record.readAsStringSync()) as Map;
      final oldId = id.replaceFirst('_p$kReleasePreparation', '_p$preparation');
      json['preparation'] = preparation;
      json['id'] = oldId;
      await generation.close();
      open.remove(generation);
      record.writeAsStringSync(jsonEncode(json));
      final oldFolder = p.join(documents.path, 'releases', oldId);
      Directory(folder).renameSync(oldFolder);
      final catalog = raw.sqlite3.open(p.join(oldFolder, 'catalog.db'));
      catalog.execute(
        'ALTER TABLE products_core DROP COLUMN safety_assessment_status',
      );
      catalog.execute(
        'ALTER TABLE products_core DROP COLUMN safety_assessment_reason',
      );
      catalog.close();
      final pointerFile = File(
        p.join(documents.path, 'releases', 'active.json'),
      );
      final pointer = pointerOnDisk()..['active'] = oldId;
      pointerFile.writeAsStringSync(jsonEncode(pointer));
      return oldFolder;
    }

    for (final preparation in [0, kReleasePreparation - 1]) {
      test('a folder from preparation $preparation is rebuilt from the same '
          'files, and the old folder is not written', () async {
        final oldFolder = await seedOlderFolder(preparation);
        final oldHash = sha256
            .convert(File(p.join(oldFolder, 'catalog.db')).readAsBytesSync())
            .toString();

        final rebuilt = await boot(store());
        expect(rebuilt.record.preparation, kReleasePreparation);
        expect(
          rebuilt.record.id,
          p
              .basename(oldFolder)
              .replaceFirst('_p$preparation', '_p$kReleasePreparation'),
        );
        await expectPair(rebuilt, catalog: _updateCatalog, rules: _updateRules);
        expect(
          sha256
              .convert(File(p.join(oldFolder, 'catalog.db')).readAsBytesSync())
              .toString(),
          oldHash,
        );
      });
    }

    // On a full phone the rebuild can't run, and the old folder stays active.
    // Typed reads use SELECT *, so a column it never had reads as null, which
    // means an older catalog and keeps the stricter rule (ADR-016). Naming that
    // column in a query would break this phone.
    test('a folder that cannot be rebuilt still reads, with no safety status, '
        'and is not written', () async {
      final oldFolder = await seedOlderFolder(kReleasePreparation - 1);
      final oldHash = sha256
          .convert(File(p.join(oldFolder, 'catalog.db')).readAsBytesSync())
          .toString();

      final kept = await boot(
        store(
          onStep: (step) async {
            if (step == ReleaseStep.prepare) {
              throw const FileSystemException(
                'No space left on device',
                '',
                OSError('disk full', 28),
              );
            }
          },
        ),
      );

      expect(kept.record.preparation, kReleasePreparation - 1);
      final product = (await kept.core.findById(kFixtureProduct))!;
      expect(product.safetyAssessmentStatus, isNull);
      expect(product.safetyAssessmentReason, isNull);
      expect(await kept.core.countProducts(), greaterThan(0));
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
      expect(foldersOnDisk(), [old.record.id], reason: 'never published');
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

    test('a release that fails to open as it activates is refused, and the '
        'phone stays on its release', () async {
      final s = store(
        onStep: (at) async {
          if (at != ReleaseStep.openNew) return;
          final folder = pointerOnDisk()['active'] as String;
          File(
            p.join(documents.path, 'releases', folder, 'catalog.db'),
          ).writeAsStringSync('torn');
        },
      );
      final current = await boot(s);
      final result = await s.activate(await candidate());

      expect(result, isA<ReleaseNotActivated>());
      expect(pointerOnDisk()['active'], current.record.id);
      expect(pointerOnDisk()['refused'], hasLength(1));
    });

    test('a file that can\'t be read the moment it activates stays eligible, '
        'and the phone stays on its release', () async {
      final s = store(
        onStep: (at) async {
          if (at != ReleaseStep.openNew) return;
          final folder = pointerOnDisk()['active'] as String;
          Process.runSync('chmod', [
            '000',
            p.join(documents.path, 'releases', folder, 'catalog.db'),
          ]);
        },
      );
      final current = await boot(s);
      final result = await s.activate(await candidate());

      expect(result, isA<ReleaseNotActivated>());
      expect(pointerOnDisk()['active'], current.record.id);
      expect(pointerOnDisk()['refused'], isEmpty);
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
        expect(
          Directory(documents.path)
              .listSync(recursive: true)
              .where((e) => p.basename(e.path).startsWith('assembly-')),
          isEmpty,
          reason: 'a half-built folder does not outlive the crash',
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

    test('a damaged release returns to the last good one, not the bundled '
        'one', () async {
      final s = store();
      await boot(s);
      final good = await activate(s, await candidate());
      final bad = await activate(
        s,
        await candidate(
          sequence: 20,
          catalogVersion: '2026.12.01.000000',
          stagedName: 'second',
        ),
      );
      expect(bad.record.id, isNot(good.record.id));
      await bad.close();
      open.remove(bad);
      File(
        p.join(documents.path, 'releases', bad.record.id, 'catalog.db'),
      ).writeAsStringSync('torn');

      final generation = await boot(store());

      expect(generation.record.id, good.record.id);
      expect(pointerOnDisk()['refused'], contains(bad.record.id));
    });

    test('a release missing a file is refused, since that won\'t come back '
        'on its own', () async {
      final s = store();
      final old = await boot(s);
      final active = await activate(s, await candidate());
      await active.close();
      open.remove(active);
      File(
        p.join(documents.path, 'releases', active.record.id, 'catalog.db'),
      ).deleteSync();

      final generation = await boot(store());

      expect(generation.record.id, old.record.id);
      expect(pointerOnDisk()['refused'], contains(active.record.id));
    });

    test('a file that can\'t be read right now is not condemned, and the next '
        'launch returns to it', () async {
      final s = store();
      final old = await boot(s);
      final active = await activate(s, await candidate());
      await active.close();
      open.remove(active);
      final catalog = File(
        p.join(documents.path, 'releases', active.record.id, 'catalog.db'),
      );
      Process.runSync('chmod', ['000', catalog.path]);
      addTearDown(() => Process.runSync('chmod', ['644', catalog.path]));

      final during = await boot(store());
      expect(during.record.id, old.record.id);
      expect(pointerOnDisk()['refused'], isEmpty);
      expect(pointerOnDisk()['active'], active.record.id);
      expect(foldersOnDisk(), contains(active.record.id));

      Process.runSync('chmod', ['644', catalog.path]);
      await expectPair(
        await boot(store()),
        catalog: _updateCatalog,
        rules: _updateRules,
      );
    });

    test('with nothing readable right now, launch fails without touching what '
        'is on disk', () async {
      final s = store();
      final generation = await boot(s);
      await generation.close();
      open.remove(generation);
      final catalog = File(
        p.join(documents.path, 'releases', generation.record.id, 'catalog.db'),
      );
      Process.runSync('chmod', ['000', catalog.path]);
      addTearDown(() => Process.runSync('chmod', ['644', catalog.path]));
      final before = pointerOnDisk();

      await expectLater(store().open(), throwsA(anything));

      expect(pointerOnDisk()['active'], before['active']);
      expect(foldersOnDisk(), contains(generation.record.id));
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

    test(
      'a newer bundle that fails validation leaves the phone on its release',
      () async {
        final s = store();
        await boot(s);
        await activate(s, await candidate());

        final broken = FakeReleaseBundle(
          catalog: Uint8List.fromList(utf8.encode('not a database')),
          rules: bundle.rules,
          catalogVersion: '2026.05.01.000000',
          rulesVersion: _bundledRules,
        );
        await expectPair(
          await boot(store(withBundle: broken)),
          catalog: _updateCatalog,
          rules: _updateRules,
        );
      },
    );

    test('a later good bundle replaces rules that never opened', () async {
      final noRules = FakeReleaseBundle(
        catalog: bundle.catalog,
        rules: Uint8List.fromList(utf8.encode('not a database')),
        catalogVersion: _bundledCatalog,
        rulesVersion: _bundledRules,
      );
      expect((await boot(store(withBundle: noRules))).rules, isNull);

      final updated = await newBundle(_bundledCatalog, '1.0.20');
      await expectPair(
        await boot(store(withBundle: updated)),
        catalog: _bundledCatalog,
        rules: '1.0.20',
      );
    });

    test(
      'a catalog correction arrives on a phone whose rules never opened',
      () async {
        final noRules = FakeReleaseBundle(
          catalog: bundle.catalog,
          rules: Uint8List.fromList(utf8.encode('not a database')),
          catalogVersion: _bundledCatalog,
          rulesVersion: _bundledRules,
        );
        await boot(store(withBundle: noRules));

        final updated = await FakeReleaseBundle.build(
          workspace,
          catalogVersion: '2026.05.01.000000',
          rulesVersion: _bundledRules,
        );
        final generation = await boot(store(withBundle: updated));
        expect(
          await generation.core.validateCatalogSnapshot(),
          '2026.05.01.000000',
        );
      },
    );

    test(
      'a rule correction keeps a withheld catalog marked as withheld',
      () async {
        final s = store();
        await boot(s);
        await s.recordVerified(
          sequence: 1,
          blockedCatalog: {_bundledCatalog},
          blockedRules: const {},
        );
        final relaunched = await boot(store());
        expect(relaunched.qualityWithheld, isTrue);
        // What the screens read to say so.
        expect(relaunched.core.qualityWithheld, isTrue);

        final updated = await newBundle(_bundledCatalog, '1.0.20');
        final generation = await boot(store(withBundle: updated));
        expect(generation.qualityWithheld, isTrue);
        expect(generation.core.qualityWithheld, isTrue);
        expect(
          (await generation.core.findById(kFixtureProduct))!.qualityScoreV4100,
          isNull,
        );
        expect(await severityIn(generation.rules), 'avoid');
      },
    );

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
      await block(s, catalog: {_updateCatalog});
      expect(s.isSettled(active), isFalse);

      final generation = await s.reselect();
      open.add(generation);
      expect(generation.record.id, previous.record.id);
      expect(generation.rules, isNotNull);
      expect(generation.rulesWithheld, isFalse);
      expect(s.isSettled(generation), isTrue);
    });

    test('re-selecting during a session leaves the folder on screen in place, '
        'so a running check can finish', () async {
      final s = store();
      await boot(s);
      final active = await activate(s, await candidate());
      await block(s, catalog: {_updateCatalog});

      final generation = await s.reselect();
      open.add(generation);

      expect(generation.rules, isNotNull);
      expect(generation.record.id, isNot(active.record.id));
      expect(foldersOnDisk(), contains(active.record.id));
      expect(await severityIn(active.rules), 'contraindicated');
      expect(await active.core.countProducts(), 1);

      await boot(store());
      expect(foldersOnDisk(), isNot(contains(active.record.id)));
    });

    test('a damaged copy without scores is rebuilt, and never falls back to '
        'the blocked file that still has them', () async {
      final s = store();
      await boot(s);
      await block(s, catalog: {_bundledCatalog});
      final withheld = await boot(store());
      expect(withheld.qualityWithheld, isTrue);
      await withheld.close();
      open.remove(withheld);
      File(
        p.join(documents.path, 'releases', withheld.record.id, 'catalog.db'),
      ).writeAsStringSync('torn');

      final generation = await boot(store());
      expect(generation.qualityWithheld, isTrue);
      expect(
        (await generation.core.findById(kFixtureProduct))!.qualityScoreV4100,
        isNull,
      );
    });

    test('a build that rebuilds prepared files keeps the scored source of a '
        'withheld catalog, so a lifted block still restores scores', () async {
      final s = store();
      await boot(s);
      await block(s, catalog: {_bundledCatalog});
      final withheld = await boot(store());
      await withheld.close();
      open.remove(withheld);

      final id = withheld.record.id;
      final oldId = id.replaceFirst('_p$kReleasePreparation', '_p0');
      final folder = p.join(documents.path, 'releases', id);
      final record = File(p.join(folder, 'release.json'));
      final json = jsonDecode(record.readAsStringSync()) as Map;
      json['preparation'] = 0;
      json['id'] = oldId;
      record.writeAsStringSync(jsonEncode(json));
      Directory(folder).renameSync(p.join(documents.path, 'releases', oldId));
      File(
        p.join(documents.path, 'releases', 'active.json'),
      ).writeAsStringSync(jsonEncode(pointerOnDisk()..['active'] = oldId));

      final rebuilt = store();
      expect((await boot(rebuilt)).qualityWithheld, isTrue);
      await rebuilt.recordVerified(
        sequence: 100,
        blockedCatalog: const {},
        blockedRules: const {},
      );
      final restored = await rebuilt.reselect();
      open.add(restored);
      expect(restored.qualityWithheld, isFalse);
      expect(
        (await restored.core.findById(kFixtureProduct))!.qualityScoreV4100,
        88,
      );
    });

    group('when only the rules are blocked', () {
      Future<ReleaseStore> onRules({
        required String catalogVersion,
        String minRulesVersion = '1.0.0',
      }) async {
        final s = store();
        await boot(s);
        final result = await s.activate(
          await candidate(
            catalogVersion: catalogVersion,
            minRulesVersion: minRulesVersion,
          ),
        );
        open.add((result as ReleaseActivated).generation);
        await s.recordVerified(
          sequence: 2,
          blockedCatalog: const {},
          blockedRules: const {_updateRules},
        );
        return s;
      }

      Future<void> expectProductsStillShow(ReleaseGeneration generation) async {
        expect(generation.qualityWithheld, isFalse);
        final product = await generation.core
            .customSelect(
              "SELECT quality_score_v4_100 AS score, product_safety_status AS status "
              "FROM products_core",
            )
            .getSingle();
        expect(product.read<double>('score'), 88);
        expect(product.read<String>('status'), 'caution');
      }

      test('the newer catalog stays, and only interaction checks are withheld '
          '(Sean, 2026-11-03)', () async {
        final s = await onRules(catalogVersion: _updateCatalog);

        final generation = await s.reselect();
        open.add(generation);

        expect(generation.record.catalogVersion, _updateCatalog);
        expect(generation.rules, isNull);
        expect(generation.rulesWithheld, isTrue);
        expect(s.isSettled(generation), isTrue);
        await expectProductsStillShow(generation);

        final relaunch = await boot(store());
        expect(relaunch.record.catalogVersion, _updateCatalog);
        expect(relaunch.rulesWithheld, isTrue);
        await expectProductsStillShow(relaunch);
      });

      test(
        'the same catalog returns to the rules it was paired with',
        () async {
          final s = await onRules(catalogVersion: _bundledCatalog);

          final generation = await s.reselect();
          open.add(generation);

          await expectPair(
            generation,
            catalog: _bundledCatalog,
            rules: _bundledRules,
          );
        },
      );

      test(
        'the same catalog doesn\'t return to rules below its minimum',
        () async {
          final s = await onRules(
            catalogVersion: _bundledCatalog,
            minRulesVersion: _updateRules,
          );

          final generation = await s.reselect();
          open.add(generation);

          expect(generation.record.rulesVersion, _updateRules);
          expect(generation.rulesWithheld, isTrue);
          await expectProductsStillShow(generation);
        },
      );
    });

    test('a blocked catalog still returns to the previous release, even when '
        'its rules are blocked too', () async {
      final s = store();
      await boot(s);
      final result = await s.activate(await candidate());
      open.add((result as ReleaseActivated).generation);
      await s.recordVerified(
        sequence: 2,
        blockedCatalog: const {_updateCatalog},
        blockedRules: const {_updateRules},
      );

      final generation = await s.reselect();
      open.add(generation);

      await expectPair(
        generation,
        catalog: _bundledCatalog,
        rules: _bundledRules,
      );
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

    group('a blocked catalog with no usable rules', () {
      late FakeReleaseBundle brokenRules;
      setUp(() {
        brokenRules = FakeReleaseBundle(
          catalog: bundle.catalog,
          rules: Uint8List.fromList(utf8.encode('not a database')),
          catalogVersion: _bundledCatalog,
          rulesVersion: _bundledRules,
        );
      });

      File activeRulesFile(ReleaseStore s) => File(
        p.join(documents.path, 'releases', s.active!.id, 'rules.sqlite'),
      );

      Future<void> expectScoreWithheld(ReleaseGeneration generation) async {
        expect(generation.qualityWithheld, isTrue);
        final product = (await generation.core.findById(kFixtureProduct))!;
        expect(product.productName, 'Fixture Product');
        expect(product.qualityScoreV4100, isNull);
        expect(catalogProductIsNotScored(product), isTrue);
        expect(
          catalogProductSafetyStatus(product),
          CatalogProductSafetyStatus.caution,
        );
      }

      test(
        'withholds the score, and keeps it withheld through a relaunch',
        () async {
          final s = store(withBundle: brokenRules);
          expect((await boot(s)).rules, isNull);
          await block(s, catalog: {_bundledCatalog});

          final reopened = store(withBundle: brokenRules);
          final generation = await boot(reopened);
          await expectScoreWithheld(generation);
          expect(generation.rules, isNull);
          expect(reopened.isSettled(generation), isTrue);

          await expectScoreWithheld(await boot(store(withBundle: brokenRules)));
        },
      );

      test(
        'verified revocations remain effective when the pointer cannot be saved',
        () async {
          final s = store();
          final initial = await boot(s);
          final obstruction = Directory(
            p.join(documents.path, 'releases', 'active.json.tmp'),
          );
          await obstruction.create();
          await expectLater(
            s.recordVerified(
              sequence: 9,
              blockedCatalog: {_bundledCatalog},
              blockedRules: {_bundledRules},
            ),
            throwsA(isA<FileSystemException>()),
          );
          expect(s.isSettled(initial), isFalse);
          final withheld = await s.reselect();
          open.add(withheld);
          await expectScoreWithheld(withheld);
          expect(withheld.rulesWithheld, isTrue);
          expect(withheld.rules, isNull);
          await obstruction.delete();
          await s.recordVerified(
            sequence: 9,
            blockedCatalog: {_bundledCatalog},
            blockedRules: {_bundledRules},
          );
          await expectScoreWithheld(await boot(store()));
        },
      );

      test(
        'a failed scoreless preparation removes its assembly in the same session',
        () async {
          var failPreparation = false;
          final s = store(
            onStep: (step) async {
              if (failPreparation && step == ReleaseStep.prepare) {
                throw const FileSystemException(
                  'No space left on device',
                  '',
                  OSError('disk full', 28),
                );
              }
            },
          );
          await boot(s);
          await block(s, catalog: {_bundledCatalog});
          failPreparation = true;
          final withheld = await s.reselect();
          open.add(withheld);
          await expectScoreWithheld(withheld);
          final leftovers = Directory(p.join(documents.path, 'releases'))
              .listSync(recursive: true)
              .whereType<Directory>()
              .where((d) => p.basename(d.path).startsWith('assembly-'))
              .toList();
          expect(
            leftovers,
            isEmpty,
            reason:
                'a failed copy must not consume space until the next launch',
          );
        },
      );

      for (final hasRules in [false, true]) {
        test('disk-full withholding protects every read and relaunch '
            '(rules=$hasRules)', () async {
          var cannotAssemble = false;
          Future<void> failCopy(ReleaseStep step) async {
            if (cannotAssemble && step == ReleaseStep.assemble) {
              throw const FileSystemException(
                'No space left on device',
                '',
                OSError('disk full', 28),
              );
            }
          }

          final chosenBundle = hasRules ? bundle : brokenRules;
          final s = store(withBundle: chosenBundle, onStep: failCopy);
          final initial = await boot(s);
          final scoredPath = p.join(
            documents.path,
            'releases',
            initial.record.id,
            'catalog.db',
          );
          await block(s, catalog: {_bundledCatalog});
          cannotAssemble = true;

          final withheld = await s.reselect();
          open.add(withheld);
          await expectScoreWithheld(withheld);
          expect(withheld.core.qualityWithheld, isTrue);
          expect(s.isSettled(withheld), isTrue);
          expect(withheld.rules != null, hasRules);
          final rows = await withheld.core
              .customSelect(
                'SELECT rowid, quality_score_v4_100, quality_tier, '
                'quality_score_status, product_safety_status FROM products_core',
              )
              .get();
          expect(rows.single.data['rowid'], isNotNull);
          expect(rows.single.data['quality_score_v4_100'], isNull);
          expect(rows.single.data['quality_tier'], isNull);
          expect(rows.single.data['quality_score_status'], 'not_scored');
          expect(rows.single.data['product_safety_status'], 'caution');
          expect(
            (await withheld.core.searchProducts(
              'Fixture',
            )).single.qualityScoreV4100,
            isNull,
          );
          expect(
            (await withheld.core.filterProducts()).single.qualityScoreV4100,
            isNull,
          );

          // The original file stays intact: withholding is a read boundary,
          // not an in-place mutation of the only usable catalog.
          final original = raw.sqlite3.open(scoredPath);
          try {
            expect(
              original
                  .select(
                    'SELECT quality_score_v4_100 '
                    'FROM products_core',
                  )
                  .single
                  .values
                  .single,
              88,
            );
          } finally {
            original.close();
          }
          final reopened = store(withBundle: chosenBundle, onStep: failCopy);
          await expectScoreWithheld(await boot(reopened));
          await block(reopened);
          final restored = await reopened.reselect();
          open.add(restored);
          expect(restored.qualityWithheld, isFalse);
          expect(
            (await restored.core.findById(kFixtureProduct))!.qualityScoreV4100,
            88,
          );
        });
      }

      test(
        'read projection matches scoreless copy and preserves FTS and bans',
        () async {
          final initial = await boot(store());
          final source = File(
            p.join(documents.path, 'releases', initial.record.id, 'catalog.db'),
          );
          final prepared = File(p.join(workspace.path, 'projection.db'));
          await source.copy(prepared.path);
          final setup = raw.sqlite3.open(prepared.path);
          try {
            setup.execute("UPDATE products_core SET upc_sku = '012345678905'");
            setup.execute(
              'CREATE VIRTUAL TABLE products_fts USING fts5('
              'product_name, content=products_core, content_rowid=rowid)',
            );
            setup.execute(
              "INSERT INTO products_fts(products_fts) VALUES('rebuild')",
            );
          } finally {
            setup.close();
          }
          final projected = CoreDatabase.readOnly(
            prepared,
            qualityWithheld: true,
          );
          addTearDown(projected.close);
          expect(
            (await projected.searchProducts(
              'Fixture',
            )).single.qualityScoreV4100,
            isNull,
          );
          final fts = await projected
              .customSelect(
                "SELECT p.quality_score_v4_100 FROM products_fts f "
                "JOIN products_core p ON p.rowid = f.rowid "
                "WHERE products_fts MATCH 'Fixture'",
              )
              .get();
          expect(fts, hasLength(1));
          expect(fts.single.data['quality_score_v4_100'], isNull);
          expect(
            (await projected.findAllByUpc(
              '012345678905',
            )).single.qualityScoreV4100,
            isNull,
          );
          final projectedRow = Map<String, dynamic>.from(
            (await projected
                    .customSelect('SELECT * FROM products_core')
                    .getSingle())
                .data,
          )..remove('rowid');
          final writable = CoreDatabase(prepared);
          await writable.withholdQualityScores();
          final copiedRow =
              (await writable
                      .customSelect('SELECT * FROM products_core')
                      .getSingle())
                  .data;
          expect(projectedRow, copiedRow);
          await writable.customStatement(
            "UPDATE products_core SET "
            "quality_score_status = 'suppressed_safety', "
            "quality_assessment_status = 'complete', "
            "product_safety_status = 'blocked'",
          );
          await writable.close();
          final banned = await projected.findById(kFixtureProduct);
          expect(banned!.qualityScoreStatus, 'suppressed_safety');
          expect(banned.qualityAssessmentStatus, 'complete');
          expect(banned.productSafetyStatus, 'blocked');
          await expectLater(
            projected.customStatement('DELETE FROM products_core'),
            throwsA(anything),
          );
        },
      );

      test('withholds the score during a session too', () async {
        final s = store(withBundle: brokenRules);
        await boot(s);
        await block(s, catalog: {_bundledCatalog});

        final generation = await s.reselect();
        open.add(generation);

        await expectScoreWithheld(generation);
        expect(s.isSettled(generation), isTrue);
      });

      test(
        'withholds the score when the release\'s rules file is corrupt',
        () async {
          final s = store();
          await boot(s);
          activeRulesFile(s).writeAsBytesSync(utf8.encode('not a database'));
          await block(s, catalog: {_bundledCatalog});

          final generation = await boot(store(withBundle: brokenRules));

          await expectScoreWithheld(generation);
          expect(generation.rules, isNull);
        },
      );

      test(
        'withholds the score when the release\'s rules file is missing',
        () async {
          final s = store();
          await boot(s);
          activeRulesFile(s).deleteSync();
          await block(s, catalog: {_bundledCatalog});

          final generation = await boot(store(withBundle: brokenRules));

          await expectScoreWithheld(generation);
          expect(generation.rules, isNull);
        },
      );

      test('corrupt rules with a good bundle get the bundled rules back, and '
          'the score stays withheld', () async {
        final s = store();
        await boot(s);
        activeRulesFile(s).writeAsBytesSync(utf8.encode('not a database'));
        await block(s, catalog: {_bundledCatalog});

        final generation = await boot(store());

        await expectScoreWithheld(generation);
        expect(await severityIn(generation.rules), 'caution');
      });

      test('rules that recover later don\'t bring the score back', () async {
        final s = store(withBundle: brokenRules);
        await boot(s);
        await block(s, catalog: {_bundledCatalog});
        await boot(store(withBundle: brokenRules));

        final recovered = await boot(store());

        await expectScoreWithheld(recovered);
        expect(await severityIn(recovered.rules), 'caution');
        await expectScoreWithheld(await boot(store()));
      });

      test('lifting the block returns the score and keeps the rules that '
          'recovered', () async {
        final s = store(withBundle: brokenRules);
        await boot(s);
        await block(s, catalog: {_bundledCatalog});
        await boot(store(withBundle: brokenRules));
        final recovering = store();
        await boot(recovering);

        await block(recovering);
        final generation = await boot(store());

        expect(generation.qualityWithheld, isFalse);
        final product = (await generation.core.findById(kFixtureProduct))!;
        expect(product.qualityScoreV4100, 88);
        expect(await severityIn(generation.rules), 'caution');
      });

      test('lifting the block keeps newer rules a bundle brought while the '
          'score was withheld', () async {
        final s = store();
        await boot(s);
        await block(s, catalog: {_bundledCatalog});
        await boot(store());
        final update = await FakeReleaseBundle.build(
          workspace,
          catalogVersion: _bundledCatalog,
          rulesVersion: _updateRules,
        );
        final updated = store(withBundle: update);
        await expectPair(
          await boot(updated),
          catalog: _bundledCatalog,
          rules: _updateRules,
        );

        await block(updated);
        final generation = await boot(store(withBundle: update));

        expect(generation.qualityWithheld, isFalse);
        final product = (await generation.core.findById(kFixtureProduct))!;
        expect(product.qualityScoreV4100, 88);
        await expectPair(
          generation,
          catalog: _bundledCatalog,
          rules: _updateRules,
        );
      });

      test('a catalog that isn\'t blocked keeps its score', () async {
        final s = store(withBundle: brokenRules);
        await boot(s);
        await block(s, catalog: {_updateCatalog});

        final generation = await boot(store(withBundle: brokenRules));

        expect(generation.qualityWithheld, isFalse);
        final product = (await generation.core.findById(kFixtureProduct))!;
        expect(product.qualityScoreV4100, 88);
      });

      test('a phone with no rules can still take a catalog update, which '
          'ends the withholding', () async {
        final s = store(withBundle: brokenRules);
        await boot(s);
        await block(s, catalog: {_bundledCatalog});
        final withheld = store(withBundle: brokenRules);
        await boot(withheld);

        final result = await withheld.activate(
          await candidate(sequence: 100, rulesVersion: null),
        );

        expect(result, isA<ReleaseActivated>());
        final generation = (result as ReleaseActivated).generation;
        open.add(generation);
        expect(generation.record.catalogVersion, _updateCatalog);
        expect(generation.qualityWithheld, isFalse);
        expect(generation.rules, isNull);
        final product = (await generation.core.findById(kFixtureProduct))!;
        expect(product.qualityScoreV4100, 88);
      });

      test('a phone with no rules can take a newer bundled catalog whose '
          'rules are blocked', () async {
        await boot(store(withBundle: brokenRules));
        final s = store(withBundle: brokenRules);
        await boot(s);
        await block(s, rules: {_updateRules});
        final update = await FakeReleaseBundle.build(
          workspace,
          catalogVersion: _updateCatalog,
          rulesVersion: _updateRules,
        );

        final generation = await boot(store(withBundle: update));

        expect(generation.record.catalogVersion, _updateCatalog);
        expect(generation.rules, isNull);
      });

      test('a no-rules release from an older build is rebuilt', () async {
        final s = store(withBundle: brokenRules);
        await boot(s);
        final id = s.active!.id;
        final oldId = id.replaceFirst('_p$kReleasePreparation', '_p0');
        final releases = p.join(documents.path, 'releases');
        Directory(p.join(releases, id)).renameSync(p.join(releases, oldId));
        final recordFile = File(p.join(releases, oldId, 'release.json'));
        final json = jsonDecode(recordFile.readAsStringSync()) as Map;
        json['id'] = oldId;
        json['preparation'] = 0;
        recordFile.writeAsStringSync(jsonEncode(json));
        final pointerFile = File(p.join(releases, 'active.json'));
        pointerFile.writeAsStringSync(
          pointerFile.readAsStringSync().replaceAll(id, oldId),
        );

        final generation = await boot(store(withBundle: brokenRules));

        expect(generation.record.preparation, kReleasePreparation);
        expect(generation.rules, isNull);
      });
    });

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
      final restored = await withheld.reselect();
      open.add(restored);
      expect(restored.qualityWithheld, isFalse);
      expect(
        (await restored.core.findById(kFixtureProduct))!.qualityScoreV4100,
        88,
      );
      // Nothing else is left to return to, and the file is not its own backup.
      expect(pointerOnDisk()['previous'], isNull);
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

    test('a crash during migration keeps the catalog, and the next launch '
        'finishes the move', () async {
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

      await expectPair(
        await boot(store()),
        catalog: _updateCatalog,
        rules: _bundledRules,
      );
      expect(root('pharmaguide_core.db').existsSync(), isFalse);
    });

    group('with no room to write', () {
      test('a newer root catalog and its rules move, needing no new space, '
          'on a phone that has none', () async {
        await buildCatalog(
          root('pharmaguide_core.db').path,
          version: _updateCatalog,
        );
        await buildRules(root('interaction_db.sqlite').path, version: '1.0.1');
        bundle.noSpaceForDatabases = true;

        final generation = await boot(store());

        await expectPair(generation, catalog: _updateCatalog, rules: '1.0.1');
        expect(root('pharmaguide_core.db').existsSync(), isFalse);
        expect(root('interaction_db.sqlite').existsSync(), isFalse);
      });

      test(
        'an older root catalog keeps working while the bundled one can\'t '
        'be written, and the bundled pair lands once there is room',
        () async {
          await buildCatalog(
            root('pharmaguide_core.db').path,
            version: '2025.06.01.000000',
          );
          await buildRules(
            root('interaction_db.sqlite').path,
            version: '1.0.1',
          );
          bundle.noSpaceForDatabases = true;

          await expectPair(
            await boot(store()),
            catalog: '2025.06.01.000000',
            rules: '1.0.1',
          );

          bundle.noSpaceForDatabases = false;
          await expectPair(
            await boot(store()),
            catalog: _bundledCatalog,
            rules: _bundledRules,
          );
        },
      );

      test(
        'a failed staging folder doesn\'t strand a good root catalog',
        () async {
          await buildCatalog(
            root('pharmaguide_core.db').path,
            version: _updateCatalog,
          );
          final staging = Directory(
            p.join(documents.path, 'releases', 'staging'),
          )..createSync(recursive: true);
          Process.runSync('chmod', ['555', staging.path]);
          addTearDown(() => Process.runSync('chmod', ['755', staging.path]));

          expect((await boot(store())).record.catalogVersion, _updateCatalog);
        },
      );

      test('with nothing writable the root files open where they are, are '
          'kept, and the next launch moves them', () async {
        await buildCatalog(
          root('pharmaguide_core.db').path,
          version: _updateCatalog,
        );
        await buildRules(root('interaction_db.sqlite').path, version: '1.0.1');
        final releases = Directory(p.join(documents.path, 'releases'))
          ..createSync();
        Process.runSync('chmod', ['555', releases.path]);
        addTearDown(() => Process.runSync('chmod', ['755', releases.path]));

        final s = store();
        final generation = await boot(s);

        await expectPair(generation, catalog: _updateCatalog, rules: '1.0.1');
        expect(root('pharmaguide_core.db').existsSync(), isTrue);
        expect(root('interaction_db.sqlite').existsSync(), isTrue);

        // The session's own recheck must not fall over on the missing pointer.
        final again = await s.reselect();
        open.add(again);
        expect(again.record.catalogVersion, _updateCatalog);

        Process.runSync('chmod', ['755', releases.path]);
        await expectPair(
          await boot(store()),
          catalog: _updateCatalog,
          rules: _bundledRules,
        );
        expect(root('pharmaguide_core.db').existsSync(), isFalse);
      });

      test('a crash right after the move keeps the catalog even with an old '
          'swap backup beside it', () async {
        await buildCatalog(
          root('pharmaguide_core.db').path,
          version: _updateCatalog,
        );
        await buildCatalog(
          root('pharmaguide_core.db.backup').path,
          version: '2026.02.01.000000',
        );
        final crashing = store(
          onStep: (at) async {
            if (at == ReleaseStep.assemble) throw SimulatedReleaseCrash(at);
          },
        );
        await expectLater(crashing.open(), throwsA(anything));

        await expectPair(
          await boot(store()),
          catalog: _updateCatalog,
          rules: _bundledRules,
        );
      });
    });

    group('rules that fail once at first launch', () {
      late FakeReleaseBundle brokenRules;
      setUp(() {
        brokenRules = FakeReleaseBundle(
          catalog: bundle.catalog,
          rules: Uint8List.fromList(utf8.encode('not a database')),
          catalogVersion: _bundledCatalog,
          rulesVersion: _bundledRules,
        );
      });

      test('come back on the next launch, and a catalog update then '
          'works', () async {
        final first = await boot(store(withBundle: brokenRules));
        expect(first.rules, isNull);

        final s = store();
        await expectPair(
          await boot(s),
          catalog: _bundledCatalog,
          rules: _bundledRules,
        );

        final result = await s.activate(
          await candidate(sequence: 1, rulesVersion: null),
        );
        expect(result, isA<ReleaseActivated>());
        open.add((result as ReleaseActivated).generation);
        expect(result.generation.rules, isNotNull);
      });

      test('keep being retried while they keep failing', () async {
        await boot(store(withBundle: brokenRules));
        expect((await boot(store(withBundle: brokenRules))).rules, isNull);
        expect((await boot(store())).rules, isNotNull);
      });

      test('fall back to the root rules when the bundled ones fail', () async {
        await buildRules(root('interaction_db.sqlite').path, version: '1.0.1');

        await expectPair(
          await boot(store(withBundle: brokenRules)),
          catalog: _bundledCatalog,
          rules: '1.0.1',
        );
        await expectPair(
          await boot(store()),
          catalog: _bundledCatalog,
          rules: _bundledRules,
        );
      });
    });

    group('a root catalog that can\'t be read right now', () {
      void lock() {
        Process.runSync('chmod', ['000', root('pharmaguide_core.db').path]);
        addTearDown(() {
          final file = root('pharmaguide_core.db');
          if (file.existsSync()) Process.runSync('chmod', ['644', file.path]);
        });
      }

      void unlock() =>
          Process.runSync('chmod', ['644', root('pharmaguide_core.db').path]);

      test('is kept, and wins once it can be read', () async {
        await buildCatalog(
          root('pharmaguide_core.db').path,
          version: _updateCatalog,
        );
        lock();

        await expectLater(boot(store()), throwsA(anything));
        expect(root('pharmaguide_core.db').existsSync(), isTrue);

        unlock();
        await expectPair(
          await boot(store()),
          catalog: _updateCatalog,
          rules: _bundledRules,
        );
      });

      test('doesn\'t let an interrupted swap replace it', () async {
        await buildCatalog(
          root('pharmaguide_core.db').path,
          version: _updateCatalog,
        );
        await buildCatalog(
          root('pharmaguide_core.db.backup').path,
          version: '2026.02.01.000000',
        );
        root(
          'pharmaguide_core.db.activation.json',
        ).writeAsStringSync(jsonEncode({'expected': _updateCatalog}));
        lock();

        await expectLater(boot(store()), throwsA(anything));

        unlock();
        expect((await boot(store())).record.catalogVersion, _updateCatalog);
      });

      test('still gives way when the file is really invalid', () async {
        root('pharmaguide_core.db').writeAsStringSync('torn');

        await expectPair(
          await boot(store()),
          catalog: _bundledCatalog,
          rules: _bundledRules,
        );
      });
    });

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

    test('a root catalog that fails validation gives way to the bundled one, '
        'on this launch and not only the next', () async {
      await buildCatalog(
        root('pharmaguide_core.db').path,
        version: _updateCatalog,
        empty: true,
      );
      await expectPair(
        await boot(store()),
        catalog: _bundledCatalog,
        rules: _bundledRules,
      );
    });

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
    '2447eb8c853e4909bdbe34f1af4513fb6c857bbd2c638a49ec058bd5bab47428';
