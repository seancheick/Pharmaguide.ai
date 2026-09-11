import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pharmaguide/services/gtin.dart';
import 'package:pharmaguide/services/gtin_ocr_service.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

/// Reads the text printed in one submission photo, on the phone.
typedef ReadSubmissionPhotoText =
    Future<String> Function(ProductSubmissionPhoto photo);

/// What on-device text suggests a photo shows.
///
/// Capture-screen suggestions only. Nothing here decides a submission's
/// evidence or blocks a photo, and no recognized text leaves the phone: the
/// user can always keep a photo, and the reviewer remains the authority on
/// what it shows.
class PanelHints {
  const PanelHints({
    this.showsFactsHeading = false,
    this.showsFactsPanel = false,
    this.showsDirectionsOrWarnings = false,
    this.showsOtherIngredients = false,
    this.showsSubmissionBarcode = false,
    this.conflictingBarcode,
  });

  static const none = PanelHints();

  /// The printed "Supplement Facts" heading itself.
  final bool showsFactsHeading;

  /// The heading or the table around it (serving size, % Daily Value), so a
  /// panel photographed with its heading cut off still counts.
  final bool showsFactsPanel;
  final bool showsDirectionsOrWarnings;
  final bool showsOtherIngredients;

  /// The barcode the user scanned, printed in this photo.
  final bool showsSubmissionBarcode;

  /// A different full-width barcode, present only when the scanned one is
  /// not. Short runs never count: a lot code or date passes an 8-digit check
  /// digit one time in ten.
  final GtinIdentity? conflictingBarcode;
}

final _factsHeading = RegExp(r'supplement\s*facts');
final _factsTable = RegExp(
  r'serving\s*size|amount\s*per\s*serving|daily\s*value|%\s*dv\b|'
  r'servings?\s*per\s*container',
);
final _directionsOrWarnings = RegExp(
  r'directions|suggested\s*use|recommended\s*use|\bwarnings?\b|\bcaution\b|'
  r'keep\s*out\s*of\s*(?:the\s*)?reach|'
  r'consult\s*(?:your|a)\s*(?:physician|doctor|health)',
);
final _otherIngredients = RegExp(r'\b(?:other|inactive)\s*ingredients?\b');

PanelHints readPanelHints(String text, {required GtinIdentity submission}) {
  if (text.trim().isEmpty) return PanelHints.none;
  final lower = text.toLowerCase();
  final heading = _factsHeading.hasMatch(lower);

  var showsSubmission = false;
  GtinIdentity? conflict;
  // Barcode reading has one owner; this only compares what it found.
  for (final candidate in extractGtinCandidatesFromText(text)) {
    if (candidate.canonicalGtin14 == submission.canonicalGtin14 ||
        candidate.lookupCandidates.any(submission.lookupCandidates.contains)) {
      showsSubmission = true;
    } else if (conflict == null && candidate.rawDigits.length >= 12) {
      conflict = candidate;
    }
  }

  return PanelHints(
    showsFactsHeading: heading,
    showsFactsPanel: heading || _factsTable.hasMatch(lower),
    showsDirectionsOrWarnings: _directionsOrWarnings.hasMatch(lower),
    showsOtherIngredients: _otherIngredients.hasMatch(lower),
    showsSubmissionBarcode: showsSubmission,
    conflictingBarcode: showsSubmission ? null : conflict,
  );
}

/// The production reader: ML Kit needs a file, so the prepared bytes are
/// written to app-private temporary storage for the read and deleted after.
Future<String> readSubmissionPhotoText(ProductSubmissionPhoto photo) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/panel_hint_${photo.photoId}.jpg');
  await file.writeAsBytes(photo.bytes, flush: true);
  try {
    return await readLatinTextFromFile(XFile(file.path));
  } finally {
    try {
      await file.delete();
    } on Object {
      // The OS clears its temporary directory; a leftover is not evidence.
    }
  }
}
