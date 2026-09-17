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
//
// Export schema 2.5.0 separates claimed from verified certifications:
// `claimed_programs` (every label claim, with its canonical registry program)
// and `verified_programs` (registry-verified product certifications). A
// program is verified only when it comes from the registry; everything else,
// including every pre-2.5 catalog entry, is a label claim.
void main() {
  Widget build(Map<String, dynamic>? cd) =>
      buildCertificationsSection(certificationDetail: cd);

  List<PGCertification> certsOf(Widget widget) =>
      (widget as PGCertificationSection).certifications;

  group('buildCertificationsSection GMP', () {
    test('null detail suppresses the section', () {
      expect(build(null), isA<SizedBox>());
    });

    test('registry-linked manufacturer renders a manufacturer-level badge', () {
      final section = build(<String, dynamic>{
        'verified_programs': <Object>[],
        'gmp': {
          'claimed': false,
          'audited_facility': true,
          'audited_facility_basis': 'manufacturer_facility',
        },
      });
      final gmp = certsOf(section).single;
      expect(gmp.label, 'GMP-registered manufacturer');
      expect(gmp.verified, isTrue);
      expect(
        gmp.caption,
        'Manufacturer listed in an audited GMP facility registry',
      );
    });

    test(
      'pre-2.5 manufacturer-facility GMP (free-text inference) earns no badge',
      () {
        expect(
          build(<String, dynamic>{
            'gmp': {
              'audited_facility': true,
              'audited_facility_basis': 'manufacturer_facility',
            },
          }),
          isA<SizedBox>(),
        );
      },
    );

    test('a verified certification basis renders "Audited GMP facility"', () {
      final gmp = certsOf(
        build(<String, dynamic>{
          'gmp': {
            'audited_facility': 1,
            'audited_facility_basis': 'verified_certification',
          },
        }),
      ).single;
      expect(gmp.label, 'Audited GMP facility');
      expect(gmp.caption, 'Implied by a verified product certification');
    });

    test('an unknown basis earns no badge', () {
      expect(
        build(<String, dynamic>{
          'verified_programs': <Object>[],
          'gmp': {
            'audited_facility': true,
            'audited_facility_basis': 'label_claim',
          },
        }),
        isA<SizedBox>(),
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

  group('claimed vs verified programs', () {
    const verifiedCaption = 'Verified in the official listing';
    const claimedCaption = 'Claimed on label';

    test('new catalog: verified programs, then remaining claims', () {
      final certs = certsOf(
        build(<String, dynamic>{
          'claimed_programs': [
            {'name': 'NSF Contents Certified', 'program': 'NSF Certified'},
            {'name': 'Informed Choice', 'program': 'Informed Choice'},
          ],
          'verified_programs': [
            {
              'name': 'NSF Certified',
              'program': 'NSF Certified',
              'record_id': 'NSF_CERTIFIE_1',
              'scope': 'sku',
              'source_url': 'https://info.nsf.org/Certified/Dietary/',
            },
          ],
          'third_party_programs': {
            'programs': [
              {
                'name': 'NSF Certified',
                'verified': true,
                'source': 'registry',
                'record_id': 'NSF_CERTIFIE_1',
              },
            ],
          },
          'purity_verified': true,
          'heavy_metal_tested': true,
          'label_accuracy_verified': true,
        }),
      );

      final programs = certs
          .where(
            (c) => c.caption == verifiedCaption || c.caption == claimedCaption,
          )
          .map((c) => (c.label, c.verified, c.caption))
          .toList();
      expect(programs, [
        ('NSF Certified', true, verifiedCaption),
        ('Informed Choice', false, claimedCaption),
      ]);
      expect(
        certs.map((c) => c.label),
        containsAll(<String>[
          'Purity Verified',
          'Heavy Metal Tested',
          'Label Accuracy Verified',
        ]),
      );
    });

    test(
      'new catalog: a claim-only product shows claims, no quality badge',
      () {
        final certs = certsOf(
          build(<String, dynamic>{
            'claimed_programs': [
              {'name': 'USP Verified', 'program': 'USP Verified'},
            ],
            'verified_programs': <Object>[],
            'third_party_programs': {'programs': <Object>[]},
            'purity_verified': false,
          }),
        );
        expect(certs.map((c) => (c.label, c.verified, c.caption)), [
          ('USP Verified', false, claimedCaption),
        ]);
      },
    );

    test('old catalog: legacy "verified": true entries are claims', () {
      final certs = certsOf(
        build(<String, dynamic>{
          'third_party_programs': {
            'programs': [
              {'name': 'Informed Choice', 'verified': true},
              {'name': 'USP Verified', 'verified': true, 'source': 'rules_db'},
              'NSF Sport',
            ],
          },
          // Pre-2.5 flags were derived from claims: never shown as verified.
          'purity_verified': 1,
          'heavy_metal_tested': 1,
          'label_accuracy_verified': 1,
        }),
      );
      expect(certs.map((c) => (c.label, c.verified, c.caption)), [
        ('Informed Choice', false, claimedCaption),
        ('USP Verified', false, claimedCaption),
        ('NSF Sport', false, claimedCaption),
      ]);
    });

    test(
      'legacy list entry verified only with registry source + record id',
      () {
        final certs = certsOf(
          build(<String, dynamic>{
            'third_party_programs': {
              'programs': [
                {
                  'name': 'NSF Sport',
                  'verified': true,
                  'source': 'registry',
                  'record_id': 'NSF_SPORT_1',
                },
                {'name': 'IFOS', 'verified': true, 'source': 'registry'},
                {'name': 'BSCG', 'verified': true, 'source': 'manufacturer'},
              ],
            },
          }),
        );
        expect(certs.map((c) => (c.label, c.verified)), [
          ('NSF Sport', true),
          ('IFOS', false),
          ('BSCG', false),
        ]);
      },
    );

    test('a claim-only product still offers the certifications section', () {
      expect(
        hasRenderableCertifications(<String, dynamic>{
          'claimed_programs': [
            {'name': 'USP Verified', 'program': 'USP Verified'},
          ],
          'verified_programs': <Object>[],
        }),
        isTrue,
      );
    });
  });
}
