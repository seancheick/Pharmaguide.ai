// The upgrade on a phone with no room, on a volume that is really full, with the
// real bundled files. It needs a small disk image, so it runs only when one is
// given:
//
//   hdiutil create -size 110m -fs HFS+ -volname pgfull /tmp/pgfull.dmg
//   hdiutil attach /tmp/pgfull.dmg
//   PG_RELEASE_FULL_VOLUME=/Volumes/pgfull \
//     flutter test test/services/release/release_full_disk_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/release_store.dart';

import 'release_fixtures.dart';

void main() {
  final volume = Platform.environment['PG_RELEASE_FULL_VOLUME'];

  test(
    'an install keeps working when the volume has no room for a second copy',
    () async {
      await CrashReportingService().initialize();
      final documents = Directory(p.join(volume!, 'documents'))
        ..createSync(recursive: true);
      addTearDown(() => documents.deleteSync(recursive: true));
      final catalog = File('assets/db/pharmaguide_core.db');
      final rules = File('assets/db/interaction_db.sqlite');
      catalog.copySync(p.join(documents.path, 'pharmaguide_core.db'));
      rules.copySync(p.join(documents.path, 'interaction_db.sqlite'));

      // Fill what is left, then free only enough for the small files.
      final filler = File(
        p.join(documents.path, 'filler'),
      ).openSync(mode: FileMode.write);
      final chunk = List<int>.filled(1 << 18, 0);
      var written = 0;
      try {
        while (true) {
          filler.writeFromSync(chunk);
          written += chunk.length;
        }
      } on FileSystemException {
        filler.truncateSync(written - (1 << 20));
      }
      filler.closeSync();

      final bundle = FakeReleaseBundle(
        catalog: await catalog.readAsBytes(),
        rules: await rules.readAsBytes(),
        catalogVersion:
            jsonDecode(
                  File('assets/db/export_manifest.json').readAsStringSync(),
                )['db_version']
                as String,
        rulesVersion:
            jsonDecode(
                  File(
                    'assets/db/interaction_db_manifest.json',
                  ).readAsStringSync(),
                )['interaction_db_version']
                as String,
      );

      final store = ReleaseStore(documents: documents, bundle: bundle);
      final generation = await store.open();
      addTearDown(generation.close);

      expect(generation.record.catalogVersion, bundle.catalogVersion);
      expect(generation.rules, isNotNull);
      expect(await generation.core.validateCatalogSnapshot(), isNotNull);
    },
    skip: volume == null ? 'needs PG_RELEASE_FULL_VOLUME' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
