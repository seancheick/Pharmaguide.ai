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

  test('failed safety-alert sends stay queued with attempts and error recorded', () {
    const retryMigrationPath =
        'supabase/migrations/20260825031508_safety_alert_delivery_retry.sql';
    final file = File(retryMigrationPath);
    expect(file.existsSync(), isTrue,
        reason: 'The retry migration must ship: without it a transient FCM '
            'failure deletes the delivery row and the alert is silently lost.');
    final sql = _normalized(file.readAsStringSync());

    expect(sql, contains('add column if not exists attempts integer not null default 0'));
    expect(sql, contains('add column if not exists last_error text'));
    // The released row is UPDATEd back into the queue — never deleted — and
    // the claim is back-dated so the next dispatch reclaims it immediately.
    expect(sql, contains('create function public.release_safety_alert_push_delivery'));
    expect(sql, contains('set attempts = attempts + 1'));
    expect(sql, contains("claimed_at = now() - interval '10 minutes'"));
    expect(sql, isNot(contains('delete from public.safety_alert_push_deliveries')));
    expect(
      sql,
      contains(
        'revoke all on function public.release_safety_alert_push_delivery(text, integer, uuid, text)',
      ),
    );
  });

  test('dispatcher reports undelivered pushes instead of claiming success', () {
    final source = File(
      'supabase/functions/dispatch-safety-alert-release/index.ts',
    ).readAsStringSync();

    expect(source, contains('p_error: outcome.detail'),
        reason: 'Failed sends must record why, for the delivery row audit trail.');
    expect(source, contains('const ok = failed === 0;'),
        reason: 'HTTP success with failed sends hid lost safety alerts.');
    expect(source, contains('ok ? 200 : 502'));
    expect(source, isNot(contains('json({ ok: true, sent, removed })')),
        reason: 'The unconditional-success response is the original defect.');
  });

  test('push tokens do not survive sign-out', () {
    final service = File(
      'lib/services/notifications/safety_push_service.dart',
    ).readAsStringSync();
    expect(service, contains('AuthChangeEvent.signedOut'),
        reason: 'Every sign-out path must invalidate the FCM token, or the '
            'signed-out device keeps receiving the account\'s notifications.');
    expect(service, contains('unregisterBeforeSignOut'));
    expect(service.contains('_deleteLocalToken'), isTrue);

    final auth = File('lib/services/auth/pg_auth_service.dart').readAsStringSync();
    final unregisterAt = auth.indexOf('unregisterBeforeSignOut');
    final signOutAt = auth.indexOf('supabase.auth.signOut()');
    expect(unregisterAt, greaterThan(-1));
    expect(signOutAt, greaterThan(unregisterAt),
        reason: 'The server-side row delete needs the JWT, so it must run '
            'before the session is destroyed.');

    final fn = File('supabase/functions/register-push-token/index.ts').readAsStringSync();
    expect(fn, contains('"unregister"'));
    expect(fn, contains('.eq("user_id", authData.user.id)'),
        reason: 'Unregister may only remove the caller\'s own token row.');
    expect(fn, contains('.eq("fcm_token", registration.token)'));
  });

  test('iOS token acquisition follows permission -> APNs -> FCM order', () {
    final service = File(
      'lib/services/notifications/safety_push_service.dart',
    ).readAsStringSync();
    final permissionAt = service.indexOf('requestPermission()');
    final apnsAt = service.indexOf('getAPNSToken()');
    final tokenAt = service.indexOf('_messaging.getToken()');
    expect(permissionAt, greaterThan(-1));
    expect(apnsAt, greaterThan(permissionAt),
        reason: 'Firebase requires the APNs token before FCM API calls on '
            'Apple platforms; getToken() first fails the whole session.');
    expect(tokenAt, greaterThan(apnsAt));

    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<string>fetch</string>'));
    expect(plist, contains('<string>remote-notification</string>'));
  });
}
