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
const _valproate = 'class:valproate';
const _loop = 'class:loop_diuretics'; // Section 1 — calcium is loop-specific
const _acidsupp = 'class:acid_suppressants'; // Section 2 — iron (PPI + H2)

// Positive: these MUST resolve to the given class.
const _positives = <String, ({String rxcui, String name})>{
  '$_loopThiazide/furosemide': (rxcui: '4603', name: 'furosemide'),
  '$_loopThiazide/ethacrynic acid': (rxcui: '4109', name: 'ethacrynic acid'),
  '$_loopThiazide/hydrochlorothiazide': (
    rxcui: '5487',
    name: 'hydrochlorothiazide',
  ),
  '$_ppi/omeprazole': (rxcui: '7646', name: 'omeprazole'),
  '$_ppi/pantoprazole': (rxcui: '40790', name: 'pantoprazole'),
  '$_eiasm/phenytoin': (rxcui: '8183', name: 'phenytoin'),
  '$_eiasm/carbamazepine': (rxcui: '2002', name: 'carbamazepine'),
  '$_valproate/divalproex sodium': (rxcui: '266856', name: 'divalproex sodium'),
  '$_valproate/sodium valproate': (rxcui: '9919', name: 'sodium valproate'),
  '$_valproate/valproate': (rxcui: '40254', name: 'valproate'),
  '$_valproate/valproic acid': (rxcui: '11118', name: 'valproic acid'),
  '$_loop/furosemide': (rxcui: '4603', name: 'furosemide'),
  '$_acidsupp/omeprazole': (rxcui: '7646', name: 'omeprazole (PPI)'),
  '$_acidsupp/famotidine': (rxcui: '4278', name: 'famotidine (H2)'),
  // Corrected rxcui — lansoprazole is 17128, not the retired 112002.
  '$_ppi/lansoprazole': (rxcui: '17128', name: 'lansoprazole'),
  // Completeness 2026-07-24 — dexlansoprazole (Dexilant) is a current PPI.
  '$_ppi/dexlansoprazole': (rxcui: '816346', name: 'dexlansoprazole'),
  '$_acidsupp/dexlansoprazole': (
    rxcui: '816346',
    name: 'dexlansoprazole (PPI)',
  ),
};

// Negative: these must NOT resolve to the given class (safety-critical).
const _negatives = <String, ({String rxcui, String name})>{
  '$_loopThiazide/spironolactone': (rxcui: '9997', name: 'spironolactone'),
  '$_loopThiazide/amiloride': (rxcui: '644', name: 'amiloride'),
  '$_loopThiazide/eplerenone': (rxcui: '298869', name: 'eplerenone'),
  '$_loopThiazide/triamterene': (rxcui: '10763', name: 'triamterene'),
  '$_eiasm/oxcarbazepine': (rxcui: '32624', name: 'oxcarbazepine'),
  '$_eiasm/valproate': (rxcui: '40254', name: 'valproate'),
  '$_eiasm/divalproex sodium': (rxcui: '266856', name: 'divalproex sodium'),
  '$_eiasm/sodium valproate': (rxcui: '9919', name: 'sodium valproate'),
  '$_eiasm/valproic acid': (rxcui: '11118', name: 'valproic acid'),
  // Loop class is calciuric-only: thiazides retain calcium, K-sparing don't apply.
  '$_loop/hydrochlorothiazide': (rxcui: '5487', name: 'hydrochlorothiazide'),
  '$_loop/spironolactone': (rxcui: '9997', name: 'spironolactone'),
};

// The PPI class must resolve exactly the six proton-pump inhibitors (Section 2's
// five + dexlansoprazole 816346, added 2026-07-24) — no neutralising antacid
// (e.g. magnesium hydroxide) may leak in.
const _ppiExactRxcuis = <String>{
  '283742',
  '17128',
  '7646',
  '40790',
  '114979',
  '816346',
};

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
    test('required clinical classes exist and are non-empty', () async {
      for (final cid in const [
        _loopThiazide,
        _ppi,
        _eiasm,
        _valproate,
        _loop,
        _acidsupp,
      ]) {
        final members = await db.rxcuisForDrugClass(cid);
        expect(
          members,
          isNotEmpty,
          reason: '$cid missing/empty in drug_class_map',
        );
      }
    });

    test(
      'PPI class resolves exactly the six PPIs (no antacid leakage)',
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

  group(
    'interaction DB release guard: rxcui-identity fix (2026-07-24 audit)',
    () {
      test('retired lansoprazole rxcui 112002 resolves to nothing', () async {
        // The shipped DB must carry the corrected 17128, not the retired 112002.
        expect(await db.drugClassesForRxcui('112002'), isEmpty);
      });

      test('metronidazole 6922 is not a fluoroquinolone', () async {
        // 6922 = metronidazole was mislabelled moxifloxacin; the swap is fixed.
        expect(
          await db.drugClassesForRxcui('6922'),
          isNot(contains('class:fluoroquinolones')),
        );
      });
    },
  );
}
