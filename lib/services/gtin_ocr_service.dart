import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pharmaguide/services/gtin.dart';

/// A reader is injected at the UI boundary so tests never depend on native
/// ML Kit. OCR proposes text only; [GtinIdentity] remains the single identity
/// authority and every candidate must pass its check digit.
typedef GtinTextReader = Future<String> Function(XFile file);

/// Finds validated GTINs in OCR text, preserving their exact printed width.
///
/// Digits may be separated by spaces or hyphens but never by a line break. A
/// printed UPC-A is read as "0  37000  12345  3" — the gap under the bars is
/// wide — so one separator is not enough; but allowing a newline lets two
/// unrelated numbers on consecutive lines merge into a run that passes a check
/// digit, and a confidently wrong identity is the worst outcome here.
///
/// Retail screenshots often contain several identifiers (TCIN, DPCI, and
/// UPC). This function deliberately returns only check-digit-valid GTINs;
/// callers must still ask the user to confirm which candidate is the product
/// UPC. Store-specific identifiers are never promoted to product identity.
List<GtinIdentity> extractGtinCandidatesFromText(String text) {
  final labeled = <String, GtinIdentity>{};
  final labeledPattern = RegExp(
    r'(?:(?:u\.?p\.?c\.?|gtin|ean(?:-?8|-?13|-?14)?|barcode))\s*[:#-]?\s*'
    r'((?:\d[ \t -]{0,3}){8,14})(?!\d)',
    caseSensitive: false,
  );
  for (final match in labeledPattern.allMatches(text)) {
    _addCandidate(labeled, match.group(1));
  }
  // A labeled product code suppresses nearby store identifiers (TCIN/DPCI).
  if (labeled.isNotEmpty) return List.unmodifiable(labeled.values);

  final candidates = <String, GtinIdentity>{};
  final matches =
      RegExp(r'(?<!\d)(?:\d[ \t -]{0,3}){8,14}(?!\d)').allMatches(text);
  for (final match in matches) {
    final before = text.substring(0, match.start);
    if (RegExp(
      r'(?:t\.?c\.?i\.?n|d\.?p\.?c\.?i)\s*[:#-]?\s*$',
      caseSensitive: false,
    ).hasMatch(before)) {
      continue;
    }
    _addCandidate(candidates, match.group(0));
  }
  return List.unmodifiable(candidates.values);
}

void _addCandidate(Map<String, GtinIdentity> candidates, String? raw) {
  if (raw == null) return;
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  try {
    final identity = GtinIdentity.parse(digits);
    candidates[identity.canonicalGtin14] = identity;
  } on FormatException {
    // OCR frequently drops or adds a digit. Never repair it heuristically.
  }
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
