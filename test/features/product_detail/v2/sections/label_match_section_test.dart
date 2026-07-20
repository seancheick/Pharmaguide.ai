import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/label_match_section.dart';

const _fingerprint =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

Map<String, dynamic> _record({
  String? sourceName = 'NIH DSLD',
  String? sourceRecordId = '999',
  String? catalogVersion = '7',
  String? formulaFingerprint = _fingerprint,
  String? sourceDate = '2024-01-02',
  String? sourceUpdatedDate = '2025-03-04T10:11:12Z',
  String? productStatus = 'reformulated',
  String? labelSourceUrl = 'https://example.test/labels/999.png',
  String? lineageKey = 'dsld:999',
  List<Map<String, dynamic>> formulaHistory = const [],
}) {
  final fields = <String, String?>{
    'source_name': sourceName,
    'source_record_id': sourceRecordId,
    'catalog_version': catalogVersion,
    'formula_fingerprint': formulaFingerprint,
    'source_date': sourceDate,
    'source_updated_date': sourceUpdatedDate,
    'product_status': productStatus,
    'label_source_url': labelSourceUrl,
    'lineage_key': lineageKey,
  };
  final statuses = {
    for (final entry in fields.entries)
      entry.key: entry.value == null ? 'unavailable' : 'available',
  };
  final unavailable = statuses.entries
      .where((entry) => entry.value == 'unavailable')
      .map((entry) => 'unavailable:${entry.key}')
      .toList(growable: false);

  return {
    ...fields,
    'metadata_status': unavailable.isEmpty ? 'available' : 'partial',
    'metadata_issues': unavailable,
    'field_statuses': statuses,
    'formula_history': formulaHistory,
    'history_status': formulaHistory.isEmpty ? 'unavailable' : 'available',
  };
}

Widget _harness({
  required Object? labelRecord,
  String? upc,
  Future<void> Function(Uri uri)? onOpenSourceLabel,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: buildLabelMatchSection(
          labelRecord: labelRecord,
          upc: upc,
          onOpenSourceLabel: onOpenSourceLabel,
        ),
      ),
    ),
  );
}

