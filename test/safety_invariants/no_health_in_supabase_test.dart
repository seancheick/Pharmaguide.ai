// Safety invariant: no health data is written to Supabase.
//
// The app stores health-derived state (conditions, medications, profile,
// DOB, FitScore) on-device only. Two parallel guards exist:
//
//   1. lib/services/crash_reporting_service.dart scrubs sensitive keys
//      from Sentry breadcrumbs at runtime.
//   2. THIS test enforces the same rule for the Supabase write surface
//      at build time — by locking the only known Supabase write call
//      site (stack_sync_queue._rowToRemote) to an explicit allowlist of
//      columns, and by scanning the rest of `lib/` for any other write
//      that smells like health data.
//
// If a new Supabase write is added that needs new columns, this test
// will fail. The fix is NOT to weaken the allowlist — it's to either
// (a) confirm the new column carries no health info and add it
//     explicitly here AND in the playbook, or
// (b) keep the data on-device.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _stackSyncQueuePath =
    'lib/features/stack/services/stack_sync_queue.dart';

// Exact allowlist for the only known Supabase write call site. Adding a
// column here without updating knowledge/sentry-autofix-playbook.md is
// a process violation, not a code bug.
const _userStacksAllowedColumns = <String>{
  'id',
  'user_id',
  'type',
  'name',
  'dsld_id',
  'ingredient_keys',
  'dosage',
  'frequency',
  'added_at',
  'client_updated_at',
  'deleted_at',
};

// Substrings that must never appear as column names in any Supabase
// write payload. These are stricter than the breadcrumb scrubber
// because the breadcrumb list also blocks generic value matches —
// here we only care about column-name-shaped tokens.
const _forbiddenColumnTokens = <String>[
  'conditions',
  'medications',
  'medication_',
  'medical_',
  '_medical',
  'health_',
  '_health',
  'diagnosis',
  'symptoms',
  'allergies',
  'prescription',
  'dob',
  'birthdate',
  'fit_score',
];

// Regex for `.upsert(` / `.insert(` / `.update(` invocations. Used to
// locate write call sites in any file that also imports Supabase.
final _supabaseWriteRegex = RegExp(
  r'\.(upsert|insert|update)\s*\(',
  multiLine: true,
);

void main() {
  group('Safety invariant: no health data leaves the device', () {
    test('_rowToRemote in stack_sync_queue.dart writes only allowed columns',
        () {
      final file = File(_stackSyncQueuePath);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Expected $_stackSyncQueuePath to exist. Was it moved? '
            'If so, update this test AND the playbook to point at the '
            'new location.',
      );

      final source = file.readAsStringSync();

      // Pull the body of _rowToRemote so we don't accidentally match
      // unrelated map literals elsewhere in the file.
      final methodStart = source.indexOf('_rowToRemote');
      expect(
        methodStart,
        greaterThan(-1),
        reason:
            '_rowToRemote was removed or renamed in $_stackSyncQueuePath. '
            'If this is intentional, update both this test and the '
            'sentry-autofix playbook.',
      );

      final openBrace = source.indexOf('{', methodStart);
      // Walk forward to find the matching close brace.
      var depth = 0;
      var closeBrace = -1;
      for (var i = openBrace; i < source.length; i++) {
        if (source[i] == '{') depth++;
        if (source[i] == '}') {
          depth--;
          if (depth == 0) {
            closeBrace = i;
            break;
          }
        }
      }
      expect(closeBrace, greaterThan(openBrace));

      final body = source.substring(openBrace, closeBrace);

      // Extract every quoted-string key in the map literal. These are
      // the column names being upserted.
      final keyMatches = RegExp("'([a-zA-Z_][a-zA-Z0-9_]*)'\\s*:")
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toSet();

      expect(
        keyMatches,
        equals(_userStacksAllowedColumns),
        reason:
            'stack_sync_queue._rowToRemote columns drifted from the '
            'allowlist. If you intentionally added or removed a column, '
            'update _userStacksAllowedColumns here and document the new '
            'column in knowledge/sentry-autofix-playbook.md. Do NOT add '
            'any column that carries health data (conditions, medications, '
            'profile, DOB, FitScore, etc.).',
      );

      // Defense in depth: even if the allowlist is updated, none of
      // those names may contain a forbidden substring.
      for (final column in keyMatches) {
        for (final token in _forbiddenColumnTokens) {
          expect(
            column.toLowerCase().contains(token),
            isFalse,
            reason:
                'Column "$column" contains forbidden token "$token" — '
                'this looks like health data being written to Supabase. '
                'Health data must stay on-device.',
          );
        }
      }
    });

    test('no other file in lib/ writes forbidden tokens to Supabase', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final offenders = <String>[];

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        // Generated files are out of scope — they ship from build_runner.
        if (entity.path.endsWith('.g.dart')) continue;
        if (entity.path.endsWith('.drift.dart')) continue;
        if (entity.path.endsWith('.freezed.dart')) continue;

        final source = entity.readAsStringSync();
        if (!source.contains('supabase_flutter') &&
            !source.contains('Supabase.instance')) {
          continue;
        }

        // For each .upsert/.insert/.update site, inspect the next 40
        // lines for forbidden column tokens appearing inside a quoted
        // string. This catches `'medications': ...` style map literals.
        for (final match in _supabaseWriteRegex.allMatches(source)) {
          final start = match.start;
          final end = (start + 2000).clamp(0, source.length);
          final window = source.substring(start, end);

          for (final token in _forbiddenColumnTokens) {
            final tokenRegex = RegExp("['\"]([a-zA-Z0-9_]*$token[a-zA-Z0-9_]*)['\"]");
            for (final hit in tokenRegex.allMatches(window)) {
              offenders.add(
                '${entity.path}: forbidden token "$token" in column '
                '"${hit.group(1)}" near a Supabase write.',
              );
            }
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Found Supabase write(s) that look like they include health '
            'data:\n${offenders.join('\n')}\n\n'
            'Health data must stay on-device. If you believe this is a '
            'false positive, narrow _forbiddenColumnTokens — but consult '
            'a human reviewer first.',
      );
    });
  });
}
