// The app must fail closed on an unreviewed research claim, on its own.
//
// The pipeline used to emit `formula_only` before it consulted the clinician
// sign-off, so a formula-level match rendered an affirmative badge with no
// review behind it. The producer is fixed, but a bundle built before that fix
// is still installable, and a stale artifact must not be able to talk the app
// into an affirmative claim. The reader therefore re-checks `review_status`
// itself rather than trusting `research_match_status`.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/probiotic_section.dart';
import 'package:pharmaguide/core/components/pg_probiotic_section.dart';

Map<String, dynamic> _strain({
  required String matchStatus,
  String? reviewStatus,
  bool blocked = false,
}) => <String, dynamic>{
  'strain_id': 'STRAIN_TEST',
  'research_match_status': matchStatus,
  if (reviewStatus != null) 'review_status': reviewStatus,
  'is_blocked': blocked,
  'source_urls': const ['https://pubmed.ncbi.nlm.nih.gov/12345678/'],
};

const _affirmative = {
  PGProbioticResearchStatus.exactStrain,
  PGProbioticResearchStatus.speciesLevel,
  PGProbioticResearchStatus.formulaOnly,
};

void main() {
  group('stale artifacts cannot claim reviewed research', () {
    for (final status in ['formula_only', 'exact_strain', 'species_level']) {
      for (final review in <String?>[null, 'pending_review', '', 'unknown']) {
        test('$status with review=${review ?? "absent"} shows no badge', () {
          final resolved = probioticResearchStatusForTest(
            _strain(matchStatus: status, reviewStatus: review),
          );
          expect(
            _affirmative.contains(resolved),
            isFalse,
            reason:
                'a $status row without clinician_verified must not present as '
                'affirmative; got $resolved',
          );
          expect(resolved, PGProbioticResearchStatus.none);
        });
      }
    }
  });

  group('reviewed rows keep their badge', () {
    const expected = {
      'exact_strain': PGProbioticResearchStatus.exactStrain,
      'species_level': PGProbioticResearchStatus.speciesLevel,
      'formula_only': PGProbioticResearchStatus.formulaOnly,
    };
    expected.forEach((status, badge) {
      test('$status with clinician_verified renders $badge', () {
        expect(
          probioticResearchStatusForTest(
            _strain(matchStatus: status, reviewStatus: 'clinician_verified'),
          ),
          badge,
        );
      });
    });
  });

  group('non-affirmative and blocked states', () {
    test('rejected never renders a badge even when verified', () {
      expect(
        probioticResearchStatusForTest(
          _strain(matchStatus: 'rejected', reviewStatus: 'clinician_verified'),
        ),
        PGProbioticResearchStatus.none,
      );
    });

    test('is_blocked wins over a verified affirmative status', () {
      expect(
        probioticResearchStatusForTest(
          _strain(
            matchStatus: 'exact_strain',
            reviewStatus: 'clinician_verified',
            blocked: true,
          ),
        ),
        PGProbioticResearchStatus.none,
      );
    });

    test('pending_review renders no badge', () {
      expect(
        probioticResearchStatusForTest(
          _strain(matchStatus: 'pending_review', reviewStatus: 'clinician_verified'),
        ),
        PGProbioticResearchStatus.none,
      );
    });

    test('a null row renders no badge', () {
      expect(
        probioticResearchStatusForTest(null),
        PGProbioticResearchStatus.none,
      );
    });
  });
}
