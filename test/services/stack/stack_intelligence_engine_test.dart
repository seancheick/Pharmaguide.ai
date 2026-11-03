import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/core/utils/stack_intelligence_helpers.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

InteractionResult _interaction({
  required String id,
  required Severity severity,
  String mechanism = 'mech',
  InteractionType type = InteractionType.supplementSupplement,
  String? alertStyle,
}) {
  return InteractionResult(
    id: id,
    type: type,
    severity: severity,
    evidenceLevel: EvidenceLevel.established,
    agent1Name: 'A',
    agent2Name: 'B',
    mechanism: mechanism,
    management: 'manage',
    doseDependant: false,
    doseThreshold: null,
    sourceUrls: const <String>[],
    source: InteractionSource.pipeline,
    alertStyle: alertStyle,
  );
}

NutrientStatus _nutrient({
  required String id,
  required NutrientTier tier,
  String? warning,
}) {
  return NutrientStatus(
    total: NutrientTotal(
      canonicalId: id,
      displayName: id,
      totalAmount: 100,
      unit: 'mg',
      contributions: const <NutrientContribution>[],
    ),
    tier: tier,
    warning: warning,
  );
}

MedicationProfileWarning _profileWarning({
  required String id,
  required Severity severity,
  String headline = 'Review NSAID use in pregnancy',
}) {
  return MedicationProfileWarning(
    id: id,
    ruleId: id,
    medicationName: 'Motrin',
    severity: severity,
    evidenceLevel: EvidenceLevel.established,
    headline: headline,
    body: 'NSAIDs are generally avoided from 20 weeks of pregnancy.',
    management: 'Check with your clinician.',
    sourceUrls: const <String>[],
  );
}

RecalledIngredientViolation _violation({
  required String productName,
  required String recallStatus,
  String severity = 'major',
}) {
  return RecalledIngredientViolation(
    productDsldId: 'D-${productName.hashCode}',
    productName: productName,
    brandName: 'Brand',
    recalledIngredients: [
      RecalledIngredientAlert(
        canonicalId: 'IND',
        commonNames: const ['ingredient'],
        recallStatus: recallStatus,
        regulatoryBasis: 'FDA',
        reason: 'reason',
        effectiveDate: '2026-01-01',
        severity: severity,
        safetyWarning: 'warn',
        safetyWarningOneLiner: 'one liner',
        banContext: 'substance',
      ),
    ],
  );
}

StackDoseThresholdAlert _doseAlert({
  String conditionId = 'pregnancy',
  String canonicalId = 'caffeine',
  String displayName = 'Caffeine',
  double totalValue = 240,
  String unit = 'mg',
  double thresholdValue = 200,
  bool isIncomplete = false,
  Severity clinicalSeverity = Severity.caution,
  ConsumerDisposition consumerDisposition = ConsumerDisposition.review,
}) {
  return StackDoseThresholdAlert(
    conditionId: conditionId,
    canonicalId: canonicalId,
    displayName: displayName,
    totalValue: totalValue,
    unit: unit,
    thresholdValue: thresholdValue,
    thresholdUnit: unit,
    contributions: const [],
    isIncomplete: isIncomplete,
    clinicalSeverity: clinicalSeverity,
    consumerDisposition: consumerDisposition,
  );
}

class _ReadableFeed implements SafetyAlertRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<SafetyAlertRelease> loadCurrent() async => const SafetyAlertRelease(
    alerts: [],
    baselineRevisions: {},
    isComplete: true,
  );
}

