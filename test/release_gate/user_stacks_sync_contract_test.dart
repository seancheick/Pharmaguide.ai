// Release gate: Flutter's user-stack upsert must match the database contract.
//
// The pipeline bootstrap owns executable Supabase DDL. Flutter owns the
// PostgREST wire value through [SupabaseContract]. This test makes both sides
// explicit: no sync path may reintroduce an ID-only conflict target, and the
// applied migration must retain the database guarantees that target requires.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/supabase/supabase_contract.dart';

const _syncSourcePath = 'lib/features/stack/services/stack_sync_queue.dart';
const _migrationPath =
    'supabase/migrations/20260710195306_user_stacks_product_identity_sync.sql';
const _timestampMigrationPath =
    'supabase/migrations/20260710200321_user_stacks_require_client_timestamp.sql';

void main() {
  group('release gate: user stack sync contract', () {
    test('defines one shared PostgREST product-state conflict target', () {
      expect(
        SupabaseContract.userStacksProductConflictTarget,
        'user_id,dsld_id',
      );
    });

    test(
      'every user-stack upsert uses the shared product-state target',
      () async {
        final source = await File(_syncSourcePath).readAsString();
        const expected =
            'onConflict: SupabaseContract.userStacksProductConflictTarget';

        expect(source.contains("onConflict: 'id'"), isFalse);
        expect(source.contains(expected), isTrue);
        expect(
          expected.allMatches(source).length,
          2,
          reason:
              'The batch and per-row recovery upserts must use one shared '
              'conflict target; a mismatch reintroduces 23505 replacement-row '
              'failures.',
        );
        expect(source.contains("'user_id,dsld_id'"), isFalse);
      },
    );

    test(
      'the applied migration guarantees the client conflict target',
      () async {
        final sql = await File(_migrationPath).readAsString();

        expect(sql, contains('UNIQUE (user_id, dsld_id)'));
        expect(sql, contains('ALTER COLUMN dsld_id SET NOT NULL'));
        expect(
          sql,
          contains(
            'DROP INDEX IF EXISTS public.idx_user_stacks_user_dsld_active',
          ),
        );
        expect(
          sql,
          contains('CREATE TRIGGER zz_user_stacks_keep_newest_state'),
        );
      },
    );

    test(
      'the LWW timestamp is required by an immutable follow-up migration',
      () async {
        final sql = await File(_timestampMigrationPath).readAsString();

        expect(sql, contains('WHERE client_updated_at IS NULL'));
        expect(sql, contains('ALTER COLUMN client_updated_at SET NOT NULL'));
      },
    );
  });
}
