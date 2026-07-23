import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_review_before_use_card.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/features/product_detail/allergen_match.dart';
import 'package:pharmaguide/features/product_detail/free_from_match.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_helpers.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

FitScoreResult _fit({
  FitAssessmentState state = FitAssessmentState.limitedFit,
  List<String> reasons = const [],
  double mappedCoverage = 1,
}) {
  return FitScoreResult(
    scoreFit20: 10,
    e1: 0,
    e2a: 0,
    e2b: 0,
    e2c: 0,
    missingFields: const [],
    maxPossible: 100,
    state: state,
    reasons: reasons,
    mappedCoverage: mappedCoverage,
  );
}

InteractionWarning _warning({
  Severity severity = Severity.caution,
  EvidenceLevel evidenceLevel = EvidenceLevel.established,
  String title = 'Interaction',
  String mechanism = '',
  String management = '',
  String? alertHeadline,
  String? alertBody,
  List<String> conditionIds = const [],
  List<String> drugClassIds = const [],
  String? ingredientName,
  String? direction,
  String? displayModeDefault,
}) {
  return InteractionWarning(
    severity: severity,
    evidenceLevel: evidenceLevel,
    title: title,
    mechanism: mechanism,
    management: management,
    alertHeadline: alertHeadline,
    alertBody: alertBody,
    conditionIds: conditionIds,
    drugClassIds: drugClassIds,
    ingredientName: ingredientName,
    direction: direction,
    displayModeDefault: displayModeDefault,
  );
}

MatchedAllergen _allergen({
  String id = 'ALLERGEN_SOY',
  String displayName = 'Soy',
  String presenceType = 'contains',
  String severityLevel = 'moderate',
  String? evidence,
}) {
  return MatchedAllergen(
    id: id,
    displayName: displayName,
    presenceType: presenceType,
    severityLevel: severityLevel,
    evidence: evidence,
  );
}

ProfileRelevanceSummary _summary({
  FitScoreResult? fitResult,
  List<InteractionWarning> warnings = const [],
  String interactionHint = '',
  List<MatchedAllergen> matchedAllergens = const [],
  List<String> freeFromConflicts = const [],
  bool hasInteractionProfile = true,
  bool hasCriticalGlobalNote = false,
  bool hasProfileInformation = true,
  List<String> selectedGoalLabels = const [],
}) {
  return buildProfileRelevanceSummary(
    fitResult: fitResult ?? _fit(),
    topGoalLabel: null,
    warnings: warnings,
    interactionHint: interactionHint,
    matchedAllergens: matchedAllergens,
    freeFromConflicts: freeFromConflicts,
    hasInteractionProfile: hasInteractionProfile,
    hasCriticalGlobalNote: hasCriticalGlobalNote,
    hasProfileInformation: hasProfileInformation,
    selectedGoalLabels: selectedGoalLabels,
  );
}

Future<void> _pump(WidgetTester tester, ProfileRelevanceSummary summary) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProfileRelevanceSection(
          summary: summary,
          onCompleteProfile: () {},
        ),
      ),
    ),
  );
}

