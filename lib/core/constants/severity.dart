import 'package:flutter/material.dart';

enum Severity {
  contraindicated(
    weight: 5,
    e2cPenalty: -8,
    label: 'BLOCK — Do Not Use',
    color: Color(0xFFDC2626),
  ),
  avoid(weight: 4, e2cPenalty: -5, label: 'AVOID', color: Color(0xFFDC2626)),
  caution(
    weight: 3,
    e2cPenalty: -3,
    label: 'CAUTION',
    color: Color(0xFFF97316),
  ),
  monitor(
    weight: 2,
    e2cPenalty: -1,
    label: 'MONITOR',
    color: Color(0xFFEAB308),
  ),
  // Informational tier — the profile-less rendering of rules whose
  // intrinsic severity is `avoid` or `caution`. Zero E2C penalty: the
  // user's profile hasn't declared the triggering condition / drug
  // class, so the warning is context, not a score hit. Neutral slate
  // color (not alarming, not congratulatory). Emitted by the pipeline
  // as `severity_contextual` under schema v5.2.
  informational(
    weight: 1,
    e2cPenalty: 0,
    label: 'INFO',
    color: Color(0xFF64748B),
  ),
  safe(weight: 0, e2cPenalty: 0, label: 'SAFE', color: Color(0xFF22C55E));

  final int weight;
  final int e2cPenalty;
  final String label;
  final Color color;

  const Severity({
    required this.weight,
    required this.e2cPenalty,
    required this.label,
    required this.color,
  });

  static Severity fromString(String value) {
    return Severity.values.firstWhere(
      (s) => s.name == value.toLowerCase().trim(),
      orElse: () => Severity.safe,
    );
  }
}

enum EvidenceLevel {
  established(label: 'Strong Evidence'),
  probable(label: 'Good Evidence'),
  theoretical(label: 'Theoretical');

  final String label;
  const EvidenceLevel({required this.label});

  static EvidenceLevel fromString(String value) {
    return EvidenceLevel.values.firstWhere(
      (e) => e.name == value.toLowerCase().trim(),
      orElse: () => EvidenceLevel.theoretical,
    );
  }
}
