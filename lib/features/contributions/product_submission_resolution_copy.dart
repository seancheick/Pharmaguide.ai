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

/// What a reviewer's request for new photos asks of the user, in the words
/// the status card and the capture sheet both show.
String productSubmissionRetakeRequest(
  ProductSubmissionResolutionCode? reason,
  Set<ProductSubmissionEvidenceCategory> panels,
) {
  // Label order (front, facts, ingredients, …) whatever order they arrive in.
  final names = [
    for (final category
        in panels.toList()..sort((a, b) => a.index.compareTo(b.index)))
      _panelName(category),
  ];
  final list = names.length < 2
      ? names.join()
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  final why = switch (reason) {
    ProductSubmissionResolutionCode.photoQuality =>
      ' The last one was too blurry or dark to read — more light and a '
          'steady hand usually fix it.',
    ProductSubmissionResolutionCode.labelUnreadable =>
      ' The last one wasn’t readable enough to check. Hold the label flat '
          'and in focus.',
    ProductSubmissionResolutionCode.missingPanel =>
      ' It wasn’t in the photos you sent.',
    _ => '',
  };
  final photos = names.length < 2 ? 'a new photo' : 'new photos';
  return 'A reviewer needs $photos of the $list.$why';
}

String _panelName(
  ProductSubmissionEvidenceCategory category,
) => switch (category) {
  ProductSubmissionEvidenceCategory.frontIdentity => 'front of the package',
  ProductSubmissionEvidenceCategory.supplementFacts => 'Supplement Facts panel',
  ProductSubmissionEvidenceCategory.ingredientDisclosure =>
    'Other Ingredients list',
  ProductSubmissionEvidenceCategory.barcode => 'barcode',
  ProductSubmissionEvidenceCategory.directionsWarnings =>
    'directions and warnings',
  ProductSubmissionEvidenceCategory.lotExpiry => 'lot number and expiry date',
};
