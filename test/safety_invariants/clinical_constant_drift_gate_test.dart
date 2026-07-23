// Clinical-constant drift gate (the "no clinical policy authored in Dart" rule).
//
// One-brain principle: clinical thresholds/bands are pipeline-owned. The app
// EXECUTES them, it does not AUTHOR them. This gate scans the clinical service
// dirs for hardcoded classification-band literals (a comparison against a
// multi-digit `.0` float, e.g. `>= 100.0`) and fails if a NEW one appears.
//
// Two files carry classification-band literals today (see _allowlist for the
// breakdown: app-owned UI tiers vs the parity-locked B7 clinical value). They
// are frozen on the allowlist below: a new value, or a band literal in any
// other file, trips the gate.
//
// Backstop, not the primary guard: the primary is "enforce by construction"
// (bands come from a typed contract object), which lands with the migration
// slice. Until then this scanner blocks new drift.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A clinical classification band: a comparison operator against a multi-digit
/// float ending in `.0` (`>= 100.0`, `< 80.0`, `>= 150.0`). Incidental numbers
/// — `length >= 3`, `* 1000`, index `> 0`, single-digit ints — do NOT match.
final RegExp _clinicalBandPattern = RegExp(r'[<>]=?\s*\d{2,3}\.0(?![0-9])');

/// Files permitted to contain classification-band literals today, mapped to the
/// exact normalized literals they may contain. Two categories, both intentional:
///   - stack_ul_checker.dart (50/80/100/200): app-owned UI classification tiers
///     (intake-adequacy / UL display bands). NOT clinical policy — the pipeline
///     owns the UL verdict via `over_ul`, which the app defers to. No pipeline
///     equivalent exists to migrate to; these legitimately live in the app.
///   - stack_nutrient_aggregator.dart (150.0): the B7 UL-exceedance fallback.
///     This IS pipeline clinical policy (mirrors b7_ul_pct_threshold) and is
///     LOCKED to the pipeline value by clinical_threshold_parity_test.dart, so
///     it cannot silently drift.
///
/// Known limitations (acceptable — the gate targets the dominant accidental-drift
/// pattern: a dev copying an inline `>= X.0` comparison to add another band):
///   1. Presence-keyed, not count-keyed — a new occurrence of an already-listed
///      literal in the SAME file is not caught. New values and new files ARE.
///   2. Comparison-anchored — a threshold hidden in a named constant
///      (`const kApproachingUlPct = 80.0;`) is not caught. None exist today.
///   3. `.0`-float-anchored — an integer band (`>= 80`) is not caught, so that
///      count comparisons (`labels.length >= 20`) don't false-positive.
const Map<String, Set<String>> _allowlist = {
  'stack_ul_checker.dart': {'>=200.0', '>=100.0', '>=80.0', '>=50.0'},
  'stack_nutrient_aggregator.dart': {'>=150.0'},
};

const List<String> _scanDirs = [
  'lib/services/stack',
  'lib/services/warnings',
];

/// Return `<file>: <literal>` violations for band literals in [source] not
/// permitted for [fileName] by [allowlist]. Inline/line comments are ignored.
List<String> scanForClinicalBands(
  String fileName,
  String source, {
  Map<String, Set<String>> allowlist = _allowlist,
}) {
  final permitted = allowlist[fileName] ?? const <String>{};
  final violations = <String>[];
  for (final rawLine in source.split('\n')) {
    // Strip inline/line comments so band literals in prose don't false-positive.
    final commentIdx = rawLine.indexOf('//');
    final code = commentIdx >= 0 ? rawLine.substring(0, commentIdx) : rawLine;
    for (final m in _clinicalBandPattern.allMatches(code)) {
      final literal = m.group(0)!.replaceAll(RegExp(r'\s+'), '');
      if (!permitted.contains(literal)) {
        violations.add('$fileName: $literal   ->  ${rawLine.trim()}');
      }
    }
  }
  return violations;
}

void main() {
  group('clinical-constant drift gate', () {
    test('flags a NEW clinical band literal not on the allowlist', () {
      final v = scanForClinicalBands(
        'some_new_file.dart',
        'if (pctOfUl >= 999.0) return NutrientTier.exceedsUl;',
      );
      expect(
        v,
        isNotEmpty,
        reason: 'a >= 999.0 band in an unlisted file must be flagged',
      );
    });

    test('ignores incidental non-band numbers', () {
      const incidental = '''
        const pageSize = 20;
        if (labels.length >= 3) break;
        final x = thresholdMg * 1000;
        if (count > 0) return;
      ''';
      expect(
        scanForClinicalBands('whatever.dart', incidental),
        isEmpty,
        reason: 'single-digit ints, *1000 and index guards are not bands',
      );
    });

    test('respects the allowlist for known files', () {
      expect(
        scanForClinicalBands(
          'stack_ul_checker.dart',
          'if (pctOfUl >= 100.0) return NutrientTier.exceedsUl;',
        ),
        isEmpty,
        reason: '>=100.0 is allowlisted for stack_ul_checker.dart',
      );
    });

    test('no unallowlisted clinical band literals in the scanned dirs', () {
      final violations = <String>[];
      for (final dir in _scanDirs) {
        final d = Directory(dir);
        if (!d.existsSync()) continue;
        for (final entity in d.listSync(recursive: true)) {
          if (entity is File && entity.path.endsWith('.dart')) {
            final fileName = entity.uri.pathSegments.last;
            violations.addAll(
              scanForClinicalBands(fileName, entity.readAsStringSync()),
            );
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'New clinical-policy constant(s) hardcoded in Dart. Clinical '
            'thresholds must come from the shipped contract, not Dart. If this '
            'is a genuinely new pipeline-owned band, add it to _allowlist AND '
            'file a migration task:\n  ${violations.join('\n  ')}',
      );
    });
  });
}
