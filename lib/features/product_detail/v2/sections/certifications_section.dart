// Certifications section adapter.
//
// Reads from `certification_detail` blob: a nested `gmp` object plus three
// int-0/1 flags (purity_verified, heavy_metal_tested, label_accuracy_verified)
// and a `third_party_programs.programs` list. Section is suppressed when none
// of the fields/programs are positive.
//
// V2 maps each blob field 1:1 → PGCertification. Third-party programs
// each get a verified=true entry with the program name as the label.
// Section auto-suppresses when the resulting list is empty.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_certification_section.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';

/// Build the Certifications section. Returns `SizedBox.shrink()` when
/// the blob is null, or when no certification fields are positive.
Widget buildCertificationsSection({
  required Map<String, dynamic>? certificationDetail,
}) {
  if (certificationDetail == null) return const SizedBox.shrink();

  final certs = <PGCertification>[];

  // Four standard quality checks — production renders these even when
  // false (greyed). For the v2 component, only render verified=true
  // entries since the section title implies positives; unverified
  // checks appear in LabelConfidence (S4) when relevant. Production
  // suppresses the entire section when none are true.
  //
  // `gmp` is a nested object ({claimed, gmp_certified_or_compliant,
  // nsf_gmp, fda_registered, text_matched}), NOT a bool — safeBool('gmp')
  // always read false. A "GMP Certified" badge requires an actual
  // certification/compliance/program signal; a bare manufacturer `claimed`
  // does not earn it (under-claim over over-claim on a safety product).
  if (_gmpCertified(certificationDetail)) {
    certs.add(const PGCertification(label: 'GMP Certified', verified: true));
  }
  if (certificationDetail.safeBool('purity_verified')) {
    certs.add(const PGCertification(label: 'Purity Verified', verified: true));
  }
  if (certificationDetail.safeBool('heavy_metal_tested')) {
    certs.add(
      const PGCertification(label: 'Heavy Metal Tested', verified: true),
    );
  }
  if (certificationDetail.safeBool('label_accuracy_verified')) {
    certs.add(
      const PGCertification(label: 'Label Accuracy Verified', verified: true),
    );
  }

  // Third-party programs — pipeline ships either string list or
  // [{name, verified}] map list. Defensive extraction (matches
  // production lines 94-105 verbatim).
  final programs = certificationDetail
      .safeMap('third_party_programs')
      .safeList('programs')
      .map<String>((e) {
        if (e is String) return e.trim();
        if (e is Map) return (e['name']?.toString() ?? '').trim();
        return '';
      })
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

  for (final program in programs) {
    certs.add(
      PGCertification(
        label: program,
        verified: true,
        caption: 'Third-party verified',
      ),
    );
  }

  if (certs.isEmpty) return const SizedBox.shrink();
  return PGCertificationSection(certifications: certs);
}

/// True when the nested `gmp` object carries a real certification /
/// compliance / program signal. Bare `claimed` (manufacturer self-assertion)
/// is deliberately excluded so the "GMP Certified" badge is not overstated.
bool _gmpCertified(Map<String, dynamic> certificationDetail) {
  final gmp = certificationDetail.safeMap('gmp');
  return gmp.safeBool('gmp_certified_or_compliant') ||
      gmp.safeBool('nsf_gmp') ||
      gmp.safeBool('fda_registered');
}
