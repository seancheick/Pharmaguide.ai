// Release/packaging guard for the hydrated interaction database.
//
// interaction_db.sqlite is no longer in Git LFS — it is hydrated + verified at
// build time from a GitHub Release asset (tool/fetch_interaction_db.sh, pinned
// by tool/interaction_db.release.json). This test is the last line of defense
// before the app packages it: it must be a real SQLite (never a 133-byte LFS
// pointer or a truncated download) carrying the Sprint-3 clinical taxonomy.
//
// It is deliberately NOT tagged `bundle` (unlike the catalog-DB tests, which
// stay gated on the still-LFS pharmaguide_core.db). The interaction DB is
// present in CI after the hydrate step, so this guard runs there.
//
// It also exercises the REAL app bridge (InteractionDatabase.drugClassesForRxcui)
// — the method the depletion resolver uses to map a medication to its classes —
// not just raw SQL, so a regression in the consumer path is caught too.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/interaction_database.dart';

const _sqliteMagic = 'SQLite format 3';

// RxNorm-verified representative members (rxcui → name).
const _loopThiazide = 'class:loop_and_thiazide_diuretics';
const _ppi = 'class:proton_pump_inhibitors';
const _eiasm = 'class:enzyme_inducing_antiseizure_medications';

// Positive: these MUST resolve to the given class.
const _positives = <String, ({String rxcui, String name})>{
  '$_loopThiazide/furosemide': (rxcui: '4603', name: 'furosemide'),
  '$_loopThiazide/hydrochlorothiazide': (
    rxcui: '5487',
    name: 'hydrochlorothiazide',
  ),
  '$_ppi/omeprazole': (rxcui: '7646', name: 'omeprazole'),
  '$_ppi/pantoprazole': (rxcui: '40790', name: 'pantoprazole'),
  '$_eiasm/phenytoin': (rxcui: '8183', name: 'phenytoin'),
  '$_eiasm/carbamazepine': (rxcui: '2002', name: 'carbamazepine'),
};

// Negative: these must NOT resolve to the given class (safety-critical).
const _negatives = <String, ({String rxcui, String name})>{
  '$_loopThiazide/spironolactone': (rxcui: '9997', name: 'spironolactone'),
  '$_loopThiazide/amiloride': (rxcui: '644', name: 'amiloride'),
  '$_loopThiazide/eplerenone': (rxcui: '298869', name: 'eplerenone'),
  '$_loopThiazide/triamterene': (rxcui: '10763', name: 'triamterene'),
  '$_eiasm/oxcarbazepine': (rxcui: '32624', name: 'oxcarbazepine'),
};

// The PPI class must resolve exactly the five proton-pump inhibitors — no
// neutralising antacid (e.g. magnesium hydroxide) may leak in.
const _ppiExactRxcuis = <String>{'283742', '112002', '7646', '40790', '114979'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InteractionDatabase db;
  late Uint8List assetBytes;
  late Map<String, dynamic> pin;

  setUpAll(() async {
    pin =
        jsonDecode(File('tool/interaction_db.release.json').readAsStringSync())
            as Map<String, dynamic>;

    final data = await rootBundle.load('assets/db/interaction_db.sqlite');
    assetBytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    tempDir = await Directory.systemTemp.createTemp('idb-guard');
    final dbFile = File(p.join(tempDir.path, 'interaction_db.sqlite'));
    await dbFile.writeAsBytes(assetBytes, flush: true);
    db = InteractionDatabase.open(dbFile.path);
  });

  tearDownAll(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  group('interaction DB release guard: file integrity', () {
    test('bundled file is a real SQLite, not an LFS pointer or truncation', () {
      final header = String.fromCharCodes(assetBytes.take(_sqliteMagic.length));
      expect(
        header,
        _sqliteMagic,
        reason:
            'not a SQLite database — a 133-byte LFS pointer or a '
            'truncated download must never be packaged',
      );
    });

    test('bundled file is at least the pinned minimum size', () {
      expect(
        assetBytes.length,
        greaterThanOrEqualTo(pin['min_size_bytes'] as int),
      );
    });
  });

  group('interaction DB release guard: Sprint-3 taxonomy present', () {
    test('all three Sprint-3 classes exist and are non-empty', () async {
      for (final cid in const [_loopThiazide, _ppi, _eiasm]) {
        final members = await db.rxcuisForDrugClass(cid);
        expect(
          members,
          isNotEmpty,
          reason: '$cid missing/empty in drug_class_map',
        );
      }
    });

    test(
      'PPI class resolves exactly the five PPIs (no antacid leakage)',
      () async {
        final members = (await db.rxcuisForDrugClass(_ppi)).toSet();
        expect(
          members,
          _ppiExactRxcuis,
          reason:
              'a neutralising antacid (e.g. magnesium hydroxide) must not '
              'resolve to the PPI class',
        );
      },
    );
  });

  group('interaction DB release guard: app bridge resolution', () {
    _positives.forEach((label, m) {
      test('positive — $label', () async {
        final classes = await db.drugClassesForRxcui(m.rxcui);
        expect(
          classes,
          contains(label.split('/').first),
          reason:
              '${m.name} (${m.rxcui}) must resolve to ${label.split('/').first}',
        );
      });
    });

    _negatives.forEach((label, m) {
      test('negative — $label', () async {
        final target = label.split('/').first;
        final classes = await db.drugClassesForRxcui(m.rxcui);
        expect(
          classes,
          isNot(contains(target)),
          reason:
              '${m.name} (${m.rxcui}) must NOT resolve to $target '
              '(clinical hazard if it does)',
        );
      });
    });
  });
}
