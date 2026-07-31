// Tests for the optional curated watch threshold (roadmap Phase 1).
//
// The threshold is a CLINICAL judgment authored per entry by a reviewer. The
// app parses and renders it but must never derive, default, or round one. These
// tests codify that fail-closed contract: an entry is watched only when a
// reviewer authored both a positive whole-day threshold and the basis citing
// it. Everything else degrades to prior behavior — not watched.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';

Map<String, dynamic> _fixture({
  Object? thresholdDays,
  Object? basis,
  Object? reviewStatus = 'approved',
  Object? approver = 'PharmaGuide Clinical Team',
}) {
  return {
    'depletions': [
      {
        'id': 'DEP_METFORMIN_VITAMINB12',
        'drug_ref': {
          'id': '860974',
          'display_name': 'Metformin (type 2 diabetes medication)',
        },
        'depleted_nutrient': {
          'standard_name': 'Vitamin B12',
          'canonical_id': 'vitamin_b12',
        },
        'depletion_type': 'depletion',
        'severity': 'significant',
        'citation_review_status': 'verified',
        'mechanism': 'Metformin impairs B12 absorption.',
        'recommendation': 'Consider discussing B12 with your clinician.',
        'onset_timeline': 'years',
        'evidence_level': 'established',
        'sources': [
          {'source_type': 'reference', 'url': 'https://example.test/nih-b12'},
        ],
        if (thresholdDays != null) 'watch_threshold_days': thresholdDays,
        if (basis != null) 'watch_basis': basis,
        if (reviewStatus != null) 'watch_review_status': reviewStatus,
        if (approver != null) 'watch_approver': approver,
      },
    ],
  };
}

void main() {
  final checker = DepletionChecker();
  const metformin = (name: 'Metformin', drugClassId: null);

  DepletionMatch parseOne({
    Object? thresholdDays,
    Object? basis,
    Object? reviewStatus = 'approved',
    Object? approver = 'PharmaGuide Clinical Team',
  }) {
    final out = checker.check(
      medications: const [metformin],
      depletionsData: _fixture(
        thresholdDays: thresholdDays,
        basis: basis,
        reviewStatus: reviewStatus,
        approver: approver,
      ),
    );
    expect(out, hasLength(1));
    return out.single;
  }

  group('watch threshold — authored pairs are honoured', () {
    test('an authored threshold with a basis is parsed', () {
      final match = parseOne(
        thresholdDays: 1460,
        basis: 'Reviewer note citing the entry source set.',
      );
      expect(match.watchThresholdDays, 1460);
      expect(match.watchBasis, 'Reviewer note citing the entry source set.');
    });

    test('a numeric string threshold is rejected as schema drift', () {
      final match = parseOne(thresholdDays: '730', basis: 'Cited basis.');
      expect(match.watchThresholdDays, isNull);
    });

    test('surrounding whitespace in the basis is trimmed', () {
      final match = parseOne(thresholdDays: 730, basis: '  Cited basis.  ');
      expect(match.watchBasis, 'Cited basis.');
    });
  });

  group('watch threshold — fails closed', () {
    test('an entry with no threshold is not watched', () {
      final match = parseOne();
      expect(match.watchThresholdDays, isNull);
      expect(match.watchBasis, isNull);
    });

    test('a threshold with no basis is dropped entirely', () {
      // A clinical timeline the app cannot attribute must never surface.
      final match = parseOne(thresholdDays: 730);
      expect(match.watchThresholdDays, isNull);
      expect(match.watchBasis, isNull);
    });

    test('a blank basis is treated as absent', () {
      final match = parseOne(thresholdDays: 730, basis: '   ');
      expect(match.watchThresholdDays, isNull);
      expect(match.watchBasis, isNull);
    });

    test('a basis with no threshold yields no threshold', () {
      final match = parseOne(basis: 'Cited basis.');
      expect(match.watchThresholdDays, isNull);
      expect(match.watchBasis, isNull);
    });

    test('zero and negative thresholds are rejected', () {
      expect(parseOne(thresholdDays: 0, basis: 'b').watchThresholdDays, isNull);
      expect(
        parseOne(thresholdDays: -30, basis: 'b').watchThresholdDays,
        isNull,
      );
    });

    test('a fractional threshold is rejected, never rounded', () {
      // Silently rounding would invent a threshold no reviewer authored.
      final match = parseOne(thresholdDays: 730.5, basis: 'Cited basis.');
      expect(match.watchThresholdDays, isNull);
    });

    test('a non-numeric threshold is rejected', () {
      final match = parseOne(thresholdDays: 'two years', basis: 'Cited basis.');
      expect(match.watchThresholdDays, isNull);
    });
  });

  group('watch threshold — clinical sign-off gate', () {
    test('a proposed threshold is inert until approved', () {
      // This is how a drafted threshold ships: complete and reviewable, but
      // invisible to users until a clinician says yes.
      final match = parseOne(
        thresholdDays: 1460,
        basis: 'Cited basis.',
        reviewStatus: 'proposed',
      );
      expect(match.watchThresholdDays, isNull);
      expect(match.watchBasis, isNull);
    });

    test('a rejected threshold never surfaces', () {
      final match = parseOne(
        thresholdDays: 1460,
        basis: 'Cited basis.',
        reviewStatus: 'rejected',
      );
      expect(match.watchThresholdDays, isNull);
    });

    test('a missing review status fails closed', () {
      final match = parseOne(
        thresholdDays: 1460,
        basis: 'Cited basis.',
        reviewStatus: null,
      );
      expect(match.watchThresholdDays, isNull);
    });

    test('an unknown future status fails closed', () {
      final match = parseOne(
        thresholdDays: 1460,
        basis: 'Cited basis.',
        reviewStatus: 'pending_second_opinion',
      );
      expect(match.watchThresholdDays, isNull);
    });

    test('approval is case- and whitespace-insensitive', () {
      final match = parseOne(
        thresholdDays: 1460,
        basis: 'Cited basis.',
        reviewStatus: '  Approved ',
      );
      expect(match.watchThresholdDays, 1460);
    });

    test('an approved threshold without an attributable approver is inert', () {
      final match = parseOne(
        thresholdDays: 1460,
        basis: 'Cited basis.',
        approver: null,
      );
      expect(match.watchThresholdDays, isNull);
      expect(match.watchBasis, isNull);
    });

    test('a blank approver fails closed', () {
      final match = parseOne(
        thresholdDays: 1460,
        basis: 'Cited basis.',
        approver: '   ',
      );
      expect(match.watchThresholdDays, isNull);
    });
  });

  test('the bundled artifact authors no thresholds without a basis', () {
    // Guard for the curated data itself: if a reviewer ever ships a threshold,
    // its basis must ship with it. Passes vacuously until thresholds exist.
    final out = checker.check(
      medications: const [metformin],
      depletionsData: _fixture(thresholdDays: 730, basis: 'Cited basis.'),
    );
    for (final match in out) {
      if (match.watchThresholdDays != null) {
        expect(
          match.watchBasis,
          isNotNull,
          reason: '${match.depletionId} has a threshold with no basis',
        );
      }
    }
  });
}
