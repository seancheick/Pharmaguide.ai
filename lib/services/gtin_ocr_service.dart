import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pharmaguide/services/gtin.dart';

/// A reader is injected at the UI boundary so tests never depend on native
/// ML Kit. OCR proposes text only; [GtinIdentity] remains the single identity
/// authority and every candidate must pass its check digit.
typedef GtinTextReader = Future<String> Function(XFile file);

/// Finds validated GTINs in OCR text, preserving their exact printed width.
///
/// Retail screenshots often contain several identifiers (TCIN, DPCI, and
/// UPC). This function deliberately returns only check-digit-valid GTINs;
/// callers must still ask the user to confirm which candidate is the product
/// UPC. Store-specific identifiers are never promoted to product identity.
List<GtinIdentity> extractGtinCandidatesFromText(String text) {
  final candidates = <String, GtinIdentity>{};
  final matches = RegExp(r'(?<!\d)(?:\d[\s-]?){8,14}(?!\d)').allMatches(text);
  for (final match in matches) {
    final raw = match.group(0);
    if (raw == null) continue;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    try {
      final identity = GtinIdentity.parse(digits);
      candidates[identity.canonicalGtin14] = identity;
    } on FormatException {
      // OCR frequently drops or adds a digit. Invalid candidates are
      // discarded rather than corrected heuristically.
    }
  }
  return List.unmodifiable(candidates.values);
}

/// Reads Latin text from a local image with on-device ML Kit.
///
/// The plugin accepts a file path, so the caller's original image remains
/// private and no network service receives the label. The recognizer is
/// always closed, including when native processing fails.
Future<String> readLatinTextFromFile(XFile file) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(
      InputImage.fromFilePath(file.path),
    );
    return result.text;
  } finally {
    await recognizer.close();
  }
}

/// Convenience adapter for the contribution identity sheet.
Future<List<GtinIdentity>> readGtinCandidatesFromFile(XFile file) async {
  final text = await readLatinTextFromFile(file);
  return extractGtinCandidatesFromText(text);
}
