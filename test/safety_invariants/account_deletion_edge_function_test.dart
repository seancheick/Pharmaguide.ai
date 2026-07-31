import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'account deletion removes private objects before deleting auth user',
    () {
      final file = File('supabase/functions/delete-account/index.ts');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();

      final listIndex = source.indexOf(
        'list_product_submission_objects_for_user',
      );
      final removeIndex = source.indexOf('removeStorageObjectsOrThrow(');
      final deleteUserIndex = source.indexOf('auth.admin.deleteUser');

      expect(source, contains('userClient.auth.getUser'));
      expect(listIndex, greaterThanOrEqualTo(0));
      expect(removeIndex, greaterThan(listIndex));
      expect(deleteUserIndex, greaterThan(removeIndex));
      expect(source, contains('product-submission-photos'));
      expect(source, contains('event: "account_deletion"'));
      expect(source, contains('../_shared/verified_storage_removal.ts'));
    },
  );

  test('account deletion is authenticated, bounded, and fail closed', () {
    final source = File(
      'supabase/functions/delete-account/index.ts',
    ).readAsStringSync();

    expect(source, contains('request.method !== "POST"'));
    expect(source, contains('authorization?.startsWith("Bearer ")'));
    expect(source, contains('resolveSupabasePublicKey'));
    expect(source, contains('resolveSupabaseAdminKey'));
    expect(source, contains('../_shared/supabase_server_keys.ts'));
    expect(source, contains('DELETE_CONFIRMATION'));
    expect(source, contains('MAX_BODY_BYTES = 1024'));
    expect(source, contains('new TextEncoder().encode(bodyText).byteLength'));
    expect(source, contains('MAX_OBJECTS_PER_DELETE = 1000'));
    expect(source, isNot(contains('user.email')));
    expect(source, isNot(contains('console.info(user')));
  });
}
