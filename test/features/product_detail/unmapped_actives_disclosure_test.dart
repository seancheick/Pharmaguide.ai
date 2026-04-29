// Tests for UnmappedActivesDisclosure — the v1.3.2 transparency widget
// that surfaces ingredients the pipeline could not map to its quality
// reference data.
//
// Reads detail_blob.unmapped_actives, which the pipeline always emits
// (empty shape when nothing was unmapped, populated shape otherwise):
//
//   {
//     "names": ["Exotic Extract", "Typo Ingredient"],
//     "total": 2,
//     "excluding_banned_exact_alias": 2
//   }
//
// TDD: contract first, implementation after.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/unmapped_actives_disclosure.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  group('UnmappedActivesDisclosure', () {
    testWidgets('renders nothing when blob is null', (tester) async {
      await _pump(
        tester,
        const UnmappedActivesDisclosure(unmappedActives: null),
      );
      expect(find.byKey(const Key('unmapped-actives-card')), findsNothing);
    });

    testWidgets('renders nothing when total is 0', (tester) async {
      await _pump(
        tester,
        const UnmappedActivesDisclosure(
          unmappedActives: <String, dynamic>{
            'names': <String>[],
            'total': 0,
            'excluding_banned_exact_alias': 0,
          },
        ),
      );
      expect(find.byKey(const Key('unmapped-actives-card')), findsNothing);
    });

    testWidgets('renders nothing when total is missing/null', (tester) async {
      await _pump(
        tester,
        const UnmappedActivesDisclosure(
          unmappedActives: <String, dynamic>{'names': <String>[]},
        ),
      );
      expect(find.byKey(const Key('unmapped-actives-card')), findsNothing);
    });

    testWidgets('renders card and headline when total > 0', (tester) async {
      await _pump(
        tester,
        const UnmappedActivesDisclosure(
          unmappedActives: <String, dynamic>{
            'names': <String>['Exotic Extract', 'Typo Ingredient'],
            'total': 2,
            'excluding_banned_exact_alias': 2,
          },
        ),
      );
      expect(find.byKey(const Key('unmapped-actives-card')), findsOneWidget);
      expect(find.textContaining('2 ingredients'), findsOneWidget);
    });

    testWidgets('uses singular noun for total = 1', (tester) async {
      await _pump(
        tester,
        const UnmappedActivesDisclosure(
          unmappedActives: <String, dynamic>{
            'names': <String>['Single Mystery Extract'],
            'total': 1,
            'excluding_banned_exact_alias': 1,
          },
        ),
      );
      expect(find.textContaining('1 ingredient'), findsOneWidget);
      expect(find.text('Single Mystery Extract'), findsOneWidget);
    });

    testWidgets('renders the names list when present', (tester) async {
      await _pump(
        tester,
        const UnmappedActivesDisclosure(
          unmappedActives: <String, dynamic>{
            'names': <String>['Exotic Extract', 'Typo Ingredient'],
            'total': 2,
            'excluding_banned_exact_alias': 2,
          },
        ),
      );
      expect(find.text('Exotic Extract'), findsOneWidget);
      expect(find.text('Typo Ingredient'), findsOneWidget);
    });

    testWidgets('renders count without names when names list is empty', (
      tester,
    ) async {
      // Defensive: pipeline should never emit total > 0 with empty
      // names, but if it does, the card still renders the headline
      // and skips the names section gracefully.
      await _pump(
        tester,
        const UnmappedActivesDisclosure(
          unmappedActives: <String, dynamic>{
            'names': <String>[],
            'total': 3,
            'excluding_banned_exact_alias': 3,
          },
        ),
      );
      expect(find.byKey(const Key('unmapped-actives-card')), findsOneWidget);
      expect(find.textContaining('3 ingredients'), findsOneWidget);
    });

    testWidgets('handles raw List from JSON decode (List<dynamic>)', (
      tester,
    ) async {
      // jsonDecode produces List<dynamic>, not List<String>. The widget
      // must accept that without crashing.
      await _pump(
        tester,
        const UnmappedActivesDisclosure(
          unmappedActives: <String, dynamic>{
            'names': <dynamic>['Foo Extract', 'Bar Powder'],
            'total': 2,
            'excluding_banned_exact_alias': 2,
          },
        ),
      );
      expect(find.text('Foo Extract'), findsOneWidget);
      expect(find.text('Bar Powder'), findsOneWidget);
    });

    testWidgets('handles total provided as string from loose JSON', (
      tester,
    ) async {
      // Defensive against type drift in the blob format.
      await _pump(
        tester,
        const UnmappedActivesDisclosure(
          unmappedActives: <String, dynamic>{
            'names': <String>['Mystery Compound'],
            'total': '1',
            'excluding_banned_exact_alias': '1',
          },
        ),
      );
      expect(find.byKey(const Key('unmapped-actives-card')), findsOneWidget);
      expect(find.text('Mystery Compound'), findsOneWidget);
    });
  });
}
