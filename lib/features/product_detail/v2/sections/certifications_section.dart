// Certifications section adapter.
//
// Reads from the `certification_detail` blob:
// - a nested `gmp` object (badge from the Verification pillar's decision);
// - `verified_programs`: registry-verified product certifications (export
//   schema 2.5.0+), rendered "Verified in the official listing";
// - `claimed_programs`: every label claim with its canonical registry
//   `program`, rendered "Claimed on label" unless the same program is
//   verified;
// - legacy `third_party_programs.programs`: an entry is verified only when it
//   comes from the registry (`source: "registry"` with a `record_id`). Every
//   pre-2.5 entry, and any entry with a missing or unknown source, is a claim;
// - purity / heavy-metal / label-accuracy flags, shown only under the 2.5.0
//   contract (pre-2.5 flags were derived from label claims).
// Section auto-suppresses when the resulting list is empty.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_certification_section.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';

/// Build the Certifications section. Returns `SizedBox.shrink()` when
/// the blob is null, or when no certification fields are positive.
Widget buildCertificationsSection({
  required Map<String, dynamic>? certificationDetail,
}) {
  final certs = _certificationsFromDetail(certificationDetail);
  if (certs.isEmpty) return const SizedBox.shrink();
  return PGCertificationSection(certifications: certs);
}

/// Mirrors [buildCertificationsSection]'s visibility contract so callers only
/// offer navigation when the destination can render real certificate data.
bool hasRenderableCertifications(Map<String, dynamic>? certificationDetail) =>
    _certificationsFromDetail(certificationDetail).isNotEmpty;

List<PGCertification> _certificationsFromDetail(
  Map<String, dynamic>? certificationDetail,
) {
  if (certificationDetail == null) return const [];
  final certs = <PGCertification>[];

  // Four standard quality checks — production renders these even when
  // false (greyed). For the v2 component, only render verified=true
  // entries since the section title implies positives; unverified
  // checks appear in LabelConfidence (S4) when relevant. Production
  // suppresses the entire section when none are true.
  //
  // `gmp` is a nested object. The badge renders the Verification pillar's
  // audited-facility decision (`audited_facility`, copied by the pipeline);
  // label GMP wording is self-asserted and earns neither pillar points nor a
  // badge. The app never re-derives GMP from the label flags.
  final gmpBadge = _auditedGmpBadge(certificationDetail);
  if (gmpBadge != null) certs.add(gmpBadge);
  // Pre-2.5 catalogs derived these flags from label claims; only the 2.5.0
  // contract (which carries `verified_programs`) derives them from verified
  // registry certifications.
  final hasVerificationContract =
      certificationDetail['verified_programs'] is List;
  if (hasVerificationContract) {
    for (final (key, label) in const [
      ('purity_verified', 'Purity Verified'),
      ('heavy_metal_tested', 'Heavy Metal Tested'),
      ('label_accuracy_verified', 'Label Accuracy Verified'),
    ]) {
      if (certificationDetail.safeBool(key)) {
        certs.add(PGCertification(label: label, verified: true));
      }
    }
  }

  certs.addAll(_programCertifications(certificationDetail));
  return certs;
}

const _verifiedCaption = 'Verified in the official listing';
const _claimedCaption = 'Claimed on label';

/// Verified programs first, then the label claims no verification covers.
/// Keys are canonical registry programs, so "NSF Contents Certified" on the
/// label is covered by a verified "NSF Certified" listing.
List<PGCertification> _programCertifications(Map<String, dynamic> detail) {
  final verified = <String, String>{};
  final claimed = <String, String>{};

  void add(Map<String, String> into, String? name, String? program) {
    final label = (name ?? '').trim().isNotEmpty
        ? name!.trim()
        : (program ?? '').trim();
    final key = (program ?? '').trim().isNotEmpty ? program!.trim() : label;
    if (label.isEmpty) return;
    into.putIfAbsent(key.toLowerCase(), () => label);
  }

  for (final entry in detail.safeList('verified_programs')) {
    if (entry is Map) {
      add(verified, entry['name']?.toString(), entry['program']?.toString());
    }
  }
  for (final entry
      in detail.safeMap('third_party_programs').safeList('programs')) {
    if (entry is Map &&
        entry['source']?.toString() == 'registry' &&
        (entry['record_id']?.toString() ?? '').trim().isNotEmpty) {
      add(verified, entry['name']?.toString(), entry['program']?.toString());
    } else if (entry is Map) {
      add(claimed, entry['name']?.toString(), entry['program']?.toString());
    } else if (entry is String) {
      add(claimed, entry, null);
    }
  }
  for (final entry in detail.safeList('claimed_programs')) {
    if (entry is Map) {
      add(claimed, entry['name']?.toString(), entry['program']?.toString());
    } else if (entry is String) {
      add(claimed, entry, null);
    }
  }

  return [
    for (final label in verified.values)
      PGCertification(label: label, verified: true, caption: _verifiedCaption),
    for (final MapEntry(:key, :value) in claimed.entries)
      if (!verified.containsKey(key))
        PGCertification(
          label: value,
          verified: false,
          caption: _claimedCaption,
        ),
  ];
}

/// "Audited GMP facility" when the pipeline's Verification pillar credited an
/// audited source: a verified certification whose program audits GMP, or a
/// manufacturer facility record naming a certified/audited facility.
PGCertification? _auditedGmpBadge(Map<String, dynamic> certificationDetail) {
  final gmp = certificationDetail.safeMap('gmp');
  if (!gmp.safeBool('audited_facility')) return null;
  final caption = switch (gmp['audited_facility_basis']?.toString()) {
    'verified_certification' => 'Implied by a verified certification',
    'manufacturer_facility' => 'Manufacturer facility record',
    _ => null,
  };
  return PGCertification(
    label: 'Audited GMP facility',
    verified: true,
    caption: caption,
  );
}