void main() {
  group('Label match catalog record details', () {
    testWidgets('shows source identity and version metadata without a claim', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(labelRecord: _record(), upc: '012345678901'),
      );

      expect(find.text('Catalog record details'), findsOneWidget);
      expect(
        find.text(
          'Compare these catalog details with the package in your hand.',
        ),
        findsOneWidget,
      );
      expect(find.text('Source'), findsOneWidget);
      expect(find.text('NIH DSLD'), findsOneWidget);
      expect(find.text('Source record ID'), findsOneWidget);
      expect(find.text('999'), findsOneWidget);
      expect(find.text('UPC'), findsOneWidget);
      expect(find.text('012345678901'), findsOneWidget);
      expect(find.text('Product status'), findsOneWidget);
      expect(find.text('Reformulated'), findsOneWidget);
      expect(find.text('Catalog version'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('Formula fingerprint'), findsOneWidget);
      expect(find.text(_fingerprint), findsOneWidget);
      expect(find.text('Source date'), findsOneWidget);
      expect(find.text('2024-01-02'), findsOneWidget);
      expect(find.text('Source updated'), findsOneWidget);
      expect(find.text('2025-03-04T10:11:12Z'), findsOneWidget);

      expect(
        find.textContaining('exact match', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('verified', findRichText: true), findsNothing);
      expect(find.textContaining('current', findRichText: true), findsNothing);
    });

    testWidgets('names unavailable fields and metadata issues explicitly', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          labelRecord: _record(
            sourceName: null,
            catalogVersion: null,
            sourceUpdatedDate: null,
            productStatus: null,
            labelSourceUrl: null,
          ),
          upc: null,
        ),
      );

      expect(find.text('Partial source metadata'), findsOneWidget);
      expect(find.text('Unavailable'), findsNWidgets(5));
      expect(
        find.text(
          'Unavailable in catalog: Source, UPC, Catalog version, '
          'Source updated, Product status, Source label.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('View source label'), findsNothing);
    });

    testWidgets(
      'keeps valid source metadata when the fingerprint is unavailable',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            labelRecord: _record(formulaFingerprint: null),
            upc: '012345678901',
          ),
        );

        expect(find.text('Catalog record details unavailable'), findsNothing);
        expect(find.text('NIH DSLD'), findsOneWidget);
        expect(find.text('999'), findsOneWidget);
        expect(find.text('Formula fingerprint'), findsOneWidget);
        expect(find.text('Unavailable'), findsOneWidget);
        expect(
          find.text('Unavailable in catalog: Formula fingerprint.'),
          findsOneWidget,
        );
      },
    );

    for (final testCase in <({String url, String actionLabel})>[
      (
        url: 'https://example.test/labels/999.JPEG?download=1',
        actionLabel: 'View source label image',
      ),
      (
        url: 'https://example.test/labels/999.pdf#page=1',
        actionLabel: 'View source label PDF',
      ),
      (
        url: 'https://api.ods.od.nih.gov/dsld/v9/label/999?view=full',
        actionLabel: 'View source label',
      ),
    ]) {
      testWidgets('${testCase.actionLabel} opens only its real source URL', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        Uri? opened;
        await tester.pumpWidget(
          _harness(
            labelRecord: _record(labelSourceUrl: testCase.url),
            upc: '012345678901',
            onOpenSourceLabel: (uri) async => opened = uri,
          ),
        );

        final action = find.bySemanticsLabel(
          '${testCase.actionLabel}, opens external source',
        );
        expect(action, findsOneWidget);
        tester.semantics.tap(
          find.semantics.byLabel(
            '${testCase.actionLabel}, opens external source',
          ),
        );
        await tester.pump();

        expect(opened, Uri.parse(testCase.url));
        semantics.dispose();
      });
    }

    testWidgets('malformed record fails closed without exposing an action', (
      tester,
    ) async {
      final malformed = _record(labelSourceUrl: 'javascript:alert(1)');

      await tester.pumpWidget(
        _harness(
          labelRecord: malformed,
          upc: '012345678901',
          onOpenSourceLabel: (_) async {
            fail('Malformed source records must not open a URL.');
          },
        ),
      );

      expect(find.text('Catalog record details unavailable'), findsOneWidget);
      expect(
        find.text(
          'This catalog record could not be read. Compare the ingredient '
          'list with the package before use.',
        ),
        findsOneWidget,
      );
      expect(find.text('NIH DSLD'), findsNothing);
      expect(find.textContaining('View source label'), findsNothing);
      expect(
        find.textContaining('exact match', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('verified', findRichText: true), findsNothing);
    });

    testWidgets('malformed non-null fingerprint fails closed', (tester) async {
      await tester.pumpWidget(
        _harness(
          labelRecord: _record(formulaFingerprint: 'not-a-sha256'),
          upc: '012345678901',
        ),
      );

      expect(find.text('Catalog record details unavailable'), findsOneWidget);
      expect(find.text('NIH DSLD'), findsNothing);
      expect(find.textContaining('View source label'), findsNothing);
    });

    testWidgets('opens only defensible source-linked formula history', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _harness(
          labelRecord: _record(
            formulaHistory: [
              {
                'snapshot_id': 'older-source-snapshot',
                'source_record_id': '999',
                'lineage_key': 'dsld:999',
                'formula_fingerprint':
                    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                'source_date': '2024-01-01',
              },
            ],
          ),
          upc: '012345678901',
        ),
      );

      final action = find.bySemanticsLabel('View formula history');
      expect(action, findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel('View formula history'));
      await tester.pumpAndSettle();

      expect(find.text('Formula history'), findsOneWidget);
      expect(find.text('Snapshot older-source-snapshot'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('states when source-linked formula history is unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(labelRecord: _record(), upc: '012345678901'),
      );

      expect(
        find.text('No source-linked formula history is available.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('View formula history'), findsNothing);
    });
  });
}
