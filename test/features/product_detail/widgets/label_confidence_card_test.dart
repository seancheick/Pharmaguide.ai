// Sprint: docs/sprints/product_detail_page_sprint.md — T3.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/label_confidence_section.dart';

Future<void> _pump(
  WidgetTester tester, {
  double mappedCoverage = 1.0,
  bool hasProprietaryBlends = false,
  bool isNotScored = false,
  Map<String, dynamic>? productStatus,
  Map<String, dynamic>? unmappedActives,
  Map<String, dynamic>? labelLedgerAudit,
  bool labelLedgerAuditPresent = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Builder(
            builder: (context) => buildLabelConfidenceSection(
              context: context,
              mappedCoverage: mappedCoverage,
              hasProprietaryBlends: hasProprietaryBlends,
              isNotScored: isNotScored,
              productStatus: productStatus,
              unmappedActives: unmappedActives,
              labelLedgerAudit: labelLedgerAudit,
              labelLedgerAuditPresent: labelLedgerAuditPresent,
            ),
          ),
        ),
      ),
    ),
  );
}

Map<String, dynamic> _audit({
  String supportStatus = 'supported',
  String sourceStructure = 'flat_supplement_facts',
  int meaningfulRows = 4,
  int displayedRows = 4,
  int omittedRows = 0,
  Object? percentage = 100.0,
  String completenessStatus = 'complete',
}) => <String, dynamic>{
  'support_status': supportStatus,
  'source_structure': sourceStructure,
  'meaningful_source_rows': meaningfulRows,
  'displayed_rows': displayedRows,
  'omitted_rows': omittedRows,
  'completeness_percentage': percentage,
  'completeness_status': completenessStatus,
};

