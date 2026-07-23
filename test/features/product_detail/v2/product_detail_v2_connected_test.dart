import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_ingredient_tile.dart';
import 'package:pharmaguide/core/components/pg_score_breakdown_card.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/fit_score_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/personalized_warnings_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_connected.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/ingredients_section.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';

const _connectedDsldId = 'label-ledger-connected';
const _connectedFingerprint =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

Map<String, dynamic> _connectedLabelRecord() {
  const fields = <String, String>{
    'source_name': 'NIH DSLD',
    'source_record_id': '999',
    'catalog_version': '7',
    'formula_fingerprint': _connectedFingerprint,
    'source_date': '2026-01-01',
    'source_updated_date': '2026-01-02T00:00:00Z',
    'product_status': 'active',
    'label_source_url': 'https://example.test/labels/999',
    'lineage_key': 'dsld:999',
  };
  return {
    ...fields,
    'field_statuses': {for (final field in fields.keys) field: 'available'},
    'metadata_status': 'available',
    'metadata_issues': const <String>[],
    'history_status': 'available',
    'formula_history': [
      {
        'snapshot_id': 'older-label',
        'source_record_id': '999',
        'lineage_key': 'dsld:999',
        'formula_fingerprint':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'source_date': '2025-01-01',
        'display_ingredients': const [
          {
            'label_order': 0,
            'nested_depth': 0,
            'label_display_name': 'EPA',
            'exact_dose_text': '300 mg',
          },
        ],
      },
    ],
  };
}

Future<void> _seedConnectedProduct(CoreDatabase coreDb) async {
  await _seedProduct(
    coreDb,
    dsldId: _connectedDsldId,
    productName: 'Connected Label Trust Product',
  );
}

Future<void> _seedProduct(
  CoreDatabase coreDb, {
  required String dsldId,
  required String productName,
}) async {
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: productName,
          exportVersion: 'test',
          exportedAt: '2026-07-19T00:00:00Z',
          qualityScoreV4100: const Value(88),
          score100Equivalent: const Value(88),
          qualityScoreStatus: const Value('scored'),
          mappedCoverage: const Value(1),
          verdict: const Value('SAFE'),
        ),
      );
}

Map<String, dynamic> _connectedV4Pillars() => {
  'formulation': {
    'score': 12.0,
    'max': 20,
    'reason': 'Pipeline formulation reason.',
  },
  'dose': {'score': 20.0, 'max': 20, 'reason': 'Pipeline dose reason.'},
  'evidence': {'score': 17.0, 'max': 20, 'reason': 'Pipeline evidence reason.'},
  'transparency': {
    'score': 14.0,
    'max': 15,
    'reason': 'Pipeline transparency reason.',
  },
  'verification': {
    'score': 15.0,
    'max': 15,
    'reason': 'Pipeline verification reason.',
  },
  'safety_hygiene': {
    'score': 10.0,
    'max': 10,
    'reason': 'Pipeline safety reason.',
  },
};

Map<String, dynamic> _zeroTransparencyPillars() {
  final pillars = _connectedV4Pillars();
  pillars['transparency'] = {
    'score': 0.0,
    'max': 15,
    'reason': 'Pipeline transparency reason.',
  };
  return pillars;
}

Map<String, dynamic> _activeLedgerRow(String name, int order) => {
  'label_display_name': name,
  'label_order': order,
  'nested_depth': 0,
  'score_included': true,
  'display_disposition': 'scored',
  'form_display_state': 'not_disclosed',
};

