import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_certification_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/certifications_section.dart';

// `certification_detail.gmp` ships as a nested object. Since 2026-09-16 the
// pipeline adds `audited_facility` + `audited_facility_basis`, copied from the
// Verification pillar's GMP decision, and the badge renders only that. Label
// wording ("GMP", "cGMP compliant", an NSF GMP mark) is self-asserted: the
// pillar gives it no points, so the app gives it no verified badge. Before,
// 399 products showed "GMP Certified" from label wording alone while 6,866
// products with pillar GMP credit showed no badge.
void main() {
  Widget build(Map<String, dynamic>? cd) =>
      buildCertificationsSection(certificationDetail: cd);

  List<PGCertification> certsOf(Widget widget) =>
      (widget as PGCertificationSection).certifications;

  group('buildCertificationsSection GMP', () {
    test('null detail suppresses the section', () {
      expect(build(null), isA<SizedBox>());
    });

    test('pillar-audited facility renders "Audited GMP facility"', () {
      final section = build(<String, dynamic>{
        'gmp': {
          'claimed': false,
          'audited_facility': true,
          'audited_facility_basis': 'manufacturer_facility',
        },
      });
      final gmp = certsOf(section).single;
      expect(gmp.label, 'Audited GMP facility');
      expect(gmp.verified, isTrue);
      expect(gmp.caption, 'Manufacturer facility record');
    });

    test('a verified certification basis is named in the caption', () {
      final section = build(<String, dynamic>{
        'gmp': {
          'audited_facility': 1,
          'audited_facility_basis': 'verified_certification',
        },
      });
      expect(
        certsOf(section).single.caption,
        'Implied by a verified certification',
      );
    });

    for (final labelOnly in <Map<String, dynamic>>[
      {'claimed': true},
      {'gmp_certified_or_compliant': true, 'text_matched': 'GMP'},
      {'gmp_certified_or_compliant': 1},
      {'nsf_gmp': true},
      {'fda_registered': 1},
      {'gmp_certified_or_compliant': true, 'audited_facility': false},
    ]) {
      test('label wording $labelOnly earns no GMP badge', () {
        expect(build(<String, dynamic>{'gmp': labelOnly}), isA<SizedBox>());
      });
    }
  });
}
