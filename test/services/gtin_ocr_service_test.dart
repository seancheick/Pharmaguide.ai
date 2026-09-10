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

  test('returns multiple valid candidates for explicit user choice', () {
    final candidates = extractGtinCandidatesFromText(
      'TCIN 96385074 UPC 036000291452',
    );
    expect(candidates.map((candidate) => candidate.submissionIdentity), [
      '96385074',
      '036000291452',
    ]);
  });
}
