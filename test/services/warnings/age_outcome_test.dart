import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';
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

void main() {
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
