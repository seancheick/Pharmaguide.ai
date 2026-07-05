import 'package:flutter/material.dart';

import 'package:pharmaguide/services/crash_reporting_service.dart';

// Display labels — sentence case, softer-tone vocabulary (Sean 2026-04-30).
// "AVOID" felt synonymous with "banned" to users; the word is reserved
// for `contraindicated` shapes (banned / recalled / drug-interaction
// blocks) which rendered as "BLOCK — Do Not Use" pre-fix. The new
// vocabulary keeps the severity hierarchy intact while reading less
// like a courtroom verdict:
//   contraindicated → "Do not use"        (was: "BLOCK — Do Not Use")
//   avoid           → "Not recommended"   (was: "AVOID")
//   caution         → "Use caution"       (was: "CAUTION")
//   monitor         → "Monitor"           (was: "MONITOR")
//   informational   → "Informational"     (was: "INFO")
//   safe            → "Safe"              (was: "SAFE")
// Enum names + ordering are unchanged — only the user-facing display
// label moves.
enum Severity {
  contraindicated(
    weight: 5,
    e2cPenalty: -8,
    label: 'Do not use',
    color: Color(0xFFDC2626),
  ),
  avoid(
    weight: 4,
    e2cPenalty: -5,
    label: 'Not recommended',
    color: Color(0xFFDC2626),
  ),
  caution(
    weight: 3,
    e2cPenalty: -3,
    label: 'Use caution',
    color: Color(0xFFF97316),
  ),
  monitor(
    weight: 2,
    e2cPenalty: -1,
    label: 'Monitor',
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
    label: 'Informational',
    color: Color(0xFF64748B),
  ),
  safe(weight: 0, e2cPenalty: 0, label: 'Safe', color: Color(0xFF22C55E));

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
    final normalized = value.toLowerCase().trim();
    switch (normalized) {
      case 'contraindicated':
      case 'critical':
        return Severity.contraindicated;
      case 'avoid':
      case 'high':
        return Severity.avoid;
      case 'caution':
      case 'moderate':
        return Severity.caution;
      case 'monitor':
      case 'low':
      case 'no_data':
        return Severity.monitor;
      case 'informational':
      case 'info':
        return Severity.informational;
      case 'safe':
        return Severity.safe;
      default:
        // Unknown value — pipeline schema drift. Fail safe to caution,
        // but report it (non-fatal, once per value per session) so
        // drift is detectable instead of silently swallowed.
        if (_reportedUnknownValues.add(normalized)) {
          CrashReportingService().recordError(
            StateError('Unknown severity string: "$normalized"'),
            StackTrace.current,
            hint: 'severity:unknown_value',
          );
        }
        return Severity.caution;
    }
  }

  /// Unknown severity strings already reported this session — keeps
  /// the non-fatal drift report to one Sentry event per value.
  static final Set<String> _reportedUnknownValues = <String>{};

  static bool isKnownString(String value) {
    final normalized = value.toLowerCase().trim();
    switch (normalized) {
      case 'contraindicated':
      case 'critical':
      case 'avoid':
      case 'high':
      case 'caution':
      case 'moderate':
      case 'monitor':
      case 'low':
      case 'no_data':
      case 'informational':
      case 'info':
      case 'safe':
        return true;
      default:
        return false;
    }
  }
}

enum EvidenceLevel {
  established(label: 'Strong Evidence'),
  probable(label: 'Good Evidence'),
  theoretical(label: 'Theoretical'),
  ungraded(label: 'Evidence not graded');

  final String label;
  const EvidenceLevel({required this.label});

  static EvidenceLevel fromString(String value) {
    return EvidenceLevel.values.firstWhere(
      (e) => e.name == value.toLowerCase().trim(),
      orElse: () => EvidenceLevel.ungraded,
    );
  }
}
