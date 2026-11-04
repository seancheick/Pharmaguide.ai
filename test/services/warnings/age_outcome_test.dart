import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2a_goal_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart';
import 'package:pharmaguide/services/fit_score/fit_score_service.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

/// Real pipeline output: 211459 (vitamin E, 670 to 900 mg) and 4340 (vitamin A,
/// 10,000 IU retinyl palmitate) for a pregnant person.
final _real =
    jsonDecode(
          File(
            'test/fixtures/age_outcomes/real_warnings_211459_4340.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

InteractionWarning _warning(String id) =>
    InteractionWarning.fromJson(_real[id] as Map<String, dynamic>);

List<InteractionWarning> _page(String id, String? ageBracket) =>
    composeGuardedWarnings(
      detailBlob: {
        'warnings': [_real[id]],
      },
      personalizedWarnings: const [],
      userConditions: const {'pregnancy'},
      userDrugClasses: const {},
      userProfileFlags: const {'pregnant'},
      ageBracket: ageBracket,
    );

const _ageHeadline = 'Limit depends on age';
const _isAbove =
    'This amount is above the upper limit for ages 14\u201318 but not for '
    'adults. Add your age range to your profile for an answer that fits you.';
const _couldBe =
    'This amount could be above the upper limit for ages 14\u201318 but is below '
    'the limit for adults. Add your age range to your profile for an answer '
    'that fits you.';

void main() {
  test('malformed age outcome preserves the base block', () {
    for (final outcome in <Map<String, dynamic>>[
      {},
      {'consumer_disposition': 'unknown'},
    ]) {
      final warning = InteractionWarning.fromJson({
        'severity': 'avoid',
        'dose_decision': {
          'consumer_disposition': 'block',
          'age_outcomes': {'19+': outcome},
        },
      });
      expect(warning.resolvedForAge('31-50'), same(warning));
    }
  });

  test('Fit Score applies the same age outcome as the warning card', () {
    final service = FitScoreService(
      e1: E1DosageCalculator(const {}),
      e2a: E2aGoalCalculator(const {}),
      e2b: E2bAgeCalculator(const {}),
    );
    String? severity(String age) => service
        .calculate(
          nutrients: const [],
          productClusters: const [],
          interactionSummary: const {
            'condition_summary': {
              'pregnancy': {'highest_severity': 'caution'},
            },
          },
          ageBracket: age,
          sex: 'Female',
          userConditions: const ['pregnancy'],
          userProfileFlags: const {'pregnant'},
          warnings: [_warning('4340')],
        )
        .maxRelevantSeverity;

    expect(severity('14-18'), Severity.contraindicated.name);
    expect(severity('31-50'), isNull);
    expect(severity('Prefer not to say'), Severity.caution.name);
  });

  group('resolvedForAge', () {
    test('14-18 reads the teen outcome, severity and card', () {
      final teen = _warning('4340').resolvedForAge('14-18');
      expect(teen.severity, Severity.contraindicated);
      expect(teen.doseDecision?.evaluationStatus, 'above_threshold');
      expect(teen.doseDecision?.consumerDisposition, 'block');
      expect(teen.doseDecision?.decisionRule?.threshold, 2800);
    });

    test('every adult bracket reads the 19+ outcome', () {
      for (final bracket in const ['19-30', '31-50', '51-70', '71+']) {
        final adult = _warning('4340').resolvedForAge(bracket);
        expect(adult.severity, Severity.caution, reason: bracket);
        expect(adult.doseDecision?.evaluationStatus, 'below_threshold');
        expect(adult.doseDecision?.consumerDisposition, 'suppress');
        expect(adult.doseDecision?.decisionRule?.threshold, 10000);
      }
    });

    test('unknown or unrecognized age stays the review', () {
      for (final bracket in const [null, '', 'teen', '13-']) {
        final review = _warning('4340').resolvedForAge(bracket);
        expect(review.doseDecision?.evaluationStatus, 'age_dependent');
        expect(review.doseDecision?.consumerDisposition, 'review');
        expect(review.severity, Severity.caution);
      }
    });

    test('no stated age reads the age card, never an adult answer', () {
      for (final bracket in const [
        null,
        '',
        'teen',
        'adult',
        '19+',
        'Prefer not to say',
      ]) {
        final review = _warning('4340').resolvedForAge(bracket);
        expect(review.alertHeadline, _ageHeadline, reason: '$bracket');
        expect(review.alertBody, _isAbove, reason: '$bracket');
        expect(review.doseDecision?.evaluationStatus, 'age_dependent');
        final adult = _warning('4340').resolvedForAge('31-50');
        expect(adult.alertBody, isNot(review.alertBody));
        expect(adult.doseDecision?.evaluationStatus, 'below_threshold');
      }
    });

    test('a measured amount says is above, a bound says could be', () {
      expect(_warning('4340').alertBody, _isAbove);
      expect(_warning('211459').alertBody, _couldBe);
      expect(_warning('211459').alertHeadline, _ageHeadline);
    });

    test('a stated age never keeps the age card', () {
      for (final id in const ['4340', '211459']) {
        for (final bracket in const ['14-18', '19-30', '71+']) {
          final card = _warning(id).resolvedForAge(bracket);
          expect(
            card.alertHeadline,
            isNot(_ageHeadline),
            reason: '$id $bracket',
          );
          expect(card.alertBody, isNot(contains('Add your age range')));
        }
      }
    });

    test('a warning with no age outcomes is returned unchanged', () {
      final plain = InteractionWarning.fromJson(const {
        'severity': 'caution',
        'title': 'x',
      });
      expect(identical(plain.resolvedForAge('14-18'), plain), isTrue);
    });

    test('malformed age outcomes never throw and read as no outcomes', () {
      Map<String, dynamic> withOutcomes(Object? outcomes) => {
        'severity': 'caution',
        'title': 'x',
        'dose_decision': {
          'evaluation_status': 'age_dependent',
          'consumer_disposition': 'review',
          'age_outcomes': outcomes,
        },
      };
      for (final outcomes in <Object?>[
        null,
        'x',
        3,
        const <dynamic>[],
        const {'14-18': 3},
        const {'19+': null},
      ]) {
        final warning = InteractionWarning.fromJson(withOutcomes(outcomes));
        expect(
          warning.resolvedForAge('14-18').doseDecision?.consumerDisposition,
          'review',
        );
        expect(warning.resolvedForAge('19-30').severity, Severity.caution);
      }
    });

    test('an outcome with no severity keeps the warning severity', () {
      final warning = InteractionWarning.fromJson(const {
        'severity': 'caution',
        'title': 'x',
        'dose_decision': {
          'evaluation_status': 'age_dependent',
          'age_outcomes': {
            '14-18': {'evaluation_status': 'above_threshold'},
          },
        },
      });
      expect(warning.resolvedForAge('14-18').severity, Severity.caution);
    });
  });

  group('product page', () {
    test('a teenager gets the hard card', () {
      final [card] = _page('4340', '14-18');
      expect(card.severity, Severity.contraindicated);
      expect(card.doseDecision?.consumerDisposition, 'block');
    });

    test('an adult within the limit gets no over-limit card', () {
      expect(_page('4340', '31-50'), isEmpty);
    });

    test('unknown age gets a review, not a clearance or an adult excess', () {
      final [card] = _page('4340', null);
      expect(card.severity, Severity.caution);
      expect(card.doseDecision?.consumerDisposition, 'review');
    });

    test('unknown age shows the approved words on the page', () {
      for (final bracket in const [null, 'teen']) {
        final [card] = _page('211459', bracket);
        expect(card.displayHeadline, _ageHeadline);
        expect(card.displayBody, _couldBe);
      }
    });

    test('E2: 900 mg is a teen review and no adult exceedance', () {
      final [teen] = _page('211459', '14-18');
      expect(teen.doseDecision?.evaluationStatus, 'form_unknown');
      expect(teen.doseDecision?.consumerDisposition, 'review');
      expect(teen.severity, isNot(Severity.avoid));
      expect(_page('211459', '19-30'), isEmpty);
    });
  });

  group('Stack dose evaluator', () {
    double? thresholdFor(String? ageBracket) =>
        stackDoseThresholdRulesFromWarnings([
          _warning('4340').resolvedForAge(ageBracket),
        ]).single.thresholdValue;

    test('each age judges a Stack total by its own limit', () {
      expect(thresholdFor('14-18'), 2800);
      expect(thresholdFor('19-30'), 10000);
    });

    test('unknown age keeps the total unresolved, never cleared', () {
      final rule = stackDoseThresholdRulesFromWarnings([
        _warning('4340').resolvedForAge(null),
      ]).single;
      expect(rule.amountUnresolved, isTrue);
    });
  });

  group('unread check', () {
    bool unread(String? ageBracket, {required bool cardsShown}) =>
        hasUnreadDoseRule(
          [_warning('4340').resolvedForAge(ageBracket)],
          userConditions: const {'pregnancy'},
          userDrugClasses: const {},
          userProfileFlags: const {'pregnant'},
          cardsShown: cardsShown,
        );

    test('unknown age is unread on Stack, where no card is shown', () {
      expect(unread(null, cardsShown: false), isTrue);
      expect(unread(null, cardsShown: true), isFalse);
    });

    test('a known age was read', () {
      expect(unread('14-18', cardsShown: false), isFalse);
      expect(unread('19-30', cardsShown: false), isFalse);
    });
  });
}