void main() {
  group('labelConfidenceHasAnySignal', () {
    test('high confidence (no signals) → false', () {
      expect(
        labelConfidenceHasAnySignal(
          mappedCoverage: 1.0,
          hasProprietaryBlends: false,
          isNotScored: false,
        ),
        isFalse,
      );
    });

    test('low coverage → true', () {
      expect(
        labelConfidenceHasAnySignal(
          mappedCoverage: 0.4,
          hasProprietaryBlends: false,
          isNotScored: false,
        ),
        isTrue,
      );
    });

    test('blend → true', () {
      expect(
        labelConfidenceHasAnySignal(
          mappedCoverage: 1.0,
          hasProprietaryBlends: true,
          isNotScored: false,
        ),
        isTrue,
      );
    });

    test('not scored → true', () {
      expect(
        labelConfidenceHasAnySignal(
          mappedCoverage: 1.0,
          hasProprietaryBlends: false,
          isNotScored: true,
        ),
        isTrue,
      );
    });

    test('product status → true', () {
      expect(
        labelConfidenceHasAnySignal(
          mappedCoverage: 1.0,
          hasProprietaryBlends: false,
          isNotScored: false,
          productStatus: const {'display': 'Reformulated'},
        ),
        isTrue,
      );
    });

    test('unmapped actives total > 0 → true', () {
      expect(
        labelConfidenceHasAnySignal(
          mappedCoverage: 1.0,
          hasProprietaryBlends: false,
          isNotScored: false,
          unmappedActives: const {'total': 2},
        ),
        isTrue,
      );
    });

    test('ledger audit is an independent signal', () {
      expect(
        labelConfidenceHasAnySignal(
          mappedCoverage: 1.0,
          hasProprietaryBlends: false,
          isNotScored: false,
          labelLedgerAudit: _audit(),
        ),
        isTrue,
      );
    });

    test('present but unparsable ledger audit fails closed as a signal', () {
      expect(
        labelConfidenceHasAnySignal(
          mappedCoverage: 1.0,
          hasProprietaryBlends: false,
          isNotScored: false,
          labelLedgerAuditPresent: true,
        ),
        isTrue,
      );
    });

    test('absent ledger audit remains no signal', () {
      expect(
        labelConfidenceHasAnySignal(
          mappedCoverage: 1.0,
          hasProprietaryBlends: false,
          isNotScored: false,
          labelLedgerAuditPresent: false,
        ),
        isFalse,
      );
    });
  });

  group('LabelConfidence v2 rendering', () {
    testWidgets('high confidence → renders nothing', (tester) async {
      await _pump(tester);
      expect(find.textContaining('Label confidence'), findsNothing);
    });

    testWidgets('low coverage → Limited tier with coverage row', (
      tester,
    ) async {
      await _pump(tester, mappedCoverage: 0.2);
      expect(find.text('Analysis coverage: Limited'), findsOneWidget);
      expect(find.text('Limited analysis coverage'), findsOneWidget);
      expect(find.textContaining('Label confidence'), findsNothing);
    });

    testWidgets('partial coverage → Partial tier', (tester) async {
      await _pump(tester, mappedCoverage: 0.4);
      expect(find.text('Analysis coverage: Partial'), findsOneWidget);
      expect(find.text('Analysis coverage is incomplete'), findsOneWidget);
    });

    testWidgets('proprietary blend → blend row visible', (tester) async {
      await _pump(tester, hasProprietaryBlends: true);
      expect(find.text('Analysis coverage: Partial'), findsOneWidget);
      expect(find.text('Blend amounts not disclosed'), findsOneWidget);
    });

    testWidgets('product status → status row visible', (tester) async {
      await _pump(
        tester,
        productStatus: const {
          'type': 'reformulated',
          'date': '2026-01-15',
          'display': 'Reformulated · 2026-01-15',
        },
      );
      // Status-only renders as a compact product-status row in v2.
      // Calling it "Label confidence: Partial" would mislead.
      expect(find.text('Product note'), findsNothing);
      expect(find.textContaining('Reformulated'), findsWidgets);
    });

    testWidgets('unmapped actives → row with count + names', (tester) async {
      await _pump(
        tester,
        unmappedActives: const {
          'total': 2,
          'names': ['Exotic A', 'Typo B'],
        },
      );
      expect(find.text('Analysis coverage: Partial'), findsOneWidget);
      expect(find.text('2 ingredients could not be mapped'), findsOneWidget);
      expect(find.textContaining('Exotic A'), findsOneWidget);
    });

    testWidgets('not scored → Limited tier with not-scored row', (
      tester,
    ) async {
      await _pump(tester, isNotScored: true);
      expect(find.text('Analysis coverage: Limited'), findsOneWidget);
      expect(find.text('Not enough verified data to score'), findsOneWidget);
    });

    testWidgets('all signals together → Limited tier with multiple rows', (
      tester,
    ) async {
      await _pump(
        tester,
        mappedCoverage: 0.2,
        hasProprietaryBlends: true,
        isNotScored: true,
        productStatus: const {'display': 'Reformulated'},
        unmappedActives: const {
          'total': 1,
          'names': ['A'],
        },
      );
      expect(find.text('Analysis coverage: Limited'), findsOneWidget);
      expect(find.text('Not enough verified data to score'), findsOneWidget);
      expect(find.text('Limited analysis coverage'), findsOneWidget);
      expect(find.text('Blend amounts not disclosed'), findsOneWidget);
      expect(find.text('1 ingredient could not be mapped'), findsOneWidget);
      expect(find.text('Reformulated'), findsOneWidget);
    });

    testWidgets('label completeness and analysis coverage stay independent', (
      tester,
    ) async {
      await _pump(tester, mappedCoverage: 0.2, labelLedgerAudit: _audit());

      expect(find.text('Label & analysis data'), findsOneWidget);
      expect(find.text('Label completeness: 100%'), findsOneWidget);
      expect(find.text('Limited analysis coverage'), findsOneWidget);
      expect(
        find.textContaining('does not mean every row is clinically analyzed'),
        findsOneWidget,
      );
    });

    testWidgets('supported incomplete audit displays its exact percentage', (
      tester,
    ) async {
      await _pump(
        tester,
        labelLedgerAudit: _audit(
          meaningfulRows: 4,
          displayedRows: 3,
          percentage: 75.0,
          completenessStatus: 'incomplete',
        ),
      );

      expect(find.text('Label data'), findsOneWidget);
      expect(find.text('Label completeness: 75%'), findsOneWidget);
      expect(
        find.textContaining('source-label rows are represented'),
        findsOneWidget,
      );
      expect(find.textContaining('Analysis coverage'), findsNothing);
    });

    testWidgets('unsupported structure makes completeness unavailable', (
      tester,
    ) async {
      await _pump(
        tester,
        labelLedgerAudit: _audit(
          supportStatus: 'unsupported',
          sourceStructure: 'unsupported_source_structure',
          meaningfulRows: 0,
          displayedRows: 0,
          omittedRows: 1,
          percentage: null,
          completenessStatus: 'unavailable',
        ),
      );

      expect(find.text('Label completeness unavailable'), findsOneWidget);
      expect(find.textContaining('Label data unavailable'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.text('Label completeness: 100%'), findsNothing);
    });

    testWidgets('malformed supported audit fails closed as unavailable', (
      tester,
    ) async {
      await _pump(
        tester,
        labelLedgerAudit: <String, dynamic>{
          ..._audit(),
          'displayed_rows': 2,
          'completeness_percentage': 100.0,
        },
      );

      expect(find.text('Label completeness unavailable'), findsOneWidget);
      expect(find.textContaining('Label data unavailable'), findsOneWidget);
      expect(find.textContaining('100%'), findsNothing);
    });

    testWidgets('present but normalized-null audit is visibly unavailable', (
      tester,
    ) async {
      await _pump(tester, labelLedgerAuditPresent: true);

      expect(find.text('Label data'), findsOneWidget);
      expect(find.text('Label completeness unavailable'), findsOneWidget);
      expect(find.textContaining('Label data unavailable'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('absent audit does not invent a completeness result', (
      tester,
    ) async {
      await _pump(tester, labelLedgerAuditPresent: false);

      expect(find.textContaining('Label completeness'), findsNothing);
      expect(find.textContaining('Label data unavailable'), findsNothing);
    });

    testWidgets('coverage concepts expose explicit accessibility labels', (
      tester,
    ) async {
      await _pump(tester, mappedCoverage: 0.2, labelLedgerAudit: _audit());

      expect(
        find.bySemanticsLabel(
          RegExp('Label completeness, 100 percent.*clinically analyzed'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp('Analysis coverage, limited.*reference data'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('low analysis coverage never uses safe-sounding copy', (
      tester,
    ) async {
      await _pump(tester, mappedCoverage: 0.2);

      final visibleCopy = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? '')
          .join(' ')
          .toLowerCase();
      expect(visibleCopy, isNot(contains('safe')));
      expect(visibleCopy, isNot(contains('good fit')));
      expect(visibleCopy, isNot(contains('fully analyzed')));
    });
  });
}
