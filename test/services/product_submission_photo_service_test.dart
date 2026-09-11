import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pharmaguide/services/product_submission_photo_service.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

void main() {
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
