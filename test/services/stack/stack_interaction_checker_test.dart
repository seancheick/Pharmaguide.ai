import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/stack/stack_interaction_checker.dart';

void main() {
  late StackInteractionChecker checker;
  setUp(() => checker = StackInteractionChecker());

  // Shared empty map — keeps inner fingerprint typing explicit and
  // avoids `inference_failure_on_collection_literal` warnings.
  const Map<String, dynamic> emptyNutrients = <String, dynamic>{};

  group('StackInteractionChecker', () {
    test('detects stimulant-sedative antagonism', () {
      final results = checker.checkSafety(
        newProductFingerprint: const <String, dynamic>{
          'nutrients': emptyNutrients,
        },
        stackFingerprints: const <Map<String, dynamic>>[
          <String, dynamic>{'nutrients': emptyNutrients},
        ],
        newContainsStimulants: true,
        newContainsSedatives: false,
        newContainsBloodThinners: false,
        stackContainsStimulants: const [false],
        stackContainsSedatives: const [true],
        stackContainsBloodThinners: const [false],
        stackProductNames: const ['Melatonin Complex'],
        newProductName: 'Caffeine Pills',
      );
      expect(results, hasLength(1));
      expect(results.first.severity, Severity.caution);
      expect(results.first.mechanism, contains('stimulants and sedatives'));
    });

    test('detects blood thinner stacking', () {
      final results = checker.checkSafety(
        newProductFingerprint: const <String, dynamic>{
          'nutrients': emptyNutrients,
        },
        stackFingerprints: const <Map<String, dynamic>>[
          <String, dynamic>{'nutrients': emptyNutrients},
        ],
        newContainsStimulants: false,
        newContainsSedatives: false,
        newContainsBloodThinners: true,
        stackContainsStimulants: const [false],
        stackContainsSedatives: const [false],
        stackContainsBloodThinners: const [true],
        stackProductNames: const ['Fish Oil'],
        newProductName: 'Ginkgo Extract',
      );
      expect(results, hasLength(1));
      expect(results.first.severity, Severity.avoid);
    });

    test('detects duplicate nutrients', () {
      final results = checker.checkSafety(
        newProductFingerprint: const <String, dynamic>{
          'nutrients': <String, dynamic>{
            'vitamin_d': emptyNutrients,
            'magnesium': emptyNutrients,
            'zinc': emptyNutrients,
          },
        },
        stackFingerprints: const <Map<String, dynamic>>[
          <String, dynamic>{
            'nutrients': <String, dynamic>{
              'vitamin_d': emptyNutrients,
              'magnesium': emptyNutrients,
              'zinc': emptyNutrients,
              'calcium': emptyNutrients,
            },
          },
        ],
        newContainsStimulants: false,
        newContainsSedatives: false,
        newContainsBloodThinners: false,
        stackContainsStimulants: const [false],
        stackContainsSedatives: const [false],
        stackContainsBloodThinners: const [false],
        stackProductNames: const ['Multivitamin'],
        newProductName: 'Mineral Complex',
      );
      expect(results, hasLength(1));
      expect(results.first.severity, Severity.monitor);
      expect(results.first.mechanism, contains('3 overlapping'));
    });

    test('returns empty for safe addition', () {
      final results = checker.checkSafety(
        newProductFingerprint: const <String, dynamic>{
          'nutrients': <String, dynamic>{'vitamin_c': emptyNutrients},
        },
        stackFingerprints: const <Map<String, dynamic>>[
          <String, dynamic>{
            'nutrients': <String, dynamic>{'vitamin_d': emptyNutrients},
          },
        ],
        newContainsStimulants: false,
        newContainsSedatives: false,
        newContainsBloodThinners: false,
        stackContainsStimulants: const [false],
        stackContainsSedatives: const [false],
        stackContainsBloodThinners: const [false],
        stackProductNames: const ['Vitamin D'],
        newProductName: 'Vitamin C',
      );
      expect(results, isEmpty);
    });
  });
}
