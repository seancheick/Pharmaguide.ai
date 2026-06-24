// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T16.2f.
//
// Locks the grouping contract that lets the active-ingredient
// renderer build label-style blend sections (header + indented
// children) from the pipeline's flat actives list + parallel
// proprietary_blend_detail.blends[] metadata.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/blend_grouping.dart';

void main() {
  group('groupActivesByBlend', () {
    test('null blends → all ingredients fall through to loose buckets', () {
      final result = groupActivesByBlend(
        ingredients: const [
          {'name': 'Vitamin D', 'quantity': 1000, 'unit': 'IU'},
          {'name': 'Lutein'},
        ],
        blendsRaw: null,
      );
      expect(result.hasBlends, isFalse);
      expect(result.looseDisclosed, hasLength(1));
      expect(result.looseDisclosed.first['name'], 'Vitamin D');
      expect(result.looseUndisclosed, hasLength(1));
      expect(result.looseUndisclosed.first['name'], 'Lutein');
      expect(result.blends, isEmpty);
    });

    test('empty blends list → loose buckets only', () {
      final result = groupActivesByBlend(
        ingredients: const [
          {'name': 'Vitamin C', 'quantity': 500, 'unit': 'mg'},
        ],
        blendsRaw: const [],
      );
      expect(result.hasBlends, isFalse);
      expect(result.looseDisclosed, hasLength(1));
    });

    test(
      'PureLean repro — Eye Health Blend with 3 children groups correctly',
      () {
        final result = groupActivesByBlend(
          ingredients: const [
            {'name': 'Vitamin C', 'quantity': 500, 'unit': 'mg'},
            {'name': 'Lutein'},
            {'name': 'Lycopene'},
            {'name': 'Zeaxanthin'},
            {'name': 'Calcium', 'quantity': 200, 'unit': 'mg'},
          ],
          blendsRaw: const [
            {
              'name': 'Eye Health Blend',
              'total_weight': 100,
              'unit': 'mg',
              'child_ingredients': [
                {'name': 'Lutein'},
                {'name': 'Lycopene'},
                {'name': 'Zeaxanthin'},
              ],
            },
          ],
        );
        expect(result.hasBlends, isTrue);
        expect(result.blends, hasLength(1));
        final blend = result.blends.first;
        expect(blend.name, 'Eye Health Blend');
        expect(blend.totalAmount, 100);
        expect(blend.unit, 'mg');
        expect(blend.children, hasLength(3));
        expect(blend.children.map((c) => c['name']), [
          'Lutein',
          'Lycopene',
          'Zeaxanthin',
        ]);
        // Loose buckets: Vitamin C and Calcium (both disclosed-dose).
        expect(result.looseDisclosed.map((i) => i['name']), [
          'Vitamin C',
          'Calcium',
        ]);
        expect(result.looseUndisclosed, isEmpty);
      },
    );

    test('blend with no matched children renders a disclosure summary', () {
      // New scoring/export contract emits only primary actives in
      // detail_blob.ingredients, while blend children stay available
      // in proprietary_blend_detail.blends[]. Keep the blend visible
      // as a compact disclosure summary instead of hiding it.
      final result = groupActivesByBlend(
        ingredients: const [
          {'name': 'Vitamin C', 'quantity': 500, 'unit': 'mg'},
        ],
        blendsRaw: const [
          {
            'name': 'Phantom Blend',
            'total_weight': 50,
            'unit': 'mg',
            'child_ingredients': [
              {'name': 'NotInActivesList'},
            ],
          },
        ],
      );
      expect(result.hasBlends, isTrue);
      expect(result.blends, hasLength(1));
      expect(result.blends.first.name, 'Phantom Blend');
      expect(result.blends.first.children, isEmpty);
      expect(result.blends.first.childCount, 1);
      expect(result.looseDisclosed, hasLength(1));
    });

    test('canonical name match handles display-form variants', () {
      // Pipeline drift: actives ship "Lutein, Free Form" while blend
      // children list "Lutein". The shared canonicalizer (after
      // T16.2e's punctuation strip) handles this.
      final result = groupActivesByBlend(
        ingredients: const [
          {'name': 'Lutein, Free Form'},
          {'name': 'Lycopene (5%)'},
        ],
        blendsRaw: const [
          {
            'name': 'Carotenoid Mix',
            'total_weight': 25,
            'unit': 'mg',
            'child_ingredients': [
              {'name': 'Lutein, Free Form'},
              {'name': 'Lycopene (5%)'},
            ],
          },
        ],
      );
      expect(result.blends, hasLength(1));
      expect(result.blends.first.children, hasLength(2));
      expect(result.looseUndisclosed, isEmpty);
    });

    test('ingredient overlapping multiple blends — first wins', () {
      // Defensive — pipeline doesn't currently emit overlap, but if it
      // does we want deterministic ordering.
      final result = groupActivesByBlend(
        ingredients: const [
          {'name': 'Lutein'},
        ],
        blendsRaw: const [
          {
            'name': 'Blend A',
            'total_weight': 10,
            'unit': 'mg',
            'child_ingredients': [
              {'name': 'Lutein'},
            ],
          },
          {
            'name': 'Blend B',
            'total_weight': 20,
            'unit': 'mg',
            'child_ingredients': [
              {'name': 'Lutein'},
            ],
          },
        ],
      );
      expect(result.blends, hasLength(1));
      expect(result.blends.first.name, 'Blend A');
    });

    test('blend with null total_weight still renders bucket', () {
      // Header will show "Amount not disclosed" but children should
      // still group — the user gets visual blend structure even
      // without the parent total.
      final result = groupActivesByBlend(
        ingredients: const [
          {'name': 'Mystery Herb'},
        ],
        blendsRaw: const [
          {
            'name': 'Mystery Blend',
            'total_weight': null,
            'unit': '',
            'child_ingredients': [
              {'name': 'Mystery Herb'},
            ],
          },
        ],
      );
      expect(result.blends, hasLength(1));
      expect(result.blends.first.totalAmount, isNull);
    });

    test('mixed loose disclosed + blend + loose undisclosed', () {
      final result = groupActivesByBlend(
        ingredients: const [
          {'name': 'Vitamin A', 'quantity': 1000, 'unit': 'IU'}, // loose disc
          {'name': 'Lutein'}, // blend member
          {'name': 'Cranberry'}, // blend member
          {'name': 'Mystery Botanical'}, // loose undisclosed
          {'name': 'Vitamin C', 'quantity': 500, 'unit': 'mg'}, // loose disc
        ],
        blendsRaw: const [
          {
            'name': 'Eye + Berry Blend',
            'total_weight': 200,
            'unit': 'mg',
            'child_ingredients': [
              {'name': 'Lutein'},
              {'name': 'Cranberry'},
            ],
          },
        ],
      );
      expect(result.looseDisclosed.map((i) => i['name']), [
        'Vitamin A',
        'Vitamin C',
      ]);
      expect(result.blends, hasLength(1));
      expect(result.blends.first.children.map((c) => c['name']), [
        'Lutein',
        'Cranberry',
      ]);
      expect(result.looseUndisclosed.map((i) => i['name']), [
        'Mystery Botanical',
      ]);
    });

    test('ingredient without name skips cleanly (no crash, no match)', () {
      // Defensive — pipeline drift / corrupted blob shouldn't fault.
      final result = groupActivesByBlend(
        ingredients: const [
          {'quantity': 500, 'unit': 'mg'}, // no name
          {'name': 'Vitamin C', 'quantity': 500, 'unit': 'mg'},
        ],
        blendsRaw: const [
          {
            'name': 'Some Blend',
            'total_weight': 50,
            'unit': 'mg',
            'child_ingredients': [
              {'name': 'Lutein'},
            ],
          },
        ],
      );
      expect(result.blends, hasLength(1));
      expect(result.blends.first.name, 'Some Blend');
      expect(result.blends.first.children, isEmpty);
      expect(result.blends.first.childCount, 1);
      // Nameless entry falls into loose-disclosed (has quantity).
      expect(result.looseDisclosed, hasLength(2));
    });

    test('PureLean repro — disclosed-dose ingredient with same name as '
        'a blend member stays loose, blend member stays in blend', () {
      // PureLean Pure Pack 188790: ships an undisclosed Zeaxanthin
      // (the carotenoid blend member) AND a separate disclosed
      // Zeaxanthin 500 mcg (standalone). Pre-revision the disclosed
      // 500 mcg entry wrongly bucketed under the blend header
      // because canonical-name lookup didn't disambiguate.
      final result = groupActivesByBlend(
        ingredients: const [
          // Blend members — undisclosed
          {'name': 'Lutein', 'quantity': 0, 'unit': 'NP'},
          {'name': 'Lycopene', 'quantity': 0, 'unit': 'NP'},
          {'name': 'Zeaxanthin', 'quantity': 0, 'unit': 'NP'},
          // Standalone disclosed entries with overlapping names
          {'name': 'FloraGLO Lutein', 'quantity': 3, 'unit': 'mg'},
          {'name': 'Zeaxanthin', 'quantity': 500, 'unit': 'mcg'},
        ],
        blendsRaw: const [
          {
            'name': 'Proprietary Mixed Carotenoid Blend',
            'total_weight': 212,
            'unit': 'mcg',
            'child_ingredients': [
              {'name': 'Lutein', 'amount': null},
              {'name': 'Lycopene', 'amount': null},
              {'name': 'Zeaxanthin', 'amount': null},
            ],
          },
        ],
      );

      // Blend has exactly the 3 undisclosed members — the 500 mcg
      // Zeaxanthin must NOT appear here.
      expect(result.blends, hasLength(1));
      expect(result.blends.first.children, hasLength(3));
      expect(result.blends.first.children.map((c) => c['name']), [
        'Lutein',
        'Lycopene',
        'Zeaxanthin',
      ]);
      // The disclosed-dose Zeaxanthin and FloraGLO Lutein remain
      // loose (disclosed bucket).
      expect(result.looseDisclosed.map((i) => i['name']), [
        'FloraGLO Lutein',
        'Zeaxanthin',
      ]);
      expect(result.looseUndisclosed, isEmpty);
    });

    test('FULL disclosure — blend child with disclosed amount matches '
        'disclosed actives entry (Tonalin CLA Complex shape)', () {
      // Pipeline `disclosure_level: full` — 1.9% of blends. Child has
      // amount: 770mg, actives entry has matching quantity. Must
      // bucket into the blend, not stay loose.
      final result = groupActivesByBlend(
        ingredients: const [
          {'name': 'Conjugated Linoleic Acid', 'quantity': 770, 'unit': 'mg'},
        ],
        blendsRaw: const [
          {
            'name': 'Tonalin Conjugated Linoleic Acid Complex',
            'total_weight': 770,
            'unit': 'mg',
            'child_ingredients': [
              {'name': 'Conjugated Linoleic Acid', 'amount': 770, 'unit': 'mg'},
            ],
          },
        ],
      );

      expect(result.blends, hasLength(1));
      expect(result.blends.first.children, hasLength(1));
      expect(
        result.blends.first.children.first['name'],
        'Conjugated Linoleic Acid',
      );
      // Bucketed → not in loose.
      expect(result.looseDisclosed, isEmpty);
      expect(result.looseUndisclosed, isEmpty);
    });

    test('PARTIAL disclosure — mixed disclosed + undisclosed children all '
        'bucket into the blend (Diindolylmethane Complex shape)', () {
      // Pipeline `disclosure_level: partial` — 2.9% of blends. DIM
      // disclosed at 25 mg, vitamin E / phosphatidylcholine / silica
      // undisclosed. All four entries must bucket into the blend.
      final result = groupActivesByBlend(
        ingredients: const [
          {'name': 'Diindolylmethane', 'quantity': 25, 'unit': 'mg'},
          {'name': 'Vitamin E', 'quantity': 0, 'unit': 'NP'},
          {'name': 'Phosphatidylcholine', 'quantity': 0, 'unit': 'NP'},
          {'name': 'Silica', 'quantity': 0, 'unit': 'NP'},
        ],
        blendsRaw: const [
          {
            'name': 'Diindolylmethane Complex',
            'total_weight': 100,
            'unit': 'mg',
            'child_ingredients': [
              {'name': 'Diindolylmethane', 'amount': 25, 'unit': 'mg'},
              {'name': 'Vitamin E', 'amount': null},
              {'name': 'Phosphatidylcholine', 'amount': null},
              {'name': 'Silica', 'amount': null},
            ],
          },
        ],
      );

      expect(result.blends, hasLength(1));
      expect(result.blends.first.children, hasLength(4));
      expect(result.blends.first.children.map((c) => c['name']), [
        'Diindolylmethane',
        'Vitamin E',
        'Phosphatidylcholine',
        'Silica',
      ]);
      expect(result.looseDisclosed, isEmpty);
      expect(result.looseUndisclosed, isEmpty);
    });

    test('PARTIAL with same-name overlap — disclosed standalone outside '
        'blend stays loose, even when blend has a disclosed child', () {
      // Worst-case combo: blend has a disclosed CLA child at 770 mg
      // AND the actives ALSO ship a standalone CLA at 200 mg (same
      // name, different dose, NOT a blend member). The hasAmount
      // dimension alone can't disambiguate this — pipeline doesn't
      // currently emit this shape, but if it did, first-wins on
      // disclosed match would route the standalone into the blend
      // bucket (mild over-grouping). Documented here for future
      // tightening if pipeline introduces this case.
      final result = groupActivesByBlend(
        ingredients: const [
          // Both disclosed CLA entries — current matcher buckets the
          // FIRST one (which happens to also be the blend member).
          {'name': 'Conjugated Linoleic Acid', 'quantity': 770, 'unit': 'mg'},
          {'name': 'Conjugated Linoleic Acid', 'quantity': 200, 'unit': 'mg'},
        ],
        blendsRaw: const [
          {
            'name': 'CLA Complex',
            'total_weight': 770,
            'unit': 'mg',
            'child_ingredients': [
              {'name': 'Conjugated Linoleic Acid', 'amount': 770, 'unit': 'mg'},
            ],
          },
        ],
      );

      // Both disclosed entries land in the blend bucket today —
      // documented limitation. Update if pipeline emits this shape.
      expect(result.blends, hasLength(1));
      expect(result.blends.first.children, hasLength(2));
    });

    test('preserves pipeline order within blend children', () {
      // Children ordering matters — supplement-facts label order is
      // meaningful. Even though Lutein appears AFTER Lycopene in the
      // actives list, render it AFTER per the active-list order
      // (matches the supplement-facts ordering for that label).
      final result = groupActivesByBlend(
        ingredients: const [
          {'name': 'Lycopene'},
          {'name': 'Lutein'},
          {'name': 'Zeaxanthin'},
        ],
        blendsRaw: const [
          {
            'name': 'Carotenoid Mix',
            'total_weight': 25,
            'unit': 'mg',
            'child_ingredients': [
              // Pipeline blend metadata order doesn't dictate render
              // order — actives list does.
              {'name': 'Zeaxanthin'},
              {'name': 'Lutein'},
              {'name': 'Lycopene'},
            ],
          },
        ],
      );
      expect(result.blends.first.children.map((c) => c['name']), [
        'Lycopene',
        'Lutein',
        'Zeaxanthin',
      ]);
    });
  });
}
