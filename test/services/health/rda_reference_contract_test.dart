import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/health/rda_reference_contract.dart';

void main() {
  const appReference = {
    '_metadata': {
      'reference_data_contract': {
        'reference_version': '5.0.0-2026-06-28',
        'semantic_fingerprint': 'sha256:canonical',
      },
    },
  };

  test('accepts product UL data stamped with the active reference', () {
    const productUlData = {
      'reference_data_version': '5.0.0-2026-06-28',
      'reference_data_fingerprint': 'sha256:canonical',
    };

    expect(
      hasCurrentRdaReference(
        appReferenceData: appReference,
        productRdaUlData: productUlData,
      ),
      isTrue,
    );
  });

  test('rejects missing or mismatched product UL stamps', () {
    expect(
      hasCurrentRdaReference(
        appReferenceData: appReference,
        productRdaUlData: const {},
      ),
      isFalse,
    );
    expect(
      hasCurrentRdaReference(
        appReferenceData: appReference,
        productRdaUlData: const {
          'reference_data_version': '5.0.0-2026-06-28',
          'reference_data_fingerprint': 'sha256:other',
        },
      ),
      isFalse,
    );
  });
}
