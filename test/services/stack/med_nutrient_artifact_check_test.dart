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
    'depletions': const [],
  };

  test('a legacy asset with no _metadata is allowed (migration)', () {
    final r = checkMedicationDepletionsArtifact({'depletions': const []});
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

  test('activate returns the artifact unchanged when compatible', () {
    final data = versioned();
    expect(activateMedicationDepletionsArtifact(data), same(data));
  });

  test(
    'activate degrades an incompatible artifact to no depletions + logs',
    () {
      String? reason;
      final out = activateMedicationDepletionsArtifact(
        versioned(minRuntime: kMedNutrientRuntimeContract + 1),
        onIncompatible: (r) => reason = r,
      );
      expect(out['depletions'], isEmpty);
      expect(reason, isNotNull);
    },
  );

  test('activate preserves _metadata on degrade', () {
    final out = activateMedicationDepletionsArtifact(
      versioned(minRuntime: kMedNutrientRuntimeContract + 1),
    );
    expect(out['_metadata'], isNotNull);
  });
}
