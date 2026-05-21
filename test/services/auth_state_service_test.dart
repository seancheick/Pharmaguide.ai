import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/services/auth_state_service.dart';

void main() {
  test('falls back to guest mode when Supabase env is placeholder', () {
    expect(SupabaseConfig.isPlaceholder, isTrue);

    final service = AuthStateService();

    expect(service.state, AuthMode.guest);
  });

  test('release validation rejects placeholder Supabase config', () {
    expect(
      () => SupabaseConfig.validateForRuntime(releaseMode: true),
      throwsA(isA<SupabasePlaceholderConfigException>()),
    );
  });

  test('manual auth transitions still work', () {
    final service = AuthStateService();

    service.onSignedIn();
    expect(service.state, AuthMode.signedIn);

    service.onSignedOut();
    expect(service.state, AuthMode.guest);
  });
}
