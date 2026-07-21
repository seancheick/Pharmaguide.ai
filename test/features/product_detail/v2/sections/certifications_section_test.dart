import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_certification_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/certifications_section.dart';

// Regression: `certification_detail.gmp` ships as a nested object, not a bool.
// safeBool('gmp') always read false, so the "GMP Certified" badge never
// appeared. The fix reads the inner cert/compliance/program flags (bool or
// int 0/1), and deliberately excludes a bare manufacturer `claimed`.
void main() {
  Widget build(Map<String, dynamic>? cd) =>
      buildCertificationsSection(certificationDetail: cd);

  group('buildCertificationsSection GMP', () {
    test('null detail suppresses the section', () {
      expect(build(null), isA<SizedBox>());
    });

    test('bare `claimed` does not earn a GMP badge', () {
      expect(
        build(<String, dynamic>{
          'gmp': {'claimed': true, 'gmp_certified_or_compliant': false},
        }),
        isA<SizedBox>(),
      );
    });

    test('gmp_certified_or_compliant renders the badge (bool)', () {
      expect(
        build(<String, dynamic>{
          'gmp': {'gmp_certified_or_compliant': true},
        }),
        isA<PGCertificationSection>(),
      );
    });

    test('gmp_certified_or_compliant renders the badge (int 0/1)', () {
      expect(
        build(<String, dynamic>{
          'gmp': {'gmp_certified_or_compliant': 1},
        }),
        isA<PGCertificationSection>(),
      );
    });

    test('nsf_gmp / fda_registered also qualify', () {
      expect(
        build(<String, dynamic>{
          'gmp': {'nsf_gmp': true},
        }),
        isA<PGCertificationSection>(),
      );
      expect(
        build(<String, dynamic>{
          'gmp': {'fda_registered': 1},
        }),
        isA<PGCertificationSection>(),
      );
    });
  });
}
