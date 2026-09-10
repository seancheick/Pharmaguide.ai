import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/gtin_ocr_service.dart';

void main() {
  test('extracts the valid UPC from a Target-style listing', () {
    final candidates = extractGtinCandidatesFromText('''
      Additional information
      TCIN: 84799482
      DPCI: 245-05-3743
      UPC: 030772032565
    ''');

    expect(candidates, hasLength(1));
    expect(candidates.single.submissionIdentity, '030772032565');
    expect(candidates.single.canonicalGtin14, '00030772032565');
  });

  test('rejects invalid OCR digits instead of repairing them', () {
    expect(extractGtinCandidatesFromText('UPC 030772032564'), isEmpty);
  });

  test('prefers labeled product codes over valid store identifiers', () {
    final candidates = extractGtinCandidatesFromText(
      'TCIN 96385074 UPC 036000291452',
    );
    expect(candidates.map((candidate) => candidate.submissionIdentity), [
      '036000291452',
    ]);
  });

  test('offers a choice when more than one product code is labeled', () {
    final candidates = extractGtinCandidatesFromText(
      'UPC 036000291452 EAN-13 4006381333931',
    );
    expect(candidates.map((candidate) => candidate.submissionIdentity), [
      '036000291452',
      '4006381333931',
    ]);
  });

  test('reads a barcode printed with wide gaps under the bars', () {
    // A UPC-A under its bars is printed "0  37000  12345  3": the gap is wide
    // and OCR emits more than one space. One optional separator missed it.
    final wide = extractGtinCandidatesFromText('0  37000  12345  3');

    expect(wide.map((g) => g.canonicalGtin14), ['00037000123453']);
    expect(
      extractGtinCandidatesFromText('UPC 0  37000  12345  3')
          .map((g) => g.canonicalGtin14),
      ['00037000123453'],
    );
  });

  test('never joins digits across a line break into an identity', () {
    // Two unrelated runs on consecutive lines can concatenate into a string
    // that passes a check digit. A confidently wrong identity is the worst
    // outcome this reader can produce, so a newline never joins digits.
    expect(extractGtinCandidatesFromText('Lot 0370001\n23453 ct'), isEmpty);
  });

  test('still finds a code labelled on the line above it', () {
    // The gap between the label and the number may cross lines; only the gap
    // between digits may not.
    expect(
      extractGtinCandidatesFromText('UPC\n762111000217')
          .map((g) => g.canonicalGtin14),
      ['00762111000217'],
    );
  });
}
