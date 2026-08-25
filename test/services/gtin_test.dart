import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/gtin.dart';

Map<String, Object?> _fixture() {
  final contents = File('test/fixtures/gtin_golden.json').readAsStringSync();
  return jsonDecode(contents) as Map<String, Object?>;
}

Set<String> _strings(Object? value) =>
    (value! as List<Object?>).cast<String>().toSet();

void main() {
  final fixture = _fixture();

  group('GtinIdentity golden contract', () {
    for (final value in fixture['valid_identities']! as List<Object?>) {
      final vector = value! as Map<String, Object?>;
      test('${vector['name']} parses to one canonical identity', () {
        final symbology = GtinSymbology.values.byName(
          vector['symbology']! as String,
        );

        final identity = GtinIdentity.parse(
          vector['input']! as String,
          detectedSymbology: symbology,
        );

        expect(identity.rawDigits, vector['input']);
        expect(identity.detectedSymbology, symbology);
        expect(identity.canonicalGtin14, vector['canonical_gtin14']);
        expect(
          identity.lookupCandidates.toSet(),
          _strings(vector['lookup_candidates']),
        );
        expect(
          identity.submissionIdentity,
          vector['submission_identity'] ?? vector['canonical_gtin14'],
        );
        if (vector['expanded_upca'] case final String expanded) {
          expect(expandUpcE(vector['input']! as String), expanded);
          expect(identity.lookupCandidates, contains(expanded));
        }
      });
    }

    for (final value in fixture['invalid_inputs']! as List<Object?>) {
      final vector = value! as Map<String, Object?>;
      test('rejects ${vector['name']}', () {
        expect(
          () => GtinIdentity.parse(vector['input']! as String),
          throwsA(isA<FormatException>()),
        );
      });
    }
  });

  group('manual eight-digit ambiguity', () {
    for (final value in fixture['manual_eight_digit']! as List<Object?>) {
      final vector = value! as Map<String, Object?>;
      test(vector['name']! as String, () {
        final identity = GtinIdentity.parse(vector['input']! as String);

        expect(identity.canonicalGtin14, vector['primary_canonical_gtin14']);
        expect(
          identity.lookupCandidates.toSet(),
          _strings(vector['lookup_candidates']),
        );
        expect(identity.lookupCandidates, contains(vector['upce_expanded']));
      });
    }
  });

  test('GS1 zero-padded widths share one canonical GTIN-14', () {
    final equivalents = (fixture['zero_pad_equivalence']! as List<Object?>)
        .cast<String>();

    final canonical = equivalents
        .map(GtinIdentity.parse)
        .map((identity) => identity.canonicalGtin14)
        .toSet();

    expect(canonical, {'00016000275447'});
  });

  test('isValidGtin validates only standard GTIN widths and check digits', () {
    expect(isValidGtin('050428381397'), isTrue);
    expect(isValidGtin('4006381333931'), isTrue);
    expect(isValidGtin('96385074'), isTrue);
    expect(isValidGtin('050428381398'), isFalse);
    expect(isValidGtin('123456789'), isFalse);
  });
}
