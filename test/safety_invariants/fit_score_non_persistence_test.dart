// Safety invariant: FitScore is never persisted.
//
// CLAUDE.md: "FitScore is NEVER persisted — computed fresh from current
// profile every time."
//
// Persisting it would silently surface stale fits whenever the user
// changes their profile (goals, conditions, age, drug classes). The
// existing provider at
//   lib/features/product_detail/providers/fit_score_provider.dart
// uses FutureProvider.family.autoDispose + watches profileProvider, so
// any profile change auto-invalidates.
//
// This test enforces the rule statically — it does not depend on
// runtime behavior of the provider system, only on the shape of the
// source files. A regression that adds a Drift column, a
// shared_preferences key, or a keepAlive modifier will fail this test
// before the bad code can run in production.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fitScoreProviderPath =
    'lib/features/product_detail/providers/fit_score_provider.dart';

// Locations in `lib/` where the word `fit_score` (lower-snake) is
// allowed to appear. Anywhere else, it's a likely persistence leak.
const _allowedFitScoreReferencesIn = <String>[
  // Service + result types — they're the legitimate compute path.
  'lib/services/fit_score/',
  'lib/core/models/fit_score_result.dart',
  // Provider file — the explicit non-persistence contract.
  'lib/features/product_detail/providers/fit_score_provider.dart',
];

void main() {
  group('Safety invariant: FitScore is never persisted', () {
    test('no Drift table declares a fit_score column', () {
      final tablesDir = Directory('lib/data/database/tables');
      if (!tablesDir.existsSync()) {
        // Layout changed — fail loudly so we update this test.
        fail(
          'lib/data/database/tables/ does not exist. If the database '
          'tables moved, update this test to point at the new path '
          'before disabling it.',
        );
      }

      final offenders = <String>[];

      for (final entity in tablesDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('.g.dart')) continue;
        if (entity.path.endsWith('.drift.dart')) continue;

        final source = entity.readAsStringSync();
        // Drift column declarations are `RealColumn get foo => ...`
        // (or IntColumn / TextColumn). We look for column getters
        // whose name matches fit_score / fitScore.
        final columnRegex = RegExp(
          r'(?:Real|Int|Text|Bool|Date|DateTime)Column\s+get\s+(\w+)',
        );
        for (final match in columnRegex.allMatches(source)) {
          final name = match.group(1)!.toLowerCase();
          if (name.contains('fitscore') ||
              name.contains('fit_score') ||
              name == 'fit') {
            offenders.add('${entity.path}: column "$name"');
          }
        }

        // Also scan @DataClassName / @TableIndex annotations and raw
        // SQL strings.
        if (source.toLowerCase().contains('fit_score')) {
          // Whitelist nothing inside a Drift tables file.
          offenders.add(
            '${entity.path}: source contains "fit_score" literal',
          );
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'FitScore must never be persisted to a database. Found:\n'
            '${offenders.join('\n')}\n\n'
            'Remove the column. FitScore is computed fresh from the '
            'current profile on every read — see CLAUDE.md.',
      );
    });

    test('no shared_preferences key looks like a FitScore cache', () {
      final offenders = <String>[];
      final libDir = Directory('lib');

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('.g.dart')) continue;

        final source = entity.readAsStringSync();
        if (!source.contains('SharedPreferences') &&
            !source.contains('shared_preferences')) {
          continue;
        }

        // Look for getString/setString/getDouble/etc. with keys whose
        // content references fit score.
        final keyRegex = RegExp(
          r'''(?:setString|setDouble|setInt|setBool|getString|getDouble|getInt|getBool)\s*\(\s*['"]([^'"]+)['"]''',
        );
        for (final match in keyRegex.allMatches(source)) {
          final key = match.group(1)!.toLowerCase();
          if (key.contains('fit_score') || key.contains('fitscore')) {
            offenders.add('${entity.path}: shared_preferences key "$key"');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'FitScore must not be cached in shared_preferences. Found:\n'
            '${offenders.join('\n')}',
      );
    });

    test('FitScore provider uses autoDispose (no keepAlive)', () {
      final file = File(_fitScoreProviderPath);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Expected $_fitScoreProviderPath to exist. If the provider '
            'was moved, update this test to point at the new path.',
      );

      final source = file.readAsStringSync();

      // The provider must opt into auto-dispose. Either as
      // `FutureProvider.family.autoDispose` or via the
      // `@Riverpod(keepAlive: false)` annotation. We accept either.
      final usesAutoDispose = source.contains('autoDispose') ||
          source.contains('keepAlive: false');
      expect(
        usesAutoDispose,
        isTrue,
        reason:
            'FitScore provider must use autoDispose (or @Riverpod with '
            'keepAlive: false). A KeepAlive provider would cache stale '
            'fits across profile edits.',
      );

      // And it must NOT have keepAlive: true anywhere.
      expect(
        source.contains('keepAlive: true'),
        isFalse,
        reason:
            'FitScore provider has `keepAlive: true`. That breaks the '
            'non-persistence rule.',
      );

      // It must watch the profile so any change auto-invalidates.
      expect(
        source.contains('watch(profileProvider)'),
        isTrue,
        reason:
            'FitScore provider must watch(profileProvider) so a profile '
            'change invalidates the computation.',
      );
    });

    test('no other file in lib/ persists "fit_score"', () {
      final offenders = <String>[];
      final libDir = Directory('lib');

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('.g.dart')) continue;
        if (entity.path.endsWith('.drift.dart')) continue;

        // Skip files that are explicitly allowed to mention fit_score.
        final inAllowedPath = _allowedFitScoreReferencesIn.any(
          (allowed) => entity.path.startsWith(allowed),
        );
        if (inAllowedPath) continue;

        final source = entity.readAsStringSync();
        if (source.contains('fit_score')) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Files outside the allowed compute path reference '
            '"fit_score":\n${offenders.join('\n')}\n\n'
            'FitScore should be computed in lib/services/fit_score/ and '
            'consumed via the dedicated provider only. If you believe '
            'one of these files legitimately needs to reference it, '
            'add the path to _allowedFitScoreReferencesIn AND document '
            'why in knowledge/sentry-autofix-playbook.md.',
      );
    });
  });
}
