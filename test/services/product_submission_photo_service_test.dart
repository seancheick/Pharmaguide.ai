import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pharmaguide/services/product_submission_photo_service.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

class OverflowPicker extends ImagePicker {
  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async => [
    for (var i = 0; i < 9; i++)
      XFile.fromData(
        Uint8List.fromList([i]),
        name: 'file$i.txt',
        mimeType: 'text/plain',
      ),
  ];
}

void main() {
  test('counts selections exceeding the native picker limit', () async {
    final result = await pickProductSubmissionPhotos(
      picker: OverflowPicker(),
      limit: 8,
    );
    expect(result.photos.length + result.unreadable, 9);
  });

  test('an inaccessible file does not discard readable selections', () async {
    final directory = await Directory.systemTemp.createTemp(
      'submission-photo-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final result = await buildProductSubmissionPhotosFromFiles([
      XFile.fromData(
        Uint8List.fromList([1]),
        name: 'before.jpg',
        mimeType: 'image/jpeg',
      ),
      XFile('${directory.path}/missing.jpg'),
      XFile.fromData(
        Uint8List.fromList([2]),
        name: 'after.jpg',
        mimeType: 'image/jpeg',
      ),
    ], sanitizer: (bytes) async => bytes);
    expect(result.photos, hasLength(2));
    expect(result.unreadable, 1);
  });

  test('prepares each library file and counts the ones it cannot', () async {
    final result = await buildProductSubmissionPhotosFromFiles([
      XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'facts.jpg',
        mimeType: 'image/jpeg',
      ),
      XFile.fromData(
        Uint8List.fromList([4]),
        name: 'notes.txt',
        mimeType: 'text/plain',
      ),
      XFile.fromData(Uint8List(0), name: 'empty.png', mimeType: 'image/png'),
    ], sanitizer: (bytes) async => bytes);

    expect(result.photos, hasLength(1));
    expect(result.unreadable, 2);
    // Tagged as the front only until the user sorts them.
    expect(result.photos.single.categories, {
      ProductSubmissionEvidenceCategory.frontIdentity,
    });
  });
}
