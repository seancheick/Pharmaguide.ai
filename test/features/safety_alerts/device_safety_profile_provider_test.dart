import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/features/stack/providers/medication_identity_providers.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';

Future<DeviceSafetyProfile> _read(List<Override> overrides) {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  return container.read(deviceSafetyProfileProvider.future);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final medications = localMedicationIdentityProvider.overrideWith(
    (ref) async => (ids: const {'class:fake'}, isComplete: true),
  );
  ProfileState throwing() => throw StateError('unreadable');

  test('a pregnancy in the profile becomes the flag rules ask for, through '
      'the bundled taxonomy', () async {
    final device = await _read([
      medications,
      loadedProfileProvider.overrideWith(
        (ref) async => const ProfileState(conditions: ['pregnancy']),
      ),
    ]);

    expect(device.profileFlags, contains('pregnant'));
    expect(device.conditions, contains('pregnancy'));
    expect(device.medicationIds, {'class:fake'});
    expect(device.isComplete, isTrue);
  });

  test('a failed taxonomy is incomplete, not an all-clear', () async {
    final device = await _read([
      medications,
      loadedProfileProvider.overrideWith(
        (ref) async => const ProfileState(conditions: ['pregnancy']),
      ),
      evaluatorProfileFlagsProvider.overrideWith(
        (ref) async => throw StateError('no taxonomy'),
      ),
    ]);

    expect(device.profileFlags, isEmpty);
    expect(device.conditions, contains('pregnancy'));
    expect(device.isComplete, isFalse);
  });

  test('an unreadable profile leaves medications usable', () async {
    final device = await _read([
      medications,
      loadedProfileProvider.overrideWith((ref) async => throwing()),
    ]);

    expect(device.medicationIds, {'class:fake'});
    expect(device.isComplete, isFalse);
  });

  test('unreadable medications leave the profile usable', () async {
    final device = await _read([
      localMedicationIdentityProvider.overrideWith(
        (ref) async => throw StateError('unreadable'),
      ),
      loadedProfileProvider.overrideWith(
        (ref) async => const ProfileState(conditions: ['pregnancy']),
      ),
    ]);

    expect(device.conditions, contains('pregnancy'));
    expect(device.isComplete, isFalse);
  });
}
