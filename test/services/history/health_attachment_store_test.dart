import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pharmaguide/services/history/health_attachment_store.dart';

void main() {
  test('imports into the private root and clears every attachment', () async {
    final temp = await Directory.systemTemp.createTemp(
      'pharmaguide-health-attachment-test-',
    );
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final privateRoot = Directory('${temp.path}/private');
    final selected = File('${temp.path}/Selected Lab Photo.PNG');
    await selected.writeAsBytes(const [1, 2, 3, 4]);
    final store = HealthAttachmentStore(root: () async => privateRoot);

    final imported = await store.importImage(XFile(selected.path));

    expect(imported.path, startsWith(privateRoot.path));
    expect(imported.path, isNot(selected.path));
    expect(imported.displayName, 'Selected Lab Photo.PNG');
    expect(imported.mimeType, 'image/png');
    expect(await File(imported.path).readAsBytes(), [1, 2, 3, 4]);

    await store.clearAll();
    expect(await privateRoot.exists(), isFalse);
  });

  test('refuses to delete files outside its private root', () async {
    final temp = await Directory.systemTemp.createTemp(
      'pharmaguide-health-attachment-guard-',
    );
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final store = HealthAttachmentStore(
      root: () async => Directory('${temp.path}/private'),
    );

    expect(
      () => store.delete('${temp.path}/unrelated.jpg'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
