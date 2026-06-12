// Match-level dedupe tests for the evidence section adapter — mirrors
// the verified dsld_id 315678 shape where the SAME study matched via
// both the elemental row ('Magnesium') and the compound row
// ('Magnesium Glycinate'), appearing twice in clinical_matches with
// the same study_id.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/evidence_section.dart';

Map<String, dynamic> _mgMatch({
  required String ingredient,
  String studyId = 'INGR_MAGNESIUM_GENERIC',
  String evidenceLevel = 'ingredient-human',
  int enrollment = 2500,
  List<Map<String, dynamic>>? refs,
}) {
  return {
    'ingredient': ingredient,
    'standard_name': ingredient,
    'study_id': studyId,
    'id': studyId,
    'study_name': 'Magnesium (Generic)',
    'evidence_level': evidenceLevel,
    'study_type': 'meta-analysis',
    'total_enrollment': enrollment,
    'references_structured':
        refs ??
        [
          {'pmid': '11111111', 'title': 'Magnesium RCT'},
        ],
  };
}

void main() {
  group('dedupeClinicalMatches', () {
    test('same study via elemental + compound rows counts once', () {
      final deduped = dedupeClinicalMatches([
        _mgMatch(ingredient: 'Magnesium'),
        _mgMatch(ingredient: 'Magnesium Glycinate'),
      ]);
      expect(deduped, hasLength(1));
      expect(deduped.single['ingredient'], 'Magnesium');
    });

    test('falls back to id when study_id is missing or empty', () {
      final a = _mgMatch(ingredient: 'Magnesium')
        ..remove('study_id')
        ..['study_id'] = '';
      final b = _mgMatch(ingredient: 'Magnesium Glycinate')..remove('study_id');
      expect(dedupeClinicalMatches([a, b]), hasLength(1));
    });

    test('matches with no identity are kept (never drop evidence)', () {
      final a = _mgMatch(ingredient: 'Magnesium')
        ..remove('study_id')
        ..remove('id');
      final b = _mgMatch(ingredient: 'Magnesium Glycinate')
        ..remove('study_id')
        ..remove('id');
      expect(dedupeClinicalMatches([a, b]), hasLength(2));
    });

    test('distinct studies still count separately', () {
      final deduped = dedupeClinicalMatches([
        _mgMatch(ingredient: 'Magnesium'),
        _mgMatch(
          ingredient: 'Zinc',
          studyId: 'INGR_ZINC_GENERIC',
          enrollment: 800,
        ),
      ]);
      expect(deduped, hasLength(2));
    });
  });

  group('downstream computation on deduped matches', () {
    test('enrollment sums once for a duplicated study', () {
      final deduped = dedupeClinicalMatches([
        _mgMatch(ingredient: 'Magnesium', enrollment: 2500),
        _mgMatch(ingredient: 'Magnesium Glycinate', enrollment: 2500),
      ]);
      expect(evidenceTotalEnrollment(deduped), 2500);
      expect(evidenceTotalStudies(deduped), 1);
      expect(evidenceCitations(deduped), hasLength(1));
    });

    test('distinct studies sum enrollment and counts separately', () {
      final deduped = dedupeClinicalMatches([
        _mgMatch(ingredient: 'Magnesium', enrollment: 2500),
        _mgMatch(
          ingredient: 'Zinc',
          studyId: 'INGR_ZINC_GENERIC',
          enrollment: 800,
          refs: [
            {'pmid': '22222222', 'title': 'Zinc RCT'},
          ],
        ),
      ]);
      expect(evidenceTotalEnrollment(deduped), 3300);
      expect(evidenceTotalStudies(deduped), 2);
      expect(evidenceCitations(deduped), hasLength(2));
    });

    test('tier unaffected by dedupe — duplicate strong match', () {
      final deduped = dedupeClinicalMatches([
        _mgMatch(ingredient: 'Magnesium', evidenceLevel: 'product-human'),
        _mgMatch(
          ingredient: 'Magnesium Glycinate',
          evidenceLevel: 'product-human',
        ),
      ]);
      expect(evidenceTier(deduped), EvidenceTier.strong);
    });
  });
}
