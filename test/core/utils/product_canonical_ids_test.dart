import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/utils/product_canonical_ids.dart';

void main() {
  group('markerCanonicalIdsFromDetailBlob', () {
    // delivers_markers is the pipeline's "marker-via-ingredient" evidence
    // routing payload: a source botanical (turmeric) declares the bioactive
    // marker it delivers (curcumin) so evidence routing reaches marker-keyed
    // research pairs the source canonical_id alone would miss. Shape per
    // build_final_db.py / enrich_supplements_v3.py: each entry is a map with
    // a `marker_canonical_id` field.

    test('extracts the marker a botanical source delivers (turmeric -> '
        'curcumin)', () {
      final blob = <String, dynamic>{
        'ingredients': [
          {
            'canonical_id': 'turmeric',
            'delivers_markers': [
              {
                'marker_canonical_id': 'curcumin',
                'marker_source_db': 'ingredient_quality_map',
                'estimated_dose_mg': null,
                'estimation_method': 'none',
              },
            ],
          },
        ],
      };

      expect(markerCanonicalIdsFromDetailBlob(blob), ['curcumin']);
    });

    test('also reads markers from ingredient_quality_data.ingredients', () {
      final blob = <String, dynamic>{
        'ingredient_quality_data': {
          'ingredients': [
            {
              'canonical_id': 'green_tea',
              'delivers_markers': [
                {'marker_canonical_id': 'egcg'},
              ],
            },
          ],
        },
      };

      expect(markerCanonicalIdsFromDetailBlob(blob), ['egcg']);
    });

    test('returns empty when an ingredient delivers no markers', () {
      final blob = <String, dynamic>{
        'ingredients': [
          {'canonical_id': 'vitamin_c'},
        ],
      };

      expect(markerCanonicalIdsFromDetailBlob(blob), isEmpty);
    });

    test('dedupes and normalizes markers across ingredients', () {
      final blob = <String, dynamic>{
        'ingredients': [
          {
            'canonical_id': 'turmeric',
            'delivers_markers': [
              {'marker_canonical_id': 'Curcumin'},
            ],
          },
          {
            'canonical_id': 'turmeric_root_extract',
            'delivers_markers': [
              {'marker_canonical_id': 'curcumin'},
            ],
          },
        ],
      };

      expect(markerCanonicalIdsFromDetailBlob(blob), ['curcumin']);
    });

    test('handles null / missing / malformed shapes gracefully', () {
      expect(markerCanonicalIdsFromDetailBlob(null), isEmpty);
      expect(markerCanonicalIdsFromDetailBlob(const {}), isEmpty);
      expect(
        markerCanonicalIdsFromDetailBlob(const {'ingredients': 'nope'}),
        isEmpty,
      );
      expect(
        markerCanonicalIdsFromDetailBlob(const {
          'ingredients': [
            {'canonical_id': 'turmeric', 'delivers_markers': 'nope'},
            {
              'canonical_id': 'x',
              'delivers_markers': [42, null, <String, dynamic>{}],
            },
          ],
        }),
        isEmpty,
      );
    });
  });

  group('source vs marker routing boundary', () {
    // Safety-critical: delivered markers must NOT leak into the source
    // canonical-id extraction that feeds the interaction / warning path.
    // They belong only to the marker extraction used for research evidence,
    // so a trace botanical can never manufacture a marker-keyed warning.
    test('delivered markers are excluded from source canonical IDs', () {
      final blob = <String, dynamic>{
        'ingredients': [
          {
            'canonical_id': 'turmeric',
            'delivers_markers': [
              {'marker_canonical_id': 'curcumin'},
            ],
          },
        ],
      };

      expect(canonicalIdsFromDetailBlob(blob), ['turmeric']);
      expect(canonicalIdsFromDetailBlob(blob), isNot(contains('curcumin')));
      expect(markerCanonicalIdsFromDetailBlob(blob), ['curcumin']);
    });
  });
}
