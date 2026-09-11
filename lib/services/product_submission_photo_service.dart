import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

typedef SanitizeProductSubmissionPhoto =
    Future<Uint8List> Function(Uint8List sourceBytes);

/// Picks one image without requesting metadata, then re-encodes it as JPEG.
///
/// Re-encoding with [keepExif] false strips EXIF metadata. The UI must still
/// warn users not to photograph visible personal information because no
/// metadata operation can remove text visible in the pixels.
Future<ProductSubmissionPhoto?> pickProductSubmissionPhoto({
  required ImagePicker picker,
  required Set<ProductSubmissionEvidenceCategory> categories,
  required ImageSource source,
}) async {
  final file = await picker.pickImage(
    source: source,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  return buildProductSubmissionPhotoFromFile(
    file: file,
    categories: categories,
  );
}

/// Several library images at once, each prepared exactly like a single pick.
Future<({List<ProductSubmissionPhoto> photos, int unreadable})>
pickProductSubmissionPhotos({
  required ImagePicker picker,
  required int limit,
}) async {
  final files = await picker.pickMultiImage(
    limit: limit,
    requestFullMetadata: false,
  );
  final prepared = await buildProductSubmissionPhotosFromFiles(
    files.take(limit).toList(),
  );
  final overflow = files.length > limit ? files.length - limit : 0;
  return (photos: prepared.photos, unreadable: prepared.unreadable + overflow);
}

/// One file that cannot be prepared is counted, never fatal to the rest.
/// Every photo comes back tagged as the front until the user sorts it.
@visibleForTesting
Future<({List<ProductSubmissionPhoto> photos, int unreadable})>
buildProductSubmissionPhotosFromFiles(
  List<XFile> files, {
  SanitizeProductSubmissionPhoto sanitizer = _sanitizeProductSubmissionPhoto,
}) async {
  final photos = <ProductSubmissionPhoto>[];
  var unreadable = 0;
  for (final file in files) {
    try {
      photos.add(
        await buildProductSubmissionPhotoFromFile(
          file: file,
          categories: const {ProductSubmissionEvidenceCategory.frontIdentity},
          sanitizer: sanitizer,
        ),
      );
    } on FileSystemException {
      unreadable += 1;
    } on ProductSubmissionValidationException {
      unreadable += 1;
    }
  }
  return (photos: photos, unreadable: unreadable);
}

@visibleForTesting
Future<ProductSubmissionPhoto> buildProductSubmissionPhotoFromFile({
  required XFile file,
  required Set<ProductSubmissionEvidenceCategory> categories,
  SanitizeProductSubmissionPhoto sanitizer = _sanitizeProductSubmissionPhoto,
}) async {
  _supportedContentType(file);
  if (await file.length() > ProductSubmissionPhoto.maxByteSize) {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.photoTooLarge,
    );
  }

  final sourceBytes = await file.readAsBytes();
  if (sourceBytes.isEmpty) {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.emptyPhoto,
    );
  }
  if (sourceBytes.length > ProductSubmissionPhoto.maxByteSize) {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.photoTooLarge,
    );
  }

  late final Uint8List sanitizedBytes;
  try {
    sanitizedBytes = await sanitizer(sourceBytes);
  } on Object {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.photoSanitizationFailed,
    );
  }
  if (sanitizedBytes.isEmpty) {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.photoSanitizationFailed,
    );
  }

  return ProductSubmissionPhoto(
    categories: categories,
    bytes: sanitizedBytes,
    contentType: 'image/jpeg',
  );
}

Future<Uint8List> _sanitizeProductSubmissionPhoto(Uint8List sourceBytes) async {
  final result = await FlutterImageCompress.compressWithList(
    sourceBytes,
    minWidth: 2400,
    minHeight: 2400,
    quality: 90,
    format: CompressFormat.jpeg,
    keepExif: false,
  );
  return Uint8List.fromList(result);
}

String _supportedContentType(XFile file) {
  final rawDeclared = file.mimeType?.split(';').first.trim().toLowerCase();
  final declared = rawDeclared == null || rawDeclared.isEmpty
      ? null
      : rawDeclared;
  final normalized = declared == 'image/jpg' ? 'image/jpeg' : declared;
  if (normalized != null) {
    if (ProductSubmissionPhoto.allowedContentTypes.contains(normalized)) {
      return normalized;
    }
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.unsupportedPhotoContentType,
    );
  }

  final extension = file.name.toLowerCase().split('.').last;
  final inferred = switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'webp' => 'image/webp',
    _ => null,
  };
  if (inferred == null) {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.unsupportedPhotoContentType,
    );
  }
  return inferred;
}