void main() {
  group('buildProfileRelevanceSummary', () {
    test(
      'unmatched product states the result without a vague neutral label',
      () {
        final summary = _summary(fitResult: _fit());

        expect(summary.status, ProfileRelevanceStatus.neutral);
        expect(summary.headline, 'No profile-specific concerns found');
        expect(summary.body, contains('Based on the profile information'));
        expect(summary.body, contains('Add goals'));
        expect(summary.rows, isEmpty);
      },
    );

    test(
      'strong and good fit keep safety primary and goal match secondary',
      () {
        final summary = _summary(
          fitResult: _fit(
            state: FitAssessmentState.goodFit,
            reasons: const ['Backed by clinical evidence.'],
          ),
          selectedGoalLabels: const ['Sleep'],
        );

        expect(summary.status, ProfileRelevanceStatus.goodMatch);
        expect(summary.headline, 'No profile-specific concerns found');
        expect(summary.body, contains('No specific match found'));
      },
    );

    test('critical global substance note removes the green safe all-clear', () {
      // A moderate harmful additive / high-risk ingredient (caution severity,
      // display_mode_default == 'critical') lives in the calm general bucket,
      // so buildProfileRelevanceSummary never sees the row — but the pipeline
      // flagged it a substance-level hazard. The positive verdict must not
      // render a green "safe" all-clear over it. Both green branches downgrade
      // to a neutral (info) tone; the goal-fit headline is unchanged.
      for (final state in const [
        FitAssessmentState.strongMatch,
        FitAssessmentState.goodFit,
      ]) {
        final green = _summary(fitResult: _fit(state: state));
        expect(green.tone, PGReviewTone.safe, reason: 'baseline is green');

        final gated = _summary(
          fitResult: _fit(state: state),
          hasCriticalGlobalNote: true,
        );
        expect(
          gated.tone,
          PGReviewTone.info,
          reason: 'no green all-clear over a substance-level critical note',
        );
        expect(gated.status, green.status, reason: 'goal-fit status unchanged');
        expect(gated.headline, green.headline, reason: 'headline unchanged');
      }
    });

    test('barley product plus non-barley profile does not show barley', () {
      final matches = matchAllergens(
        const ['ALLERGEN_SOY'],
        const [
          {
            'allergen_id': 'ALLERGEN_BARLEY',
            'display_name': 'Barley',
            'presence_type': 'contains',
            'severity_level': 'moderate',
          },
        ],
      );
      final summary = _summary(matchedAllergens: matches);

      expect(matches, isEmpty);
      expect(summary.status, ProfileRelevanceStatus.neutral);
      expect(summary.rows.map((r) => r.headline), isNot(contains('Barley')));
    });

    test('profile-matched contains allergen is not recommended', () {
      final matches = matchAllergens(
        const ['ALLERGEN_BARLEY'],
        const [
          {
            'allergen_id': 'ALLERGEN_BARLEY',
            'display_name': 'Barley',
            'presence_type': 'contains',
            'severity_level': 'moderate',
          },
        ],
      );
      final summary = _summary(matchedAllergens: matches);

      expect(summary.status, ProfileRelevanceStatus.notRecommended);
      expect(summary.headline, 'Not recommended for your profile');
      expect(summary.body, 'Contains an allergen in your profile.');
      expect(summary.rows.map((r) => r.headline), contains('Barley'));
    });

    test('profile-matched may-contain allergen requires review', () {
      final summary = _summary(
        matchedAllergens: [
          _allergen(displayName: 'Tree nuts', presenceType: 'may_contain'),
        ],
      );

      expect(summary.status, ProfileRelevanceStatus.review);
      expect(summary.headline, 'Review before use');
      expect(summary.rows.single.headline, 'Tree nuts');
    });

    test('medication avoid warning is not recommended', () {
      final summary = _summary(
        warnings: [
          _warning(
            severity: Severity.avoid,
            title: 'Medication conflict',
            drugClassIds: const ['anticoagulants'],
          ),
        ],
      );

      expect(summary.status, ProfileRelevanceStatus.notRecommended);
      expect(summary.body, 'Conflicts with your medication profile.');
    });

    test('condition caution warning requires review', () {
      final summary = _summary(
        warnings: [
          _warning(
            severity: Severity.caution,
            title: 'Condition note',
            conditionIds: const ['hypertension'],
          ),
        ],
      );

      expect(summary.status, ProfileRelevanceStatus.review);
      expect(summary.headline, 'Review before use');
      expect(summary.body, 'Condition note.');
    });

    test(
      'incomplete profile with caution still shows review plus CTA state',
      () {
        final summary = _summary(
          fitResult: _fit(state: FitAssessmentState.incompleteProfile),
          hasProfileInformation: false,
          warnings: [
            _warning(
              severity: Severity.caution,
              title: 'Condition note',
              conditionIds: const ['hypertension'],
            ),
          ],
        );

        expect(summary.status, ProfileRelevanceStatus.review);
        expect(summary.profileIncomplete, isTrue);
        expect(summary.headline, 'Review before use');
        expect(summary.body, 'Condition note.');
      },
    );

    test('free-from conflict requires review inside the same rows', () {
      final summary = _summary(freeFromConflicts: const ['gluten']);

      expect(summary.status, ProfileRelevanceStatus.review);
      expect(
        summary.rows.map((r) => r.headline),
        contains('Conflicting label evidence'),
      );
      expect(
        summary.rows.map((r) => r.headline),
        isNot(contains('Gluten-free')),
        reason:
            'positive label reassurance belongs in Good to know, not the '
            'risk-focused Profile Relevance card',
      );
    });

    test('missing fit result renders incomplete profile action state', () {
      final summary = buildProfileRelevanceSummary(
        fitResult: null,
        topGoalLabel: null,
        warnings: const [],
        interactionHint: '{"has_any": true}',
        matchedAllergens: const [],
        freeFromConflicts: const [],
        hasInteractionProfile: false,
        hasProfileInformation: false,
      );

      expect(summary.status, ProfileRelevanceStatus.incomplete);
      expect(summary.headline, 'Check this product for you');
      expect(summary.body, contains('known interactions'));
    });

    test('low-coverage limited fit uses coverage hedge, not neutral copy', () {
      final summary = _summary(
        fitResult: _fit(
          mappedCoverage: 0.2,
          reasons: const [
            'Ingredient mapping coverage is low, so this fit is conservative.',
          ],
        ),
      );

      expect(summary.status, ProfileRelevanceStatus.coverageLimited);
      expect(summary.headline, 'Profile assessment unavailable');
      expect(summary.body, isNull);
      expect(
        summary.body,
        isNot('General-use product, not targeted to your profile.'),
      );
    });
  });

  group('ProfileRelevanceSection rendering', () {
    testWidgets('renders the clean profile decision even without a goal', (
      tester,
    ) async {
      await _pump(tester, _summary());

      expect(find.text('FOR YOU'), findsOneWidget);
      expect(find.text('No profile-specific concerns found'), findsOneWidget);
      expect(find.text('Add goals'), findsOneWidget);
    });

    testWidgets('omits coverage-limited result from the profile card', (
      tester,
    ) async {
      await _pump(tester, _summary(fitResult: _fit(mappedCoverage: 0.2)));

      expect(find.text('FOR YOU'), findsNothing);
      expect(find.text('Profile assessment unavailable'), findsNothing);
    });

    testWidgets('review rows render inside Profile Relevance', (tester) async {
      await _pump(
        tester,
        _summary(
          warnings: [
            _warning(severity: Severity.caution, title: 'Caution row'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FOR YOU'), findsOneWidget);
      expect(find.text('Review before use'), findsOneWidget);
      expect(find.text('Caution row'), findsOneWidget);
    });

    testWidgets('contains allergen row renders as not recommended', (
      tester,
    ) async {
      await _pump(
        tester,
        _summary(matchedAllergens: [_allergen(displayName: 'Soy')]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not recommended for your profile'), findsOneWidget);
      expect(find.text('Soy'), findsOneWidget);
    });

    testWidgets('incomplete state keeps complete-profile action in card', (
      tester,
    ) async {
      final summary = buildProfileRelevanceSummary(
        fitResult: null,
        topGoalLabel: null,
        warnings: const [],
        interactionHint: '',
        matchedAllergens: const [],
        freeFromConflicts: const [],
        hasInteractionProfile: false,
        hasProfileInformation: false,
      );

      await _pump(tester, summary);

      expect(find.text('Check this product for you'), findsOneWidget);
      expect(find.text('Add profile information'), findsOneWidget);
      final action = tester.widget<PGPillButton>(find.byType(PGPillButton));
      expect(action.variant, PGPillVariant.ghost);
      expect(action.icon, Icons.edit_outlined);
    });

    testWidgets(
      'review state keeps complete-profile action when fit incomplete',
      (tester) async {
        await _pump(
          tester,
          _summary(
            fitResult: _fit(state: FitAssessmentState.incompleteProfile),
            hasProfileInformation: false,
            warnings: [
              _warning(severity: Severity.caution, title: 'Caution row'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Review before use'), findsOneWidget);
        expect(find.text('Caution row'), findsOneWidget);
        expect(find.text('Add profile information'), findsOneWidget);
      },
    );

    testWidgets('positive match keeps why-this-fits and edit action', (
      tester,
    ) async {
      await _pump(
        tester,
        _summary(
          fitResult: _fit(
            state: FitAssessmentState.goodFit,
            reasons: const ['Backed by clinical evidence.'],
          ),
          selectedGoalLabels: const ['Sleep'],
        ),
      );

      expect(find.text('Why this fits you'), findsOneWidget);
      expect(find.text('Edit profile'), findsOneWidget);
      final action = tester.widget<PGPillButton>(find.byType(PGPillButton));
      expect(action.variant, PGPillVariant.ghost);
      expect(action.icon, Icons.edit_outlined);
    });

    testWidgets('good-to-know informational rows do not create warning cards', (
      tester,
    ) async {
      final section = buildGeneralNotesSection(
        warnings: [
          _warning(
            title: 'General nutrient guidance',
            displayModeDefault: 'informational',
          ),
        ],
      );

      expect(section, isNull);
    });

    testWidgets('verified free-from reassurance renders in Good to know', (
      tester,
    ) async {
      final section = buildGeneralNotesSection(
        warnings: const [],
        freeFromClaims: const [
          FreeFromClaim(
            label: 'Gluten-free',
            concern: 'gluten',
            status: FreeFromStatus.certified,
          ),
          FreeFromClaim(
            label: 'Soy-free',
            concern: 'soy',
            status: FreeFromStatus.unknown,
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: section)));

      expect(find.text('GOOD TO KNOW'), findsOneWidget);
      await tester.tap(find.text('Information for your profile'));
      await tester.pumpAndSettle();
      expect(find.text('Gluten-free'), findsOneWidget);
      expect(find.text('Soy-free'), findsNothing);
      expect(find.text('PRODUCT SAFETY'), findsNothing);
    });

    testWidgets(
      'profile-scoped no-data advisory is intentionally suppressed (no card)',
      (tester) async {
        // Policy "if we don't know, we don't flag": a no_data-evidence advisory
        // is deliberately shown in NEITHER lane — not the amber review card and
        // not the calm "Good to know" card — so generic "limited safety data"
        // notes don't recreate meaningless-warning noise. This null is the
        // intended behavior; do NOT "fix" it by routing no_data into Good to
        // know (see warnings_pipeline.dart no_data policy note).
        final section = buildGeneralNotesSection(
          warnings: [
            _warning(
              severity: Severity.monitor,
              evidenceLevel: EvidenceLevel.noData,
              title: 'Limited safety data',
              alertBody: 'Specific safety evidence is limited.',
              conditionIds: const ['lactation'],
            ),
          ],
        );

        expect(section, isNull);
      },
    );

    testWidgets('normal-dose breastfeeding advisory renders in Good to know', (
      tester,
    ) async {
      final section = buildGeneralNotesSection(
        warnings: [
          _warning(
            severity: Severity.informational,
            evidenceLevel: EvidenceLevel.probable,
            title: 'High-dose B6 may affect milk supply',
            alertBody: 'Higher supplemental doses may affect milk supply.',
            conditionIds: const ['lactation'],
            displayModeDefault: 'informational',
            direction: 'harmful',
          ),
        ],
      );

      expect(section, isNotNull);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: section!)));
      expect(find.text('GOOD TO KNOW'), findsOneWidget);
      expect(find.text('Review this product'), findsNothing);
    });

    testWidgets('profile-matched beneficial note renders as Good to know', (
      tester,
    ) async {
      final section = buildGeneralNotesSection(
        warnings: [
          _warning(
            severity: Severity.monitor,
            evidenceLevel: EvidenceLevel.probable,
            title: 'May support blood pressure goals',
            alertBody: 'This nutrient may support healthy blood pressure.',
            conditionIds: const ['hypertension'],
            direction: 'beneficial',
          ),
        ],
      );

      expect(section, isNotNull);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: section!)));
      expect(find.text('GOOD TO KNOW'), findsOneWidget);
      expect(find.text('Review this product'), findsNothing);
    });

    testWidgets('material global safety note remains visible', (tester) async {
      final section = buildGeneralNotesSection(
        warnings: [
          _warning(
            title: 'Review this additive',
            displayModeDefault: 'critical',
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: section)));
      await tester.pumpAndSettle();
      expect(find.text('PRODUCT SAFETY'), findsOneWidget);
      expect(find.text('Review this product'), findsOneWidget);
    });
  });

  group('rowForWarning concern-level caption', () {
    test('leads the caption with the plain-language severity label', () {
      final row = rowForWarning(
        _warning(
          severity: Severity.caution,
          alertHeadline: 'Chromium may affect your diabetes meds',
          alertBody: 'Watch your blood sugar.',
        ),
      );
      expect(row.caption, startsWith('Use caution ·'));
    });

    test('does not lead with a label for a non-actionable warning', () {
      final row = rowForWarning(
        _warning(
          severity: Severity.informational,
          alertBody: 'Just so you know.',
        ),
      );
      expect(row.caption, isNot(startsWith('Informational ·')));
    });
  });
}
