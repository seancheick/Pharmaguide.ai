import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _migrationPath =
    'supabase/migrations/20260808120000_safety_alert_delivery.sql';

String _normalized(String source) => source
    .replaceAll(RegExp(r'--[^\n]*'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

void main() {
  test('safety-alert distribution keeps releases public and device tokens private', () {
    final file = File(_migrationPath);
    expect(file.existsSync(), isTrue, reason: 'Safety alert delivery migration must ship.');
    final sql = _normalized(file.readAsStringSync());

    expect(sql, contains('create table if not exists public.safety_alert_releases'));
    expect(sql, contains('create table if not exists public.device_push_tokens'));
    expect(sql, contains('create table if not exists public.safety_alert_push_deliveries'));
    expect(sql, contains('alter table public.safety_alert_releases enable row level security'));
    expect(sql, contains('alter table public.device_push_tokens enable row level security'));
    expect(sql, contains('alter table public.safety_alert_push_deliveries enable row level security'));
    expect(sql, contains('create policy "safety_alert_releases_read_current"'));
    expect(sql, contains('using (is_current = true)'));
    expect(sql, contains('revoke all on table public.device_push_tokens from anon, authenticated'));
    expect(sql, contains('revoke all on table public.safety_alert_push_deliveries from anon, authenticated'));
    expect(sql, isNot(contains('grant select on table public.device_push_tokens to authenticated')));
    expect(sql, contains('create or replace function public.promote_safety_alert_release'));
    expect(sql, contains('security definer'));
    expect(sql, contains('set search_path = \'\''));
  });
}
