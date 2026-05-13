// Sprint C (2026-05-13) — unit tests for the two helpers that surface
// the widened banned_substance_detail context fields in the blocked
// product banner.
//
// The helpers are pure (string in, string out, no I/O) so they're
// testable without spinning up Flutter widgets, Drift DBs, or
// Riverpod overrides. The widget side (_BlockedBanner) already
// conditionally renders rows when these helpers return non-null,
// so pinning the helper contract pins the user-visible behavior.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/blocked_banner_context.dart';

void main() {
  group('buildRegulatoryLine', () {
    test('returns "label · Sep 7, 2016" for ISO date + label', () {
      expect(
        buildRegulatoryLine('FDA ban effective', '2016-09-07'),
        'FDA ban effective · Sep 7, 2016',
      );
    });

    test('formats different ISO date correctly', () {
      expect(
        buildRegulatoryLine('Recalled', '2024-12-01'),
        'Recalled · Dec 1, 2024',
      );
    });

    test('returns label alone when date is missing', () {
      expect(
        buildRegulatoryLine('FDA ban effective', null),
        'FDA ban effective',
      );
      expect(
        buildRegulatoryLine('FDA ban effective', ''),
        'FDA ban effective',
      );
      expect(
        buildRegulatoryLine('FDA ban effective', '   '),
        'FDA ban effective',
      );
    });

    test('returns null when label is missing (orphan date suppressed)', () {
      // Per the helper's docstring: a date without a regulatory verb
      // ("2016-09-07") carries no context — better suppressed than
      // shown as a mystery footer.
      expect(buildRegulatoryLine(null, '2016-09-07'), isNull);
      expect(buildRegulatoryLine('', '2016-09-07'), isNull);
      expect(buildRegulatoryLine('   ', '2016-09-07'), isNull);
    });

    test('returns null when both fields are missing', () {
      expect(buildRegulatoryLine(null, null), isNull);
      expect(buildRegulatoryLine('', ''), isNull);
    });

    test('falls back to raw date string when not ISO 8601', () {
      // Defensive: a future pipeline change might emit "Sep 2016" or
      // "2024-Q1" — we still want the user to see the regulator's
      // intent rather than dropping the date silently.
      expect(
        buildRegulatoryLine('FDA ban effective', 'September 2016'),
        'FDA ban effective · September 2016',
      );
    });

    test('trims whitespace from label and date', () {
      expect(
        buildRegulatoryLine('  FDA ban effective  ', '  2016-09-07  '),
        'FDA ban effective · Sep 7, 2016',
      );
    });
  });

  group('contextNoteFor', () {
    test('adulterant_in_supplements → prescription-medication note', () {
      final note = contextNoteFor('adulterant_in_supplements');
      expect(note, isNotNull);
      // Carries the load-bearing reassurance: a clinician-prescribed
      // medication that happens to appear undisclosed in supplements
      // must NOT read as "stop your medication." Pin the phrasing
      // ("the concern is with the supplement, not the prescription")
      // so future copy edits can't accidentally drop the reassurance.
      expect(note, contains('prescription medication'));
      expect(note, contains('not the prescription'));
      expect(note, contains('supplement'));
      // PharmaGuide brand voice — clinical precision, no imperatives.
      // "Discuss with your provider" reads as actionable advice, not
      // alarm. See feedback_copy_voice.md.
      expect(note, contains('Discuss with your provider'));
      expect(note, isNot(contains('Stop ')));
      expect(note, isNot(contains('Avoid')));
      expect(note, isNot(contains('Do not')));
    });

    test('contamination_recall → lot-specific recall note', () {
      final note = contextNoteFor('contamination_recall');
      expect(note, isNotNull);
      // Load-bearing distinction: the recall is LOT-specific, not
      // substance-wide. Users with the same substance in a different
      // (clean) product shouldn't read "Do not use this ingredient."
      // The actionable next step is verifying the lot number.
      expect(note, contains('lot-specific recall'));
      expect(note, contains('not by the substance itself'));
      expect(note, contains('lot number'));
      expect(note, contains('manufacturer or your provider'));
      expect(note, isNot(contains('Stop ')));
      expect(note, isNot(contains('Avoid')));
    });

    test('watchlist → regulatory-monitoring note', () {
      final note = contextNoteFor('watchlist');
      expect(note, isNotNull);
      // PharmaGuide brand voice from pharmaguide.io — clinical
      // precision: "active regulatory monitoring", "documented labeling
      // concerns", "provider input is recommended".
      expect(note, contains('active regulatory monitoring'));
      expect(note, contains('labeling concerns'));
      expect(note, contains('Provider input is recommended'));
      expect(note, isNot(contains('Stop')));
      expect(note, isNot(contains('Avoid')));
    });

    test('export_restricted → region-restriction note', () {
      final note = contextNoteFor('export_restricted');
      expect(note, isNotNull);
      // Names the asymmetry (restricted as a supplement abroad, still
      // legal in US) — the asymmetry is the user-relevant fact.
      expect(note, contains('Restricted'));
      expect(note, contains('remaining legal in the US'));
      expect(note, contains('Provider input is recommended'));
      expect(note, isNot(contains('Stop')));
      expect(note, isNot(contains('Avoid')));
    });

    test('substance → null (no extra row, default tone)', () {
      // "substance" is the dominant case (the molecule itself is
      // controlled). The base BLOCKED banner already conveys "do
      // not use" — no extra context line needed.
      expect(contextNoteFor('substance'), isNull);
    });

    test('null/empty/unknown → null', () {
      expect(contextNoteFor(null), isNull);
      expect(contextNoteFor(''), isNull);
      expect(contextNoteFor('   '), isNull);
      expect(contextNoteFor('unknown_value'), isNull);
      // Future-pipeline-value safety: a new enum value we don't know
      // about yet must NOT crash and must NOT render a broken note.
      expect(contextNoteFor('future_pipeline_addition'), isNull);
    });

    test('case-insensitive matching', () {
      expect(contextNoteFor('SUBSTANCE'), isNull);
      expect(
        contextNoteFor('Adulterant_In_Supplements'),
        equals(contextNoteFor('adulterant_in_supplements')),
      );
      expect(
        contextNoteFor('  WATCHLIST  '),
        equals(contextNoteFor('watchlist')),
      );
    });
  });
}
