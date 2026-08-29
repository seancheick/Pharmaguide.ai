import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _migrationPath =
    'supabase/migrations/20260830090000_storage_inventory_rpc.sql';

String _normalized(String source) => source
    .replaceAll(RegExp(r'--[^\n]*'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

void main() {
  test('storage inventory RPC migration has one executable Supabase owner', () {
    final migration = File(_migrationPath);
    expect(
      migration.existsSync(),
      isTrue,
      reason: 'The linked Supabase project must own the exact-version migration.',
    );

    final sql = _normalized(migration.readAsStringSync());
    expect(sql, contains('security invoker'));
    expect(sql, contains("set search_path = ''"));
    expect(
      sql,
      contains(
        'revoke execute on function public.pg_storage_inventory_summary(text) '
        'from public, anon, authenticated',
      ),
    );
    expect(
      sql,
      contains(
        'revoke execute on function public.pg_storage_inventory_page(text, text, integer) '
        'from public, anon, authenticated',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.pg_storage_inventory_summary(text) '
        'to service_role',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.pg_storage_inventory_page(text, text, integer) '
        'to service_role',
      ),
    );
    expect(sql, contains("o.bucket_id = 'pharmaguide'"));
    expect(sql, contains('pg_storage_inventory_prefix_ok(p_prefix)'));
    expect(sql, isNot(contains('security definer')));
  });

  test('storage inventory rollout records the exact reviewed migration version', () {
    final rollout = File('tool/apply_storage_inventory_rpc.sh');
    expect(
      rollout.existsSync(),
      isTrue,
      reason: 'Existing multi-owner history prevents a blanket db push; the '
          'reviewed migration needs a narrow executable rollout.',
    );

    final source = rollout.readAsStringSync();
    expect(source, contains('20260830090000_storage_inventory_rpc.sql'));
    expect(source, contains('supabase db query'));
    expect(source, contains('--file'));
    expect(
      source,
      contains('supabase migration repair --status applied 20260830090000'),
    );
    expect(source, contains('supabase migration list --linked'));
    expect(source, contains(r'do $verify$'));
    expect(source, contains('raise exception'));
    expect(
      source,
      contains('storage inventory RPC live-contract verification failed'),
    );
    expect(source, isNot(contains('supabase_migrations.schema_migrations')));
    expect(source, isNot(contains('delete from supabase_migrations')));
    expect(source, isNot(contains('insert into supabase_migrations')));
  });
}
