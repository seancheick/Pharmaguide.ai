// Release gate: Flutter's user-stack upsert must match the database contract.
//
// Flutter's versioned migrations own app data; the pipeline owns catalog
// distribution. This test makes that boundary explicit: no sync path may
// reintroduce an ID-only conflict target, and no app migration may redefine
// catalog-distribution objects.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/supabase/supabase_contract.dart';

const _syncSourcePath = 'lib/features/stack/services/stack_sync_queue.dart';
const _migrationPath =
    'supabase/migrations/20260710195306_user_stacks_product_identity_sync.sql';
const _timestampMigrationPath =
    'supabase/migrations/20260710200321_user_stacks_require_client_timestamp.sql';
const _appDataAccessMigrationPath =
    'supabase/migrations/20260710210013_app_data_schema_authority_and_access.sql';

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
        expect(source.contains('server_updated_at'), isFalse);
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

    test(
      'app-data migration owns least-privilege access and required fields',
      () async {
        final sql = await File(_appDataAccessMigrationPath).readAsString();

        expect(sql, contains('CREATE TABLE IF NOT EXISTS public.user_usage'));
        expect(
          sql,
          contains('CREATE TABLE IF NOT EXISTS public.pending_products'),
        );
        expect(sql, contains('ALTER COLUMN id DROP DEFAULT'));
        expect(sql, contains("ALTER COLUMN type SET DEFAULT 'supplement'"));
        expect(sql, contains('ALTER COLUMN type SET NOT NULL'));
        expect(sql, contains('user_stacks_type_supplement_check'));
        expect(sql, contains('ALTER COLUMN name SET NOT NULL'));
        expect(sql, contains('ALTER COLUMN scans_today SET NOT NULL'));
        expect(sql, contains('ALTER COLUMN reset_day_utc SET NOT NULL'));
        expect(sql, contains('ALTER COLUMN upc SET NOT NULL'));
        expect(sql, contains('ALTER COLUMN status SET NOT NULL'));
        expect(sql, contains('ALTER COLUMN submitted_at SET NOT NULL'));
        expect(sql, contains('pending_products_upc_nonblank_check'));
        expect(
          sql,
          contains('CREATE UNIQUE INDEX IF NOT EXISTS idx_user_usage_daily'),
        );
        expect(
          sql,
          contains(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_pending_products_user_normalized_upc_pending',
          ),
        );
        expect(
          sql,
          contains('CREATE OR REPLACE FUNCTION public.increment_usage'),
        );
        expect(sql, contains('TO authenticated'));
        expect(
          sql,
          contains('REVOKE ALL ON TABLE public.user_stacks FROM anon'),
        );
        expect(
          sql,
          contains(
            'REVOKE ALL ON FUNCTION public.increment_usage(uuid, text) FROM PUBLIC, anon, authenticated',
          ),
        );
        expect(sql, contains('SECURITY DEFINER'));
        expect(sql, contains('SET search_path = public, pg_catalog'));
        expect(
          sql,
          contains('IF p_user_id IS DISTINCT FROM auth.uid() THEN'),
        );
        expect(
          sql,
          contains("IF p_type NOT IN ('scan', 'ai_message') THEN"),
        );
        expect(
          sql,
          contains(
            'GRANT EXECUTE ON FUNCTION public.increment_usage(uuid, text) TO authenticated',
          ),
        );
      },
    );

    test(
      'app-data migration never redefines pipeline distribution objects',
      () async {
        final sql = await File(_appDataAccessMigrationPath).readAsString();

        expect(sql, isNot(contains('export_manifest')));
        expect(sql, isNot(contains('catalog_releases')));
        expect(sql, isNot(contains('rotate_manifest')));
        expect(sql, isNot(contains('ALTER DEFAULT PRIVILEGES')));
      },
    );
  });
}
