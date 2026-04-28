import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this.bytes);

  final Uint8List bytes;

  @override
  Future<ByteData> load(String key) async {
    return ByteData.sublistView(bytes);
  }
}

void main() {
  group('ensureCoreDatabaseAvailable', () {
    test('copies the bundled database when the local file is missing', () async {
      final tempDir = await Directory.systemTemp.createTemp('pharmaguide-db');
      addTearDown(() async => tempDir.delete(recursive: true));

      final dbPath = '${tempDir.path}/pharmaguide_core.db';
      final bundle = _FakeAssetBundle(Uint8List.fromList([1, 2, 3, 4]));

      await ensureCoreDatabaseAvailable(dbPath: dbPath, bundle: bundle);

      final file = File(dbPath);
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), [1, 2, 3, 4]);
    });

    test(
      'keeps the on-disk database when its byte length matches the bundle',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('pharmaguide-db');
        addTearDown(() async => tempDir.delete(recursive: true));

        final dbPath = '${tempDir.path}/pharmaguide_core.db';
        final file = File(dbPath);
        // Same length as the bundle below (4 bytes) — the byte-length check
        // treats this as "already up to date" and leaves the file alone.
        // This branch also protects an OTA-downloaded catalog whose bytes
        // happen to match the bundled asset.
        await file.writeAsBytes([9, 9, 9, 9]);

        final bundle = _FakeAssetBundle(Uint8List.fromList([1, 2, 3, 4]));
        await ensureCoreDatabaseAvailable(dbPath: dbPath, bundle: bundle);

        expect(await file.readAsBytes(), [9, 9, 9, 9]);
      },
    );

    test(
      'replaces the on-disk database when the bundle has a different byte length',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('pharmaguide-db');
        addTearDown(() async => tempDir.delete(recursive: true));

        final dbPath = '${tempDir.path}/pharmaguide_core.db';
        final file = File(dbPath);
        // Stale on-disk DB from a prior install (3 bytes). The bundle now
        // ships a different size — the new logic must re-materialize the
        // bundled asset so users get the fresh catalog after upgrade.
        await file.writeAsBytes([9, 9, 9]);

        final bundle = _FakeAssetBundle(Uint8List.fromList([1, 2, 3, 4]));
        await ensureCoreDatabaseAvailable(dbPath: dbPath, bundle: bundle);

        expect(await file.readAsBytes(), [1, 2, 3, 4]);
      },
    );
  });
}
