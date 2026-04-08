import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/stack/stack_interaction_checker.dart';

void main() {
  late StackInteractionChecker checker;
  setUp(() => checker = StackInteractionChecker());

  group('StackInteractionChecker', () {
    test('detects stimulant-sedative antagonism', () {
      final results = checker.checkSafety(
        newProductFingerprint: {'nutrients': {}},
        stackFingerprints: [
          {'nutrients': {}}
        ],
        newContainsStimulants: true,
        newContainsSedatives: false,
        newContainsBloodThinners: false,
        stackContainsStimulants: [false],
        stackContainsSedatives: [true],
        stackContainsBloodThinners: [false],
        stackProductNames: ['Melatonin Complex'],
        newProductName: 'Caffeine Pills',
      );
      expect(results, hasLength(1));
      expect(results.first.severity, Severity.caution);
      expect(results.first.mechanism, contains('stimulants and sedatives'));
    });

    test('detects blood thinner stacking', () {
      final results = checker.checkSafety(
        newProductFingerprint: {'nutrients': {}},
        stackFingerprints: [
          {'nutrients': {}}
        ],
        newContainsStimulants: false,
        newContainsSedatives: false,
        newContainsBloodThinners: true,
        stackContainsStimulants: [false],
        stackContainsSedatives: [false],
        stackContainsBloodThinners: [true],
        stackProductNames: ['Fish Oil'],
        newProductName: 'Ginkgo Extract',
      );
      expect(results, hasLength(1));
      expect(results.first.severity, Severity.avoid);
    });

    test('detects duplicate nutrients', () {
      final results = checker.checkSafety(
        newProductFingerprint: {
          'nutrients': {'vitamin_d': {}, 'magnesium': {}, 'zinc': {}}
        },
        stackFingerprints: [
          {
            'nutrients': {
              'vitamin_d': {},
              'magnesium': {},
              'zinc': {},
              'calcium': {}
            }
          }
        ],
        newContainsStimulants: false,
        newContainsSedatives: false,
        newContainsBloodThinners: false,
        stackContainsStimulants: [false],
        stackContainsSedatives: [false],
        stackContainsBloodThinners: [false],
        stackProductNames: ['Multivitamin'],
        newProductName: 'Mineral Complex',
      );
      expect(results, hasLength(1));
      expect(results.first.severity, Severity.monitor);
      expect(results.first.mechanism, contains('3 overlapping'));
    });

    test('returns empty for safe addition', () {
      final results = checker.checkSafety(
        newProductFingerprint: {
          'nutrients': {'vitamin_c': {}}
        },
        stackFingerprints: [
          {
            'nutrients': {'vitamin_d': {}}
          }
        ],
        newContainsStimulants: false,
        newContainsSedatives: false,
        newContainsBloodThinners: false,
        stackContainsStimulants: [false],
        stackContainsSedatives: [false],
        stackContainsBloodThinners: [false],
        stackProductNames: ['Vitamin D'],
        newProductName: 'Vitamin C',
      );
      expect(results, isEmpty);
    });
  });
}
