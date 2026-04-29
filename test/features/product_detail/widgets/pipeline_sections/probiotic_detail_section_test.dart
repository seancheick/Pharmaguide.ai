// Regression: the pipeline emits `clinical_strains` as a list of strain
// records, not an int count. The widget used to do `as int?` and crashed
// with `type 'List<dynamic>' is not a subtype of type 'int?' in type cast`
// when the new catalog landed on existing devices. The widget now accepts
// both shapes defensively so a pipeline schema tweak can never crash the
// product-detail screen again.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/pipeline_sections/probiotic_detail_section.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ProbioticDetailSection clinical_strains parsing', () {
    testWidgets('renders without throwing when clinical_strains is a List', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ProbioticDetailSection(
            probioticDetail: {
              'strains': [
                {'name': 'L. acidophilus', 'cfu': '5B', 'is_clinical': true},
              ],
              'total_cfu': '10B',
              'clinical_strains': [
                {'strain_name': 'L. acidophilus NCFM', 'cfu': 5e9},
                {'strain_name': 'B. lactis Bi-07', 'cfu': 5e9},
              ],
            },
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // List has 2 entries → chip should show "Clinically studied: 2".
      // The label is rendered as "Clinically studied: " (trailing space)
      // and the value as "2" in a sibling Text widget — match both.
      expect(find.text('Clinically studied: '), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('still accepts the legacy int shape', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ProbioticDetailSection(
            probioticDetail: {
              'strains': [
                {'name': 'L. acidophilus', 'cfu': '5B'},
              ],
              'total_cfu': '10B',
              'clinical_strains': 3,
            },
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('omits the clinically-studied chip when the field is absent', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ProbioticDetailSection(
            probioticDetail: {
              'strains': [
                {'name': 'L. acidophilus', 'cfu': '5B'},
              ],
              'total_cfu': '10B',
            },
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Clinically studied: '), findsNothing);
    });
  });
}
