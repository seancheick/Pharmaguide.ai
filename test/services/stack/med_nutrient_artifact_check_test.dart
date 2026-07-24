// Activation-compatibility gate for the versioned medication-depletions
// artifact (B1.2 App-1). The app renders an artifact only when it is
// structurally sound and its minimum_runtime_contract is within what this build
// supports. A legacy asset (no _metadata) is allowed so the migration never
// blanks the monitor; a genuinely incompatible or corrupt artifact is rejected
// (the caller then degrades to no depletions rather than render garbage).

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';

void main() {
  Map<String, dynamic> versioned({
    int? minRuntime = kMedNutrientRuntimeContract,
  }) => {
    '_metadata': {
      'schema_version': '5.4.0',
      'content_version': '2026.07.23',
      'content_hash': 'sha256:abc',
      if (minRuntime != null) 'minimum_runtime_contract': minRuntime,
    },
    'depletions': const <Map<String, dynamic>>[],
  };

  test('a legacy asset with no _metadata is allowed (migration)', () {
    final r = checkMedicationDepletionsArtifact({
      'depletions': const <Map<String, dynamic>>[],
    });
    expect(r.compatible, isTrue);
    expect(r.isLegacy, isTrue);
  });

  test('a versioned asset within the supported contract is compatible', () {
    final r = checkMedicationDepletionsArtifact(versioned());
    expect(r.compatible, isTrue);
    expect(r.isLegacy, isFalse);
  });

  test('an artifact requiring a newer runtime contract is rejected', () {
    final r = checkMedicationDepletionsArtifact(
      versioned(minRuntime: kMedNutrientRuntimeContract + 1),
    );
    expect(r.compatible, isFalse);
  });

  test('a corrupt artifact (no depletions list) is rejected', () {
    final r = checkMedicationDepletionsArtifact({
      '_metadata': {'minimum_runtime_contract': kMedNutrientRuntimeContract},
    });
    expect(r.compatible, isFalse);
  });

  test('a versioned artifact missing minimum_runtime_contract is rejected', () {
    final r = checkMedicationDepletionsArtifact(versioned(minRuntime: null));
    expect(r.compatible, isFalse);
  });

  test('activate returns loaded + the artifact when compatible', () {
    final data = versioned();
    final out = activateMedicationDepletionsArtifact(data);
    expect(out.status, MedNutrientLoadStatus.loaded);
    expect(out.data, same(data));
  });

  test(
    'activate marks an incompatible artifact UNAVAILABLE (not empty-success)',
    () {
      String? reason;
      final out = activateMedicationDepletionsArtifact(
        versioned(minRuntime: kMedNutrientRuntimeContract + 1),
        onIncompatible: (r) => reason = r,
      );
      // Unavailable must be distinguishable from a clean "no depletions" load —
      // the caller shows an unavailable state, never a false all-clear.
      expect(out.status, MedNutrientLoadStatus.unavailable);
      expect(out.data['depletions'], isEmpty);
      expect(reason, isNotNull);
    },
  );

  test('activate preserves _metadata on an unavailable result', () {
    final out = activateMedicationDepletionsArtifact(
      versioned(minRuntime: kMedNutrientRuntimeContract + 1),
    );
    expect(out.data['_metadata'], isNotNull);
  });
}