Future<void> _pumpConnectedScreen(
  WidgetTester tester, {
  required Map<String, dynamic> detailBlob,
  String? initialSection = 'ingredients',
}) async {
  final coreDb = CoreDatabase.memory();
  final userDb = UserDatabase.memory();
  await _seedConnectedProduct(coreDb);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        userDatabaseProvider.overrideWithValue(userDb),
        detailBlobProvider.overrideWith((ref, dsldId) async {
          expect(dsldId, _connectedDsldId);
          return detailBlob;
        }),
        personalizedInteractionWarningsProvider.overrideWith(
          (ref, dsldId) async => const [],
        ),
        fitScoreForProductProvider.overrideWith((ref, dsldId) async => null),
        currentStackMedicationClassIdsProvider.overrideWith(
          (ref) async => const <String>{},
        ),
        rdaOptimalUlsProvider.overrideWith((ref) async => const {}),
      ],
      child: MaterialApp(
        home: ProductDetailV2ConnectedScreen(
          dsldId: _connectedDsldId,
          initialSection: initialSection,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollConnectedTowardTop(WidgetTester tester) async {
  final scrollView = find.byType(CustomScrollView);
  for (var attempt = 0; attempt < 8; attempt++) {
    await tester.drag(scrollView, const Offset(0, 400));
    await tester.pumpAndSettle();
  }
}

Future<void> _scrollConnectedTowardBottomUntil(
  WidgetTester tester,
  Finder target,
) async {
  final scrollView = find.byType(CustomScrollView);
  for (var attempt = 0; attempt < 12 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(scrollView, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
}

Widget _ingredientsHarness({
  required List<Map<String, dynamic>> ingredients,
  List<Map<String, dynamic>>? displayIngredients,
  List<Map<String, dynamic>> inactiveIngredients = const [],
  TextScaler? textScaler,
  bool scrollable = false,
}) {
  return MaterialApp(
    builder: textScaler == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
    home: Scaffold(
      body: Builder(
        builder: (context) {
          final section = buildIngredientsSection(
            context: context,
            ingredients: ingredients,
            displayIngredients: displayIngredients,
            inactiveIngredients: inactiveIngredients,
            ulAnalysis: null,
            blends: const [],
          );
          return scrollable ? SingleChildScrollView(child: section) : section;
        },
      ),
    ),
  );
}

List<Map<String, dynamic>> _analysisLedger() => [
  {
    'label_display_name': 'Fish Oil',
    'exact_dose_text': '2,400 mg',
    'label_order': 0,
    'nested_depth': 0,
    'score_included': true,
    'display_disposition': 'scored',
    'form_display_state': 'not_disclosed',
  },
  {
    'label_display_name': 'Total Omega-3 Fatty Acids',
    'exact_dose_text': '720 mg',
    'label_order': 1,
    'nested_depth': 1,
    'parent_label': 'Fish Oil',
    'score_included': false,
    'display_disposition': 'label_context',
    'form_display_state': 'not_applicable',
  },
  {
    'label_display_name': 'EPA',
    'exact_dose_text': '360 mg',
    'label_order': 2,
    'nested_depth': 2,
    'parent_label': 'Total Omega-3 Fatty Acids',
    'score_included': true,
    'display_disposition': 'scored',
    'form_display_state': 'not_disclosed',
  },
  {
    'label_display_name': 'DHA',
    'exact_dose_text': '240 mg',
    'label_order': 3,
    'nested_depth': 2,
    'parent_label': 'Total Omega-3 Fatty Acids',
    'score_included': true,
    'display_disposition': 'scored',
    'form_display_state': 'not_disclosed',
  },
  {
    'label_display_name': 'Other Omega-3 Fatty Acids',
    'exact_dose_text': '120 mg',
    'label_order': 4,
    'nested_depth': 2,
    'parent_label': 'Total Omega-3 Fatty Acids',
    'score_included': false,
    'display_disposition': 'label_context',
    'form_display_state': 'not_applicable',
  },
];

void main() {
  group('productDetailIngredientSourcesFromBlob', () {
    test('ledger key presence is authoritative and mixed rows fail closed', () {
      final absent = productDetailIngredientSourcesFromBlob(const {
        'ingredients': [
          {'display_label': 'Legacy score row'},
        ],
      });
      expect(absent.displayIngredients, isNull);
      expect(absent.ingredients.single['display_label'], 'Legacy score row');

      final presentEmpty = productDetailIngredientSourcesFromBlob(const {
        'display_ingredients': <Map<String, dynamic>>[],
        'ingredients': [
          {'display_label': 'Must not substitute for an empty ledger'},
        ],
      });
      expect(presentEmpty.displayIngredients, isEmpty);

      final mixed = productDetailIngredientSourcesFromBlob(const {
        'display_ingredients': [
          {'label_display_name': 'Valid-looking row'},
          'malformed row',
        ],
        'ingredients': [
          {'display_label': 'Must not replace a malformed ledger'},
        ],
      });
      expect(mixed.displayIngredients, isEmpty);
    });

    test('malformed legacy collections fail closed without throwing', () {
      late ProductDetailIngredientSources sources;

      expect(
        () => sources = productDetailIngredientSourcesFromBlob(const {
          'ingredients': [
            {'display_label': 'Valid-looking row'},
            7,
          ],
          'inactive_ingredients': 'not a list',
          'proprietary_blend_detail': {
            'blends': [
              {'name': 'Valid-looking blend'},
              false,
            ],
          },
        }),
        returnsNormally,
      );

      expect(sources.ingredients, isEmpty);
      expect(sources.inactiveIngredients, isEmpty);
      expect(sources.blends, isEmpty);
    });

    test('display rows never replace or mutate scoring inputs', () {
      final scoreRow = <String, dynamic>{
        'display_label': 'EPA',
        'quantity': 360,
        'unit': 'mg',
        'below_clinical_dose': true,
      };
      final displayRow = <String, dynamic>{
        'label_display_name': 'Total Omega-3 Fatty Acids',
        'exact_dose_text': '720 mg',
        'score_included': false,
        'display_disposition': 'label_context',
      };

      final sources = productDetailIngredientSourcesFromBlob({
        'ingredients': [scoreRow],
        'display_ingredients': [displayRow],
      });

      expect(sources.ingredients, hasLength(1));
      expect(sources.ingredients.single, {
        'display_label': 'EPA',
        'quantity': 360,
        'unit': 'mg',
        'below_clinical_dose': true,
      });
      expect(sources.displayIngredients, hasLength(1));
      expect(sources.displayIngredients!.single, {
        'label_display_name': 'Total Omega-3 Fatty Acids',
        'exact_dose_text': '720 mg',
        'score_included': false,
        'display_disposition': 'label_context',
      });
      expect(scoreRow.containsKey('score_included'), isFalse);
      expect(displayRow['score_included'], isFalse);
    });
  });

  group('connected transparency disclosure action', () {
    final trueBlendFlags = <({String name, Object value})>[
      (name: 'numeric one', value: 1),
      (name: 'boolean true', value: true),
      (name: 'string one', value: '1'),
      (name: 'string true', value: 'true'),
    ];
    for (final flag in trueBlendFlags) {
      testWidgets('keeps bare ${flag.name} blend audit flag internal', (
        tester,
      ) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: {
            'ingredients': const <Map<String, dynamic>>[],
            'display_ingredients': [_activeLedgerRow('Active row', 0)],
            'quality_pillars_v4': _connectedV4Pillars(),
            'proprietary_blend_detail': {'has_proprietary_blends': flag.value},
          },
        );

        final disclosure = find.text('Blend amounts not disclosed');
        await _scrollConnectedTowardBottomUntil(tester, disclosure);
        expect(disclosure, findsNothing);
      });
    }

    final falseBlendFlags = <({String name, Object value})>[
      (name: 'numeric zero', value: 0),
      (name: 'false-like string', value: 'false'),
    ];
    for (final flag in falseBlendFlags) {
      testWidgets('rejects ${flag.name} proprietary-blend flag', (
        tester,
      ) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: {
            'ingredients': const <Map<String, dynamic>>[],
            'display_ingredients': [_activeLedgerRow('Active row', 0)],
            'quality_pillars_v4': _connectedV4Pillars(),
            'proprietary_blend_detail': {'has_proprietary_blends': flag.value},
          },
        );

        final disclosure = find.text('Blend amounts not disclosed');
        await _scrollConnectedTowardBottomUntil(tester, disclosure);
        expect(disclosure, findsNothing);
      });
    }

    testWidgets(
      'transparency never repeats the visible label as a details action',
      (tester) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: {
            'ingredients': const <Map<String, dynamic>>[],
            'display_ingredients': [_activeLedgerRow('Active row', 0)],
            'quality_pillars_v4': _zeroTransparencyPillars(),
          },
        );

        final transparency = find.text('Transparency');
        await _scrollConnectedTowardBottomUntil(tester, transparency);

        expect(find.text('Blend amounts not disclosed'), findsNothing);
        expect(transparency, findsOneWidget);
        expect(find.text('View label details'), findsNothing);
      },
    );

    final noTargetCases = <({String name, List<Map<String, dynamic>> rows})>[
      (name: 'present-empty', rows: const []),
      (
        name: 'nutrition-only',
        rows: [
          {
            ..._activeLedgerRow('Calories', 0),
            'display_type': 'nutrition_fact',
          },
        ],
      ),
      (
        name: 'inactive-only',
        rows: [
          {
            ..._activeLedgerRow('Gelatin', 0),
            'display_type': 'inactive_ingredient',
            'display_disposition': 'other_ingredient',
          },
        ],
      ),
    ];
    for (final targetCase in noTargetCases) {
      testWidgets('${targetCase.name} canonical ledger has no action', (
        tester,
      ) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: {
            'ingredients': const <Map<String, dynamic>>[],
            'display_ingredients': targetCase.rows,
            'quality_pillars_v4': _zeroTransparencyPillars(),
          },
        );

        final transparency = find.text('Transparency');
        await _scrollConnectedTowardBottomUntil(tester, transparency);
        expect(transparency, findsOneWidget);
        expect(find.text('View label details'), findsNothing);
      });
    }
  });

  group('connected certification action', () {
    testWidgets('is hidden when no certification section can render', (
      tester,
    ) async {
      await _pumpConnectedScreen(
        tester,
        initialSection: null,
        detailBlob: {'quality_pillars_v4': _connectedV4Pillars()},
      );

      final testingBrand = find.text('Testing & Brand');
      await _scrollConnectedTowardBottomUntil(tester, testingBrand);
      expect(testingBrand, findsOneWidget);
      final scoreCard = tester.widget<PGScoreBreakdownCard>(
        find.byType(PGScoreBreakdownCard),
      );
      final verification = scoreCard.pillars.singleWhere(
        (pillar) => pillar.label == 'Testing & Brand',
      );
      expect(verification.actionLabel, isNull);
      expect(verification.onAction, isNull);
    });

    testWidgets('is shown when a verified certification can render', (
      tester,
    ) async {
      await _pumpConnectedScreen(
        tester,
        initialSection: null,
        detailBlob: {
          'quality_pillars_v4': _connectedV4Pillars(),
          'certification_detail': {
            'third_party_programs': {
              'programs': [
                {'name': 'USP Verified', 'verified': true},
              ],
            },
          },
        },
      );

      final testingBrand = find.text('Testing & Brand');
      await _scrollConnectedTowardBottomUntil(tester, testingBrand);
      final scoreCard = tester.widget<PGScoreBreakdownCard>(
        find.byType(PGScoreBreakdownCard),
      );
      final verification = scoreCard.pillars.singleWhere(
        (pillar) => pillar.label == 'Testing & Brand',
      );
      expect(verification.actionLabel, 'View certifications');
      expect(verification.onAction, isNotNull);
    });
  });

  group('label ingredient ledger', () {
    testWidgets(
      'product data disclosure is a section card with a compact tail gap',
      (tester) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: {
            'quality_pillars_v4': _connectedV4Pillars(),
            'label_record': _connectedLabelRecord(),
            'synergy_detail': {
              'clusters': [
                {
                  'name': 'Heart Health',
                  'evidence_tier': 1,
                  'match_count': 2,
                  'all_adequate': 1,
                },
              ],
            },
          },
        );

        final disclosureCard = find.byKey(
          const Key('product-data-sources-card'),
        );
        await _scrollConnectedTowardBottomUntil(tester, disclosureCard);
        expect(disclosureCard, findsOneWidget);

        final synergyCard = find.byKey(const Key('synergy-section-card'));
        expect(synergyCard, findsOneWidget);
        final decoration =
            tester.widget<Container>(disclosureCard).decoration
                as BoxDecoration;
        expect(decoration.color, V2Colors.surface);
        expect(decoration.border, isNotNull);
        expect(
          decoration.borderRadius,
          BorderRadius.circular(V2Spacing.radiusCard),
        );

        final gap =
            tester.getTopLeft(disclosureCard).dy -
            tester.getBottomLeft(synergyCard).dy;
        expect(gap, inInclusiveRange(8, V2Spacing.space24));
      },
    );

    testWidgets(
      'connected catalog action compares history with the canonical ledger',
      (tester) async {
        await _pumpConnectedScreen(
          tester,
          detailBlob: {
            'ingredients': const <Map<String, dynamic>>[],
            'display_ingredients': const [
              {
                'label_order': 0,
                'nested_depth': 0,
                'label_display_name': 'EPA',
                'exact_dose_text': '360 mg',
                'score_included': true,
                'display_disposition': 'scored',
                'form_display_state': 'not_disclosed',
              },
            ],
            'quality_pillars_v4': _connectedV4Pillars(),
            'label_record': _connectedLabelRecord(),
          },
        );

        final scrollView = find.byType(CustomScrollView);
        // Catalog details now live in the collapsed "Product data & sources"
        // section at the page bottom — scroll down to it and expand it.
        final disclosure = find.text('Product data & sources');
        for (
          var attempt = 0;
          attempt < 12 && disclosure.evaluate().isEmpty;
          attempt++
        ) {
          await tester.drag(scrollView, const Offset(0, -250));
          await tester.pumpAndSettle();
        }
        expect(disclosure, findsOneWidget);
        await tester.ensureVisible(disclosure);
        await tester.pumpAndSettle();
        await tester.tap(disclosure);
        await tester.pumpAndSettle();

        final action = find.byKey(const Key('formula-history-action'));
        expect(action, findsOneWidget);
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();

        expect(find.text('Snapshot older-label'), findsOneWidget);
        final changedRow = find.text('• Row 1: EPA · 300 mg → EPA · 360 mg');
        for (
          var attempt = 0;
          attempt < 4 && changedRow.evaluate().isEmpty;
          attempt++
        ) {
          await tester.drag(find.byType(ListView).last, const Offset(0, -220));
          await tester.pumpAndSettle();
        }
        expect(changedRow, findsOneWidget);
      },
    );

    testWidgets(
      'connected screen renders ledger identity while preserving pipeline score',
      (tester) async {
        final detailBlob = <String, dynamic>{
          'ingredients': [
            {
              'display_label': 'Scoring-only EPA identity',
              'standard_name': 'EPA',
              'quantity': 360,
              'unit': 'mg',
              'below_clinical_dose': true,
            },
          ],
          'display_ingredients': [
            {
              'label_display_name': 'Label Total Omega-3 Fatty Acids',
              'exact_dose_text': '720 mg',
              'label_order': 0,
              'nested_depth': 0,
              'raw_source_path': 'ingredientRows[0]',
              'score_included': false,
              'display_disposition': 'label_context',
              'form_display_state': 'not_applicable',
            },
          ],
          'quality_pillars_v4': _connectedV4Pillars(),
          'label_ledger_audit': {
            'support_status': 'supported',
            'source_structure': 'omega',
            'meaningful_source_rows': 1,
            'displayed_rows': 1,
            'omitted_rows': 0,
            'completeness_percentage': 100.0,
            'completeness_status': 'complete',
          },
        };

        await _pumpConnectedScreen(tester, detailBlob: detailBlob);

        expect(find.text('Label Total Omega-3 Fatty Acids'), findsOneWidget);
        expect(find.text('Scoring-only EPA identity'), findsNothing);

        await _scrollConnectedTowardTop(tester);
        // A 100%-complete label is now a silent success — no completeness row.
        expect(find.text('Label completeness: 100%'), findsNothing);
        expect(find.textContaining('Analysis coverage'), findsNothing);
        final scoreHeadline = find.text('Why this scored 88');
        await _scrollConnectedTowardBottomUntil(tester, scoreHeadline);
        expect(scoreHeadline, findsOneWidget);
        expect(find.text('12/20'), findsOneWidget);
      },
    );

    testWidgets(
      'probiotic label research follows Ingredients and renders only once',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpConnectedScreen(
          tester,
          detailBlob: {
            'ingredients': const <Map<String, dynamic>>[],
            'display_ingredients': const [
              {
                'label_display_name': 'Lactobacillus acidophilus NCFM',
                'label_order': 0,
                'nested_depth': 0,
                'score_included': true,
                'display_disposition': 'scored',
                'form_display_state': 'not_disclosed',
              },
            ],
            'quality_pillars_v4': _connectedV4Pillars(),
            'probiotic_detail': const {
              'total_cfu_label': '5 billion CFU',
              'probiotic_blends': [
                {
                  'strains': ['Lactobacillus acidophilus NCFM'],
                },
              ],
            },
          },
        );

        final ingredientsTitle = find.text('Active ingredients');
        final probioticTitle = find.text('Probiotic label & research');
        expect(ingredientsTitle, findsOneWidget);
        expect(probioticTitle, findsOneWidget);
        final sectionGap =
            tester.getTopLeft(probioticTitle).dy -
            tester.getTopLeft(ingredientsTitle).dy;
        expect(sectionGap, greaterThan(0));
        // The card belongs directly after the ingredient ledger, before the
        // remaining deep-dive sections. This guards against it drifting back
        // to the bottom of the page.
        expect(sectionGap, lessThan(210));
      },
    );

    testWidgets('connected screen keeps unsupported label audit internal', (
      tester,
    ) async {
      await _pumpConnectedScreen(
        tester,
        detailBlob: {
          'ingredients': const <Map<String, dynamic>>[],
          'display_ingredients': const [
            {
              'label_display_name': 'Literal label row',
              'label_order': 0,
              'nested_depth': 0,
              'raw_source_path': 'ingredientRows[0]',
              'score_included': false,
              'display_disposition': 'needs_review',
              'form_display_state': 'needs_review',
            },
          ],
          'quality_pillars_v4': _connectedV4Pillars(),
          'label_ledger_audit': const {
            'support_status': 'unsupported',
            'source_structure': 'unsupported_source_structure',
            'meaningful_source_rows': 0,
            'displayed_rows': 0,
            'omitted_rows': 1,
            'completeness_percentage': null,
            'completeness_status': 'unavailable',
          },
        },
      );

      await _scrollConnectedTowardTop(tester);
      expect(find.text('Label completeness unavailable'), findsNothing);
      expect(find.textContaining('Label data unavailable'), findsNothing);
      expect(find.text('Label completeness: 100%'), findsNothing);
      expect(find.textContaining('Analysis coverage'), findsNothing);
    });

    final malformedAuditCases = <({String name, Object? value})>[
      (name: 'non-map', value: 'malformed audit payload'),
      (name: 'explicit-null', value: null),
      (name: 'empty-map', value: const <String, dynamic>{}),
    ];
    for (final auditCase in malformedAuditCases) {
      testWidgets(
        'connected screen keeps present ${auditCase.name} audit internal',
        (tester) async {
          await _pumpConnectedScreen(
            tester,
            detailBlob: {
              'ingredients': const <Map<String, dynamic>>[],
              'display_ingredients': const [
                {
                  'label_display_name': 'Literal label row',
                  'label_order': 0,
                  'nested_depth': 0,
                  'raw_source_path': 'ingredientRows[0]',
                  'score_included': false,
                  'display_disposition': 'needs_review',
                  'form_display_state': 'needs_review',
                },
              ],
              'quality_pillars_v4': _connectedV4Pillars(),
              'label_ledger_audit': auditCase.value,
            },
          );

          await _scrollConnectedTowardTop(tester);
          expect(find.text('Label completeness unavailable'), findsNothing);
          expect(find.textContaining('Label data unavailable'), findsNothing);
          expect(find.textContaining('Label completeness:'), findsNothing);
          expect(find.textContaining('Analysis coverage'), findsNothing);
        },
      );
    }

    testWidgets('absent audit key does not create an audit-only section', (
      tester,
    ) async {
      await _pumpConnectedScreen(
        tester,
        detailBlob: {
          'ingredients': const <Map<String, dynamic>>[],
          'display_ingredients': const [
            {
              'label_display_name': 'Legacy blob label row',
              'label_order': 0,
              'nested_depth': 0,
              'raw_source_path': 'ingredientRows[0]',
              'score_included': false,
              'display_disposition': 'label_context',
              'form_display_state': 'not_applicable',
            },
          ],
          'quality_pillars_v4': _connectedV4Pillars(),
        },
      );

      await _scrollConnectedTowardTop(tester);
      expect(find.text('Label completeness unavailable'), findsNothing);
      expect(find.textContaining('Label completeness:'), findsNothing);
      expect(find.text('Label data'), findsNothing);
      expect(find.textContaining('Analysis coverage'), findsNothing);
    });

    testWidgets(
      'display_ingredients wins and preserves omega source order and hierarchy',
      (tester) async {
        final ledger = <Map<String, dynamic>>[
          {
            'label_display_name': 'Fish Oil',
            'exact_dose_text': '2,400 mg',
            'label_order': 0,
            'nested_depth': 0,
            'raw_source_path': 'ingredientRows[0]',
            'score_included': true,
            'display_disposition': 'scored',
            'form_display_state': 'not_disclosed',
          },
          {
            'label_display_name': 'Total Omega-3 Fatty Acids',
            'exact_dose_text': '720 mg',
            'label_order': 1,
            'nested_depth': 1,
            'parent_label': 'Fish Oil',
            'raw_source_path': 'ingredientRows[0].nestedRows[0]',
            'score_included': false,
            'display_disposition': 'label_context',
            'form_display_state': 'not_applicable',
          },
          {
            'label_display_name': 'EPA',
            'exact_dose_text': '360 mg',
            'label_order': 2,
            'nested_depth': 2,
            'parent_label': 'Total Omega-3 Fatty Acids',
            'raw_source_path': 'ingredientRows[0].nestedRows[0].nestedRows[0]',
            'score_included': true,
            'display_disposition': 'scored',
            'form_display_state': 'not_disclosed',
          },
          {
            'label_display_name': 'DHA',
            'exact_dose_text': '240 mg',
            'label_order': 3,
            'nested_depth': 2,
            'parent_label': 'Total Omega-3 Fatty Acids',
            'raw_source_path': 'ingredientRows[0].nestedRows[0].nestedRows[1]',
            'score_included': true,
            'display_disposition': 'scored',
            'form_display_state': 'not_disclosed',
          },
          {
            'label_display_name': 'Other Omega-3 Fatty Acids',
            'exact_dose_text': '120 mg',
            'label_order': 4,
            'nested_depth': 2,
            'parent_label': 'Total Omega-3 Fatty Acids',
            'raw_source_path': 'ingredientRows[0].nestedRows[0].nestedRows[2]',
            'score_included': false,
            'display_disposition': 'label_context',
            'form_display_state': 'not_applicable',
          },
        ];

        await tester.pumpWidget(
          _ingredientsHarness(
            ingredients: const [
              {
                'display_label': 'Legacy scoring row must not render',
                'quantity': 999,
                'unit': 'mg',
              },
            ],
            displayIngredients: ledger,
            inactiveIngredients: const [
              {'name': 'Legacy inactive row must not render'},
            ],
          ),
        );
        await tester.pumpAndSettle();

        final rows = tester
            .widgetList<PGActiveIngredientTile>(
              find.byType(PGActiveIngredientTile),
            )
            .map((tile) => tile.ingredient)
            .toList(growable: false);

        expect(rows.map((row) => row.name), [
          'Fish Oil',
          'Total Omega-3 Fatty Acids',
          'EPA',
          'DHA',
          'Other Omega-3 Fatty Acids',
        ]);
        expect(rows.map((row) => row.labelOrder), [0, 1, 2, 3, 4]);
        expect(rows.map((row) => row.nestedDepth), [0, 1, 2, 2, 2]);
        expect(rows.map((row) => row.parentLabel), [
          null,
          'Fish Oil',
          'Total Omega-3 Fatty Acids',
          'Total Omega-3 Fatty Acids',
          'Total Omega-3 Fatty Acids',
        ]);
        expect(rows.map((row) => row.scoreIncluded), [
          true,
          false,
          true,
          true,
          false,
        ]);
        expect(find.text('Legacy scoring row must not render'), findsNothing);
        expect(find.text('Legacy inactive row must not render'), findsNothing);
      },
    );

    testWidgets(
      'canonical ledger renders one bottle-faithful label view (no toggle)',
      (tester) async {
        await tester.pumpWidget(
          _ingredientsHarness(
            ingredients: const [],
            displayIngredients: _analysisLedger(),
          ),
        );
        await tester.pumpAndSettle();

        // The consumer Analysis toggle is removed — one faithful label view.
        expect(
          find.byKey(const ValueKey('ingredient-view-analysis')),
          findsNothing,
        );
        expect(find.textContaining('Analysis '), findsNothing);
        // Every label row renders in source order (no score-only projection).
        expect(
          tester
              .widgetList<PGActiveIngredientTile>(
                find.byType(PGActiveIngredientTile),
              )
              .map((tile) => tile.ingredient.name),
          [
            'Fish Oil',
            'Total Omega-3 Fatty Acids',
            'EPA',
            'DHA',
            'Other Omega-3 Fatty Acids',
          ],
        );
      },
    );

    testWidgets('legacy blobs render a single ingredient list, no toggle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _ingredientsHarness(
          ingredients: const [
            {
              'display_label': 'Legacy scored row',
              'quantity': 10,
              'unit': 'mg',
            },
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ingredient-view-analysis')),
        findsNothing,
      );
      expect(find.textContaining('Analysis '), findsNothing);
      expect(find.text('Legacy scored row'), findsOneWidget);
    });

    testWidgets('logical Folate stays one row with its parenthetical amount', (
      tester,
    ) async {
      await tester.pumpWidget(
        _ingredientsHarness(
          ingredients: const [
            {'display_label': 'Folate', 'quantity': 665, 'unit': 'mcg DFE'},
            {'display_label': 'Folate', 'quantity': 400, 'unit': 'mcg'},
          ],
          displayIngredients: const [
            {
              'label_display_name': 'Folate',
              'exact_dose_text': '665 mcg DFE',
              'parenthetical_dose_text': '400 mcg folic acid',
              'label_order': 0,
              'nested_depth': 0,
              'raw_source_path': 'ingredientRows[0]',
              'score_included': true,
              'display_disposition': 'scored',
              'form_display_state': 'listed_not_assessed',
              'label_display_form': 'folic acid',
            },
          ],
        ),
      );
      await tester.pumpAndSettle();

      final rows = tester
          .widgetList<PGActiveIngredientTile>(
            find.byType(PGActiveIngredientTile),
          )
          .map((tile) => tile.ingredient)
          .toList(growable: false);
      expect(rows, hasLength(1));
      expect(rows.single.name, 'Folate');
      expect(rows.single.dose, '665 mcg DFE');
      expect(rows.single.parentheticalDoseText, '400 mcg folic acid');
    });

    testWidgets(
      'Other Ingredients stay visible through the same label ledger',
      (tester) async {
        await tester.pumpWidget(
          _ingredientsHarness(
            ingredients: const [],
            inactiveIngredients: const [
              {
                'name': 'Gelatin',
                'display_role_label': 'Gelatin capsule',
                'functional_roles': ['coating', 'gelling_agent'],
              },
            ],
            displayIngredients: const [
              {
                'label_display_name': 'Gelatin',
                'raw_source_text': 'Gelatin',
                'label_order': 8,
                'nested_depth': 0,
                'raw_source_path': 'otheringredients.ingredients[0]',
                'score_included': false,
                'display_disposition': 'other_ingredient',
                'form_display_state': 'not_applicable',
              },
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PGActiveIngredientTile), findsNothing);
        expect(find.text('Other ingredients'), findsOneWidget);
        expect(find.text('Gelatin'), findsOneWidget);
        expect(find.text('Gelatin capsule'), findsOneWidget);
      },
    );

    testWidgets(
      'legacy scoring ingredients are used only when the ledger is absent',
      (tester) async {
        const legacy = [
          {'display_label': 'Undisclosed first on label'},
          {
            'display_label': 'Disclosed second on label',
            'quantity': 10,
            'unit': 'mg',
          },
        ];

        await tester.pumpWidget(_ingredientsHarness(ingredients: legacy));
        await tester.pumpAndSettle();
        final names = tester
            .widgetList<PGActiveIngredientTile>(
              find.byType(PGActiveIngredientTile),
            )
            .map((tile) => tile.ingredient.name)
            .toList(growable: false);
        expect(names, [
          'Disclosed second on label',
          'Undisclosed first on label',
        ]);

        await tester.pumpWidget(
          _ingredientsHarness(
            ingredients: legacy,
            displayIngredients: const [],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PGActiveIngredientTile), findsNothing);
        expect(find.text('Disclosed second on label'), findsNothing);
      },
    );
  });

  testWidgets('missing product id renders v2 unavailable state', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    final router = GoRouter(
      initialLocation: Routes.productDetail('missing-product'),
      routes: [
        GoRoute(
          path: '${Routes.product}/:dsldId',
          builder: (_, state) => ProductDetailV2ConnectedScreen(
            dsldId: state.pathParameters['dsldId']!,
          ),
        ),
        GoRoute(
          path: Routes.search,
          builder: (_, __) => const Scaffold(body: Text('Search v2')),
        ),
        GoRoute(
          path: Routes.home,
          builder: (_, __) => const Scaffold(body: Text('Home v2')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [coreDatabaseProvider.overrideWithValue(coreDb)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Product unavailable'), findsOneWidget);
    expect(find.textContaining('verified catalog'), findsOneWidget);

    await tester.tap(find.text('Search catalog'));
    await tester.pumpAndSettle();
    expect(find.text('Search v2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
  });
}
