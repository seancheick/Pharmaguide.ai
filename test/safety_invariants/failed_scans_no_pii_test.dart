// Safety invariant: the failed-scan queue carries no user identifier.
//
// Layer 4 captures missed UPCs so the founder can triage them into the
// data pipeline. The contract: a "missing UPC" is a public product
// identifier — the same string printed on every bottle of that product
// worldwide. It is not health data, but it MUST NOT be tied to the
// person who scanned it. Aggregate counts across one device's misses
// are fine; the user, device, session, or location are not.
//
// This test locks the failed_scans table schema down to that explicit
// column set. If a future change adds, say, a `user_id` column "for
// debugging", this test fails before the change can ship.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _failedScansTablePath = 'lib/data/database/tables/failed_scans_table.dart';

// Exact allowlist for the FailedScans Drift table. Adding a column here
// is a privacy decision that requires updating the privacy contract
// comment in failed_scans_table.dart AND running it past a human
// reviewer. Do not loosen this list to make a fix pass.
const _allowedColumns = <String>{
  'upc',
  'attemptCount',
  'firstSeen',
  'lastSeen',
};

// Substrings that must never appear as a column name on this table.
// Anything matching these is a privacy regression — the queue must
// remain device-local-aggregate-only.
const _forbiddenColumnTokens = <String>[
  'user',
  'device',
  'session',
  'profile',
  'location',
  'lat',
  'lng',
  'ip',
  'email',
  'phone',
  'name',
  'id_token',
];

void main() {
  group('Safety invariant: failed-scan queue carries no PII', () {
    test('FailedScans table declares only the allowed column set', () {
      final file = File(_failedScansTablePath);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Expected $_failedScansTablePath to exist. If the table was '
            'moved or removed, update this test (and the privacy '
            'contract) to match the new layout.',
      );

      final source = file.readAsStringSync();

      // Drift columns are declared as `<Type>Column get <name> => ...`.
      final columnRegex = RegExp(
        r'(?:Real|Int|Text|Bool|Date|DateTime)Column\s+get\s+(\w+)',
      );
      final declared = columnRegex
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toSet();

      expect(
        declared,
        equals(_allowedColumns),
        reason:
            'FailedScans column set drifted. The table must remain a '
            'device-local aggregate keyed only on UPC. If you have a '
            'genuine need for a new column, document the privacy '
            'rationale in failed_scans_table.dart AND update this '
            'allowlist explicitly — do NOT silently widen the schema.',
      );

      // Defense in depth: even if someone updates the allowlist, none
      // of the declared columns may match a forbidden token.
      for (final column in declared) {
        for (final token in _forbiddenColumnTokens) {
          expect(
            column.toLowerCase().contains(token),
            isFalse,
            reason:
                'FailedScans column "$column" contains forbidden token '
                '"$token". The failed-scan queue must never be tied to '
                'a person, device, or location.',
          );
        }
      }
    });

    test('table name is the user-scoped namespace', () {
      final source = File(_failedScansTablePath).readAsStringSync();
      // Should live in user_data.db's user_-prefixed namespace, not
      // anywhere that would suggest cross-user/server-side state.
      expect(
        RegExp("tableName\\s*=>\\s*'user_failed_scans'").hasMatch(source),
        isTrue,
        reason:
            'FailedScans tableName must be user_failed_scans — it lives '
            'in user_data.db only. If you renamed it, ensure the new '
            'name still scopes the data to one device.',
      );
    });

    test('source explicitly documents the no-PII contract', () {
      final source = File(_failedScansTablePath).readAsStringSync();
      // The privacy comment is part of the contract — removing it
      // means the next person to touch this file may not know the
      // rule. The test enforces the comment exists.
      final hasPrivacyComment = source.toLowerCase().contains('no user_id') ||
          source.toLowerCase().contains('no user identifier') ||
          source.toLowerCase().contains('not tied to the person');
      expect(
        hasPrivacyComment,
        isTrue,
        reason:
            'failed_scans_table.dart must include the privacy contract '
            'comment that explains why this table carries only UPC + '
            'counts. Removing the comment is itself a regression.',
      );
    });
  });
}
