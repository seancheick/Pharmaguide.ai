// Release gate: PHI medications must never reach the Supabase sync path.
//
// Medications added via the M4 medication-entry flow are PHI and stay on
// the device by design (spec §8.5). Enforced at three layers:
//
//   1. The Drift query `StackSyncQueue.dirtyRows()` must filter out rows
//      where `type == 'medication'`. This is the only path that feeds
//      `StackSyncService.pushAll()`.
//   2. `StackSyncService.pushAll()` must belt-and-suspenders-assert
//      `row.type == 'supplement'` before every `.upsert()` call.
//   3. `StackActions.addMedication()` must not call `_triggerSync()` —
//      the entry point is deliberately silent.
//
// This file is a static grep test: it reads the sync source files and
// asserts the above patterns exist, and asserts that only the audited
// sync file touches `supabase.from('user_stacks')`. If any of these
// contracts regress, the release gate build-fails instead of shipping
// a PHI leak.
//
// Nothing here talks to the network, Drift, or Riverpod. It's a pure
// file-system scan so it runs in milliseconds and cannot flake.
//
// Run with: flutter test test/release_gate/phi_medication_no_sync_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _libRoot = 'lib';
const _syncFile = 'lib/features/stack/services/stack_sync_queue.dart';
// After the 2026-04-16 stack_providers.dart split, StackActions lives in
// active_stack_provider.dart (re-exported via the stack_providers.dart
// barrel). This release gate reads the source directly, so it must point
// at the split file, not the barrel.
const _actionsFile = 'lib/features/stack/providers/active_stack_provider.dart';

/// Files allowed to reference `supabase.from('user_stacks')` or the
/// upsert-shaped push. Anything outside this allowlist fails the gate:
/// a second sync path would be a latent PHI leak even if it happens to
/// filter medications today.
const _userStacksUpsertAllowlist = <String>{
  'lib/features/stack/services/stack_sync_queue.dart',
};

