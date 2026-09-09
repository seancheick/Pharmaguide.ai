import 'package:pharmaguide/services/product_submission_service.dart';

/// One translation of the public resolution vocabulary for history and
/// intake. Internal review notes are never an input to consumer copy.
String? productSubmissionResolutionGuidance(
  ProductSubmissionResolutionCode? code, {
  String? detail,
}) => switch (code) {
  ProductSubmissionResolutionCode.photoQuality =>
    'The photos were too blurry or dark to read. Try again with more '
        'light and steadier hands.',
  ProductSubmissionResolutionCode.missingPanel =>
    'We couldn’t see the full Supplement Facts panel. Try again and '
        'capture the whole panel.',
  ProductSubmissionResolutionCode.labelUnreadable =>
    'The label wasn’t readable enough to verify. A retake with the '
        'label flat and in focus usually fixes this.',
  ProductSubmissionResolutionCode.productIdentityMismatch =>
    'The photos didn’t match the scanned product. Scan the barcode again '
        'and photograph that same package.',
  ProductSubmissionResolutionCode.notASupplement =>
    'This product isn’t a dietary supplement, so it doesn’t belong in '
        'the PharmaGuide catalog.',
  ProductSubmissionResolutionCode.alreadyInCatalog =>
    'Good news — this product is already in the catalog.',
  ProductSubmissionResolutionCode.duplicateSubmission =>
    'Someone beat you to it — this product is already on its way into '
        'the catalog.',
  ProductSubmissionResolutionCode.other => detail,
  null => null,
};
