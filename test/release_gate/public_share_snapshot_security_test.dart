import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public share snapshots are server-only and preserve disposition', () {
    final hardening = File(
      'supabase/migrations/20260814090000_secure_public_share_snapshots.sql',
    ).readAsStringSync();

    expect(hardening, contains('catalog_disposition'));
    expect(
      hardening,
      isNot(contains('GRANT SELECT ON public.public_share_snapshots TO anon')),
    );
    expect(hardening, isNot(contains('USING (true)')));
    expect(
      hardening,
      contains('REVOKE ALL ON public.public_share_snapshots FROM anon'),
    );
    expect(
      hardening,
      contains('REVOKE ALL ON public.public_share_snapshots FROM PUBLIC'),
    );
    expect(
      hardening,
      contains(
        'REVOKE ALL ON public.public_share_snapshots FROM authenticated',
      ),
    );
    expect(
      hardening,
      contains('DROP POLICY IF EXISTS share_snapshots_public_read'),
    );
    expect(hardening, contains('ALTER COLUMN catalog_version SET NOT NULL'));
  });
}