void main() {
  group('release gate: PHI medications never reach stack sync', () {
    test('StackSyncQueue.dirtyRows filters out type=medication rows', () async {
      final source = await File(_syncFile).readAsString();

      // The query helper must exclude medications at the query level.
      // We accept either the drift `.equals('medication').not()` form
      // currently in use OR a plain `type != 'medication'` predicate,
      // so the test survives a future refactor that switches styles.
      final medicationExclusionRegex = RegExp(
        r"type\.equals\s*\(\s*'medication'\s*\)\s*\.not\s*\(\s*\)"
        r"|type\s*!=\s*'medication'",
      );

      expect(
        medicationExclusionRegex.hasMatch(source),
        isTrue,
        reason:
            'StackSyncQueue.dirtyRows() must filter `type == \'medication\'` '
            'out of the dirty-row query. This is the single choke point '
            'that feeds StackSyncService.pushAll() — if it stops '
            'excluding medications, every PHI row becomes sync-eligible.',
      );
    });

    test(
      'StackSyncQueue.tombstoneRows filters out type=medication rows',
      () async {
        // Tombstones go through the same sync path, so they need the
        // same filter or a deleted medication row would leak out as a
        // delete request to Supabase.
        final source = await File(_syncFile).readAsString();

        // Look for the tombstoneRows() function body and assert the
        // medication filter appears inside it.
        final fnBodyMatch = RegExp(
          r'tombstoneRows\s*\([^{]*\)\s*\{([\s\S]*?)\n\s{2}\}',
        ).firstMatch(source);
        expect(
          fnBodyMatch,
          isNotNull,
          reason:
              'could not locate StackSyncQueue.tombstoneRows() body in '
              '$_syncFile — did the signature change?',
        );
        final body = fnBodyMatch!.group(1)!;
        expect(
          body.contains("type.equals('medication').not()") ||
              body.contains("type != 'medication'"),
          isTrue,
          reason:
              'StackSyncQueue.tombstoneRows() must filter out '
              '`type == \'medication\'` — otherwise a soft-deleted PHI '
              'row would push as a tombstone.',
        );
      },
    );

    test(
      'StackSyncService.pushAll asserts row.type == supplement before upsert',
      () async {
        final source = await File(_syncFile).readAsString();

        // Belt-and-suspenders assertion. We look for both the assert
        // and the defensive `continue` so a refactor that silently
        // drops the assert still has to preserve the filter.
        expect(
          source.contains("row.type == 'supplement'"),
          isTrue,
          reason:
              'StackSyncService.pushAll() must assert '
              "`row.type == 'supplement'` before pushing any row. "
              'This is the belt-and-suspenders check that catches '
              'regressions in dirtyRows().',
        );

        expect(
          source.contains("row.type != 'supplement'"),
          isTrue,
          reason:
              'StackSyncService.pushAll() must guard with '
              "`if (row.type != 'supplement') continue;` before "
              'calling upsert. An assert alone is stripped in '
              'release builds — the runtime filter must stay in place.',
        );
      },
    );

    test(
      'StackActions.addMedication deliberately skips _triggerSync',
      () async {
        // The medication entry path must never fire the sync trigger.
        // We extract the addMedication() body and assert it does NOT
        // call _triggerSync(). Medications are local-only by design.
        final source = await File(_actionsFile).readAsString();

        // Capture from `Future<String> addMedication(` through the
        // first closing brace that is two spaces in (matches class-
        // level method indentation). The simple form below accepts
        // nested braces by lazily matching up to `\n  }` on a line of
        // its own — consistent with the file's formatting.
        final fnMatch = RegExp(
          r'Future<String>\s+addMedication\s*\([\s\S]*?\n  \}',
        ).firstMatch(source);
        expect(
          fnMatch,
          isNotNull,
          reason:
              'could not locate StackActions.addMedication() in '
              '$_actionsFile — did the signature change?',
        );
        final body = fnMatch!.group(0)!;

        expect(
          body.contains('_triggerSync'),
          isFalse,
          reason:
              'StackActions.addMedication() must NOT call _triggerSync(). '
              'Medications are PHI and never leave the device. If you '
              'added a sync trigger to this method you reintroduced a '
              'PHI leak.',
        );
      },
    );

    test(
      'only the audited sync file references supabase.from(\'user_stacks\')',
      () async {
        // Any other file pushing to user_stacks would be a second sync
        // path that this gate does not audit — reject it outright so
        // reviewers are forced to add the new file to the allowlist
        // (and accept the obligation to re-audit the PHI filter there).
        final offenders = <String>[];
        await for (final entity in Directory(_libRoot).list(recursive: true)) {
          if (entity is! File) continue;
          if (!entity.path.endsWith('.dart')) continue;
          final rel = p.relative(entity.path);
          if (_userStacksUpsertAllowlist.contains(rel)) continue;

          final content = await entity.readAsString();
          // We look for `.from('user_stacks')` — the specific Supabase
          // table-entry call. Strip out string matches that are plainly
          // in a doc comment by requiring no leading `///` on the same
          // line.
          final lines = content.split('\n');
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            if (line.trimLeft().startsWith('///')) continue;
            if (line.trimLeft().startsWith('//')) continue;
            if (line.contains(".from('user_stacks')") ||
                line.contains('.from("user_stacks")')) {
              offenders.add('$rel:${i + 1}: ${line.trim()}');
            }
          }
        }

        expect(
          offenders,
          isEmpty,
          reason:
              'The following files reference supabase.from(\'user_stacks\') '
              'but are not on the PHI sync allowlist. Every such call '
              'is a potential medication leak — either remove the call '
              'or add the file to _userStacksUpsertAllowlist in this '
              'test after verifying that it filters out '
              'type==medication rows:\n  ${offenders.join('\n  ')}',
        );
      },
    );

    test(
      'no .dart source pushes a medication row to user_stacks in-line',
      () async {
        // Final static tripwire: no file anywhere in lib/ should have
        // both the string literal `'medication'` AND a reference to
        // `user_stacks` AND a call to `.upsert(` on the same file,
        // unless it's the audited sync path. The shape below catches
        // the obvious "copy the sync helper and forget the filter"
        // regression.
        final offenders = <String>[];
        await for (final entity in Directory(_libRoot).list(recursive: true)) {
          if (entity is! File) continue;
          if (!entity.path.endsWith('.dart')) continue;
          final rel = p.relative(entity.path);
          if (_userStacksUpsertAllowlist.contains(rel)) continue;

          final content = await entity.readAsString();
          final mentionsMedication =
              content.contains("'medication'") ||
              content.contains('"medication"');
          final mentionsUserStacksTable =
              content.contains("'user_stacks'") ||
              content.contains('"user_stacks"');
          final mentionsUpsert = content.contains('.upsert(');

          if (mentionsMedication && mentionsUserStacksTable && mentionsUpsert) {
            offenders.add(rel);
          }
        }

        expect(
          offenders,
          isEmpty,
          reason:
              'The following files mention both a medication string '
              'literal and a user_stacks upsert — this is the exact '
              'shape of a PHI leak. Audit and move to the sync '
              'allowlist (or remove the upsert):\n  '
              '${offenders.join('\n  ')}',
        );
      },
    );
  });
}