void main() {
  const engine = StackIntelligenceEngine();
  final emptySynergy = SynergyReport.empty();
  final emptyRecall = RecalledIngredientsReport.empty();

  group('the shared snapshot reads regulatory alerts', () {
    Future<StackHealthSnapshot> snapshot({
      bool unavailable = false,
      bool offline = false,
      bool unreadableDevice = false,
      bool reloadMatches = false,
      bool refreshMatches = false,
      bool throws = false,
      List<({SafetyAlert alert, String dsldId})> matches = const [],
    }) async {
      final now = DateTime.utc(2026, 11, 3);
      var contextChanged = false;
      final matchingContext = Provider<int>((_) => contextChanged ? 1 : 0);
      final pendingMatches = Completer<SafetyAlertMatchSet>();
      final container = ProviderContainer(
        overrides: [
          activeStackProvider.overrideWith(
            (_) async => [
              UserStacksLocalData(
                id: 'p',
                type: 'supplement',
                name: 'Fixture',
                dsldId: '999',
                addedAt: now,
                clientUpdatedAt: now,
              ),
            ],
          ),
          stackSafetyReportProvider.overrideWith(
            (_) async => const StackSafetyReport(),
          ),
          recalledIngredientsReportProvider.overrideWith(
            (_) async => emptyRecall,
          ),
          synergyReportProvider.overrideWith((_) async => emptySynergy),
          stackDoseThresholdAlertsProvider.overrideWith((_) async => []),
          if (unreadableDevice) ...[
            deviceSafetyProfileProvider.overrideWith(
              (_) async => const DeviceSafetyProfile(isComplete: false),
            ),
            safetyAlertRepositoryProvider.overrideWithValue(_ReadableFeed()),
          ] else
            safetyAlertMatchesProvider.overrideWith((ref) async {
              ref.watch(matchingContext);
              if (contextChanged) return pendingMatches.future;
              if (throws) throw StateError('feed cannot be read');
              return SafetyAlertMatchSet(
                matches: matches,
                baselineSignalKeys: {},
                isComplete: !unavailable && !offline,
                neverVerified: unavailable,
              );
            }),
        ],
      );
      addTearDown(container.dispose);
      try {
        await container.read(safetyAlertMatchesProvider.future);
      } on Object {
        // The provider failure itself is the fixture under test.
      }
      if (reloadMatches) {
        await container.read(stackHealthSnapshotProvider.future);
        contextChanged = true;
        if (refreshMatches) {
          container.invalidate(safetyAlertMatchesProvider);
        } else {
          container.invalidate(matchingContext);
        }
        await container.pump();
        expect(container.read(safetyAlertMatchesProvider).hasValue, isTrue);
        expect(
          container.read(safetyAlertMatchesProvider).isReloading,
          !refreshMatches,
        );
      }
      return container.read(stackHealthSnapshotProvider.future);
    }

    test('an unverified feed withholds a clean Stack Health result', () async {
      for (final throws in [false, true]) {
        final result = await snapshot(unavailable: true, throws: throws);
        expect(result.checksIncomplete, isTrue);
        expect(result.intelligence.analysisIncomplete, isTrue);
        expect(result.intelligence.tier, StackTier.incomplete);
      }
    });

    test('a verified feed preserves the clean Stack Health result', () async {
      for (final offline in [false, true]) {
        final result = await snapshot(offline: offline);
        expect(result.checksIncomplete, isFalse);
        expect(result.intelligence.tier, StackTier.optimized);
      }
    });

    test(
      'prior alert matches cannot clear a changed matching context',
      () async {
        for (final refresh in [false, true]) {
          final result = await snapshot(
            reloadMatches: true,
            refreshMatches: refresh,
          );
          expect(result.checksIncomplete, !refresh);
          expect(
            result.intelligence.tier,
            refresh ? StackTier.optimized : StackTier.incomplete,
          );
        }
      },
    );

    test('a readable feed cannot clear an unreadable device profile', () async {
      final result = await snapshot(unreadableDevice: true);
      expect(result.checksIncomplete, isTrue);
      expect(result.intelligence.tier, StackTier.incomplete);
    });

    test('recall and ban summaries do not call them interactions', () async {
      final feed = jsonDecode(
        File(
          'test/fixtures/safety_alerts/interaction_rule_feed.json',
        ).readAsStringSync(),
      );
      for (final row
          in (feed['alerts'] as List).cast<Map<String, dynamic>>().where(
            (r) => r['event_type'] != 'interaction_rule',
          )) {
        for (final disposition in ['block', 'review']) {
          final alert = SafetyAlert.fromJson({
            ...row,
            'consumer_disposition': disposition,
          });
          final result = await snapshot(
            matches: [(alert: alert, dsldId: '999')],
          );
          expect(result.reviewSignals, hasLength(1));
          expect(result.intelligence.interactionCount, 0);
          expect(
            result.intelligence.tier,
            disposition == 'block' ? StackTier.concerning : StackTier.decent,
          );
          expect(
            describeStackSummary(result.intelligence),
            isNot(contains('interaction')),
          );
          expect(describeStackSummary(result.intelligence), contains('review'));
        }
      }
    });

    test(
      'an authored alert reaches Home and Stack through the shared snapshot',
      () async {
        final feed = jsonDecode(
          File(
            'test/fixtures/safety_alerts/interaction_rule_feed.json',
          ).readAsStringSync(),
        );
        final alert = SafetyAlert.fromJson(
          Map<String, Object?>.from(
            (feed['alerts'] as List).cast<Map<String, dynamic>>().firstWhere(
              (row) => row['event_type'] == 'interaction_rule',
            ),
          ),
        );
        for (final unavailable in [false, true]) {
          final result = await snapshot(
            unavailable: unavailable,
            matches: [(alert: alert, dsldId: '999')],
          );
          expect(result.reviewSignals, hasLength(1));
          expect(
            result.reviewSignals.single.payload,
            isA<RegulatorySafetyPayload>(),
          );
          expect(
            result.intelligence.issues.single.headline,
            contains(alert.body),
          );
          expect(result.intelligence.tier, StackTier.unsafe);
        }
      },
    );
  });

  group('StackIntelligenceEngine.diagnose', () {
    test('an incomplete recall scan prevents an optimized all-clear', () {
      final intelligence = engine.diagnose(
        stackSize: 1,
        safetyReport: const StackSafetyReport(),
        recalledReport: const RecalledIngredientsReport(
          violations: [],
          incomplete: true,
        ),
        synergyReport: emptySynergy,
        qualityScore: 95,
      );

      expect(intelligence.analysisIncomplete, isTrue);
      expect(intelligence.tier, StackTier.incomplete);
      expect(describeStackSummary(intelligence), contains('more information'));
    });

    test('empty stack → tier=incomplete, no issues, all flags false', () {
      const report = StackSafetyReport();

      final intelligence = engine.diagnose(
        stackSize: 0,
        safetyReport: report,
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
      );

      expect(intelligence.tier, StackTier.incomplete);
      expect(intelligence.stackSize, 0);
      expect(intelligence.issues, isEmpty);
      expect(intelligence.hasBannedIngredient, isFalse);
      expect(intelligence.hasRecalledIngredient, isFalse);
      expect(intelligence.hasContraindicatedInteraction, isFalse);
      expect(intelligence.interactionCount, 0);
      expect(intelligence.nutrientWarningCount, 0);
    });

    test('single banned ingredient + clean stack → unsafe', () {
      final recall = RecalledIngredientsReport(
        violations: [
          _violation(productName: 'Banned Product', recallStatus: 'banned'),
        ],
      );

      final intelligence = engine.diagnose(
        stackSize: 5,
        safetyReport: const StackSafetyReport(),
        recalledReport: recall,
        synergyReport: emptySynergy,
        qualityScore: 90,
      );

      expect(intelligence.tier, StackTier.unsafe);
      expect(intelligence.hasBannedIngredient, isTrue);
      expect(intelligence.hasRecalledIngredient, isTrue);
      expect(intelligence.issues, isNotEmpty);
      expect(intelligence.issues.first.headline, contains('Banned Product'));
    });

    test(
      'warning-status recall → unsafe + hasRecalledIngredient (not banned)',
      () {
        final recall = RecalledIngredientsReport(
          violations: [
            _violation(
              productName: 'Watchlist Product',
              recallStatus: 'warning',
              severity: 'major',
            ),
          ],
        );

        final intelligence = engine.diagnose(
          stackSize: 4,
          safetyReport: const StackSafetyReport(),
          recalledReport: recall,
          synergyReport: emptySynergy,
        );

        expect(intelligence.tier, StackTier.unsafe);
        expect(intelligence.hasRecalledIngredient, isTrue);
        expect(intelligence.hasBannedIngredient, isFalse);
      },
    );

    test('contraindicated interaction → unsafe', () {
      final report = StackSafetyReport(
        medicationInteractions: [
          _interaction(id: 'x1', severity: Severity.contraindicated),
        ],
      );

      final intelligence = engine.diagnose(
        stackSize: 3,
        safetyReport: report,
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
      );

      expect(intelligence.tier, StackTier.unsafe);
      expect(intelligence.hasContraindicatedInteraction, isTrue);
      expect(intelligence.interactionCount, 1);
    });

    test('avoid-level interaction → concerning', () {
      final report = StackSafetyReport(
        stackInteractions: [_interaction(id: 's1', severity: Severity.avoid)],
      );

      final intelligence = engine.diagnose(
        stackSize: 4,
        safetyReport: report,
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 95,
      );

      expect(intelligence.tier, StackTier.concerning);
      expect(intelligence.interactionCount, 1);
      expect(intelligence.hasContraindicatedInteraction, isFalse);
    });

    test('medication-profile warning counts as a stack interaction issue', () {
      final report = StackSafetyReport(
        medicationProfileWarnings: [
          _profileWarning(
            id: 'MCR_PREGNANCY_NSAIDS',
            severity: Severity.caution,
          ),
        ],
      );

      final intelligence = engine.diagnose(
        stackSize: 2,
        safetyReport: report,
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 95,
      );

      expect(intelligence.interactionCount, 1);
      expect(intelligence.tier, StackTier.decent);
      final issue = intelligence.issues.single;
      expect(issue.headline, contains('Motrin'));
      expect(issue.headline, contains('Review NSAID use in pregnancy'));
      expect(issue.headline, isNot(contains('20 weeks')));
    });

    test('two nutrients approaching/exceeding UL → concerning', () {
      final report = StackSafetyReport(
        nutrientStatuses: [
          _nutrient(
            id: 'iron',
            tier: NutrientTier.approachingUl,
            warning: 'iron near UL',
          ),
          _nutrient(
            id: 'zinc',
            tier: NutrientTier.exceedsUl,
            warning: 'zinc over UL',
          ),
        ],
      );

      final intelligence = engine.diagnose(
        stackSize: 3,
        safetyReport: report,
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
      );

      expect(intelligence.tier, StackTier.concerning);
      expect(intelligence.nutrientWarningCount, 2);
      expect(
        intelligence.issues.any((i) => i.headline == 'zinc over UL'),
        isTrue,
      );
    });

    test('clean stack with qualityScore 90 → optimized', () {
      final intelligence = engine.diagnose(
        stackSize: 6,
        safetyReport: const StackSafetyReport(),
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 90,
      );

      expect(intelligence.tier, StackTier.optimized);
      expect(intelligence.issues, isEmpty);
      expect(intelligence.interactionCount, 0);
    });

    test('monitor-only interaction caps optimized stack at solid', () {
      final report = StackSafetyReport(
        stackInteractions: [_interaction(id: 'm1', severity: Severity.monitor)],
      );

      final intelligence = engine.diagnoseFromReports(
        stackSize: 2,
        safetyReport: report,
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
      );

      expect(intelligence.qualityScore, 97);
      expect(intelligence.interactionCount, 1);
      expect(intelligence.tier, StackTier.solid);
    });

    test('cumulative dose threshold alert caps clean stack at decent', () {
      final intelligence = engine.diagnose(
        stackSize: 3,
        safetyReport: const StackSafetyReport(),
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 95,
        doseThresholdAlerts: [_doseAlert()],
      );

      expect(intelligence.tier, StackTier.decent);
      expect(intelligence.nutrientWarningCount, 1);
      expect(intelligence.issues.single.severity, Severity.caution);
      expect(intelligence.issues.single.headline, contains('Caffeine'));
      expect(intelligence.issues.single.headline, contains('240 mg'));
    });

    test('avoid dose threshold makes the stack concerning', () {
      final intelligence = engine.diagnose(
        stackSize: 1,
        safetyReport: const StackSafetyReport(),
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 95,
        doseThresholdAlerts: [_doseAlert(clinicalSeverity: Severity.avoid)],
      );

      expect(intelligence.tier, StackTier.concerning);
    });

    test('contraindicated dose threshold makes the stack unsafe', () {
      final intelligence = engine.diagnose(
        stackSize: 1,
        safetyReport: const StackSafetyReport(),
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 95,
        doseThresholdAlerts: [
          _doseAlert(
            clinicalSeverity: Severity.contraindicated,
            consumerDisposition: ConsumerDisposition.block,
          ),
        ],
      );

      expect(intelligence.tier, StackTier.unsafe);
    });

    test('good-to-know dose threshold does not lower a clean tier', () {
      final intelligence = engine.diagnose(
        stackSize: 1,
        safetyReport: const StackSafetyReport(),
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 95,
        doseThresholdAlerts: [
          _doseAlert(consumerDisposition: ConsumerDisposition.goodToKnow),
        ],
      );

      expect(intelligence.tier, StackTier.optimized);
      expect(intelligence.nutrientWarningCount, 0);
    });

    test('clean stack with qualityScore 75 → solid', () {
      final intelligence = engine.diagnose(
        stackSize: 4,
        safetyReport: const StackSafetyReport(),
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 75,
      );

      expect(intelligence.tier, StackTier.solid);
    });

    test(
      'issues sort with recalls before interactions and severity-ordered',
      () {
        final report = StackSafetyReport(
          stackInteractions: [
            _interaction(
              id: 'sx',
              severity: Severity.caution,
              mechanism: 'mid-tier supplement issue',
            ),
          ],
          medicationInteractions: [
            _interaction(
              id: 'mx',
              severity: Severity.avoid,
              mechanism: 'medication conflict',
            ),
          ],
        );
        final recall = RecalledIngredientsReport(
          violations: [
            _violation(productName: 'Tainted', recallStatus: 'banned'),
          ],
        );

        final intelligence = engine.diagnose(
          stackSize: 5,
          safetyReport: report,
          recalledReport: recall,
          synergyReport: emptySynergy,
        );

        // Recall first.
        expect(intelligence.issues.first.headline, contains('Tainted'));
        // Then medication avoid before supplement caution.
        expect(intelligence.issues[1].headline, 'medication conflict');
        expect(intelligence.issues[2].headline, 'mid-tier supplement issue');
      },
    );

    test('food advisory stays contextual — no actionable count, ordered after '
        'real concerns', () {
      final report = StackSafetyReport(
        stackInteractions: [
          _interaction(
            id: 'concern',
            severity: Severity.caution,
            mechanism: 'real concern',
          ),
        ],
        medicationInteractions: [
          _interaction(
            id: 'fa',
            severity: Severity.informational,
            mechanism: 'food note',
            alertStyle: 'food_advisory_note',
          ),
        ],
      );

      final intelligence = engine.diagnose(
        stackSize: 3,
        safetyReport: report,
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
      );

      // The good_to_know food advisory does not inflate the actionable count.
      expect(intelligence.interactionCount, 1);
      // Both surface as issues; the actionable concern leads, advisory follows.
      expect(intelligence.issues.length, 2);
      expect(intelligence.issues.first.headline, 'real concern');
      expect(intelligence.issues[1].headline, 'food note');
    });

    test('suppress + good_to_know signals change neither the actionable count '
        'nor the tier (control comparison)', () {
      final concernOnly = StackSafetyReport(
        stackInteractions: [_interaction(id: 'c', severity: Severity.caution)],
      );
      final withContext = StackSafetyReport(
        stackInteractions: [
          _interaction(id: 'c', severity: Severity.caution),
          _interaction(id: 'safe', severity: Severity.safe), // → suppress
        ],
        medicationInteractions: [
          _interaction(
            id: 'fa',
            severity: Severity.informational,
            alertStyle: 'food_advisory_note', // → good_to_know
          ),
        ],
      );

      final a = engine.diagnose(
        stackSize: 3,
        safetyReport: concernOnly,
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 95,
      );
      final b = engine.diagnose(
        stackSize: 3,
        safetyReport: withContext,
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 95,
      );

      // Adding the safe (suppress) + informational (good_to_know) entries adds
      // nothing to the actionable interaction count or the tier.
      expect(b.interactionCount, a.interactionCount);
      expect(b.interactionCount, 1); // only the caution concern
      expect(b.tier, a.tier);
      expect(b.hasContraindicatedInteraction, isFalse);
    });
  });

  group('StackIntelligenceEngine.diagnoseFromReports', () {
    test('computes the shared quality score before deriving the tier', () {
      final synergy = SynergyReport(
        matches: [
          SynergyMatch(
            clusterId: 'sleep_support',
            clusterName: 'Sleep support',
            matchedIngredients: const ['magnesium', 'l_theanine'],
            mechanism: 'Complementary sleep-support stack.',
            bonusPoints: 8,
            evidenceTier: 'moderate',
            citations: const [],
          ),
        ],
        totalBonusPoints: 8,
      );

      final intelligence = engine.diagnoseFromReports(
        stackSize: 2,
        safetyReport: const StackSafetyReport(),
        recalledReport: emptyRecall,
        synergyReport: synergy,
      );

      expect(intelligence.qualityScore, 100);
      expect(intelligence.tier, StackTier.optimized);
      expect(intelligence.issues, isEmpty);
    });

    test(
      'medication-profile warning flows through to clinician/share diagnosis',
      () {
        // The clinician report + share surfaces build from
        // diagnoseFromReports (asserted structurally in the next test). This
        // proves that exact method carries the medication-profile warning,
        // with its medication-specific context, into the issue list those
        // surfaces render — so a pregnancy-NSAID warning is never silently
        // dropped from a shared clinician summary.
        final report = StackSafetyReport(
          medicationProfileWarnings: [
            _profileWarning(
              id: 'MCR_PREGNANCY_NSAIDS',
              severity: Severity.caution,
            ),
          ],
        );

        final intelligence = engine.diagnoseFromReports(
          stackSize: 2,
          safetyReport: report,
          recalledReport: emptyRecall,
          synergyReport: emptySynergy,
        );

        final issue = intelligence.issues.single;
        expect(issue.headline, contains('Motrin'));
        expect(issue.headline, contains('Review NSAID use in pregnancy'));
      },
    );

    test('stack-health surfaces use one shared diagnosis composition', () {
      for (final path in const [
        'lib/features/home/v2/home_v2_screen.dart',
        'lib/features/stack/v2/stack_v2_screen.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, contains('stackHealthSnapshotProvider'), reason: path);
        expect(source, isNot(contains('summarizeFromReports(')), reason: path);
        expect(source, isNot(contains('orderedSignalsFrom(')), reason: path);
        expect(source, isNot(contains('StackSafetyScorer().compute')));
      }

      final provider = File(
        'lib/features/stack/providers/stack_safety_providers.dart',
      ).readAsStringSync();
      expect(provider, contains('stackHealthSnapshotProvider'));
      expect(provider, contains('summarizeFromReports('));

      final shareButton = File(
        'lib/features/stack/widgets/share_clinician_report_button.dart',
      ).readAsStringSync();
      final shareSheet = File(
        'lib/features/stack/widgets/stack_share_sheet.dart',
      ).readAsStringSync();
      final preview = File(
        'lib/features/stack/widgets/clinician_report_preview_screen.dart',
      ).readAsStringSync();
      final documentProvider = File(
        'lib/services/sharing/clinician_report_document_provider.dart',
      ).readAsStringSync();

      expect(shareButton, contains('showStackShareSheet'));
      expect(shareButton, isNot(contains('diagnoseFromReports(')));
      expect(shareSheet, contains('ClinicianReportPreviewScreen'));
      expect(preview, contains('clinicianReportDocumentProvider'));
      expect(documentProvider, contains('diagnoseFromReports('));
      expect(documentProvider, isNot(contains('StackSafetyScorer().compute')));
    });

    test(
      'shared Stack Health snapshot counts interactions and nutrient signals',
      () {
        final report = StackSafetyReport(
          stackInteractions: [
            _interaction(id: 'one', severity: Severity.caution),
            _interaction(id: 'two', severity: Severity.monitor),
          ],
          nutrientStatuses: [
            const NutrientStatus(
              total: NutrientTotal(
                canonicalId: 'vitamin_d',
                displayName: 'Vitamin D',
                totalAmount: 125,
                unit: 'mcg',
                contributions: [],
              ),
              tier: NutrientTier.exceedsUl,
              ul: 100,
              pctOfUl: 125,
            ),
          ],
        );

        final snapshot = engine.summarizeFromReports(
          stackSize: 2,
          safetyReport: report,
          recalledReport: emptyRecall,
          synergyReport: emptySynergy,
        );

        expect(snapshot.reviewSignals, hasLength(3));
        expect(snapshot.intelligence.interactionCount, 2);
        expect(snapshot.intelligence.nutrientWarningCount, 1);
      },
    );

    test('shared Stack Health snapshot includes a dose-threshold signal', () {
      final snapshot = engine.summarizeFromReports(
        stackSize: 1,
        safetyReport: const StackSafetyReport(),
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        doseThresholdAlerts: [_doseAlert()],
      );

      expect(snapshot.reviewSignals, hasLength(1));
      final signal = snapshot.reviewSignals.single;
      expect(signal.family.name, 'doseThreshold');
      expect(signal.payload.runtimeType.toString(), 'DoseThresholdPayload');
      expect(signal.evaluationStatus, EvaluationStatus.aboveThreshold);
      expect(
        signal.signalIdCanonical,
        'pg_signal:v1:doseThreshold:condition:pregnancy:'
        'caffeine:>=:200:mg',
      );
      expect(snapshot.intelligence.nutrientWarningCount, 1);
    });

    test('incomplete dose threshold maps to amount-unknown evaluation', () {
      final snapshot = engine.summarizeFromReports(
        stackSize: 1,
        safetyReport: const StackSafetyReport(),
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        doseThresholdAlerts: [_doseAlert(isIncomplete: true)],
      );

      expect(snapshot.reviewSignals, hasLength(1));
      expect(
        snapshot.reviewSignals.single.evaluationStatus,
        EvaluationStatus.amountUnknown,
      );
    });

    test(
      'stack-health surfaces pass cumulative dose alerts into diagnosis',
      () {
        for (final path in const [
          'lib/features/stack/providers/stack_safety_providers.dart',
          'lib/services/sharing/clinician_report_document_provider.dart',
        ]) {
          final source = File(path).readAsStringSync();
          expect(
            source,
            contains('stackDoseThresholdAlertsProvider'),
            reason: path,
          );
          expect(source, contains('doseThresholdAlerts:'), reason: path);
        }
      },
    );

    test('incomplete cumulative dose alert uses hedge copy', () {
      final intelligence = engine.diagnose(
        stackSize: 2,
        safetyReport: const StackSafetyReport(),
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 95,
        doseThresholdAlerts: [
          _doseAlert(totalValue: 160, thresholdValue: 200, isIncomplete: true),
        ],
      );

      expect(intelligence.issues, hasLength(1));
      expect(
        intelligence.issues.single.headline,
        contains('could not be fully evaluated'),
      );
      expect(intelligence.issues.single.headline, contains('known subtotal'));
      expect(intelligence.issues.single.headline, contains('160 mg'));
      expect(intelligence.issues.single.headline, contains('threshold 200 mg'));
    });
  });
}
