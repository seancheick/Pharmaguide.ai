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

  /// A "hard" warning — `contraindicated` or `avoid`. The single source of
  /// truth for the check that was previously hand-copied across ~10 sites
  /// (gates, banners, score caps). A hard warning is NEVER dose-suppressed,
  /// beneficial-suppressed, or otherwise hidden: under-warning is the
  /// unrecoverable direction on a medical surface. Weight-based so a future
  /// tier above `avoid` is hard by construction.
  bool get isHard => weight >= Severity.avoid.weight;

  /// A mid-tier "review-worthy" severity — `caution` or `monitor`. Below
  /// [isHard] (never blocks a verdict) but above `informational` / `safe`
  /// (carries a real, if mild, penalty). Single source of truth for the
  /// warning partition, the review-before-use headline, the fit-display
  /// band, and the fit-score risk reasons — all of which had hand-copied
  /// `== caution || == monitor`.
  bool get isActionable =>
      this == Severity.caution || this == Severity.monitor;

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
  // SP-6 evidence_strength_vocab (strongest -> weakest), plus `ungraded` for a
  // missing / unrecognized value. `wireId` is the exact string the pipeline
  // emits on the interaction_db `evidence_level` column; the enum name stays
  // camelCase (Dart lint) so `no_data` needs the explicit wireId.
  established(label: 'Strong Evidence', wireId: 'established'),
  probable(label: 'Good Evidence', wireId: 'probable'),
  moderate(label: 'Moderate Evidence', wireId: 'moderate'),
  limited(label: 'Limited Evidence', wireId: 'limited'),
  theoretical(label: 'Theoretical', wireId: 'theoretical'),
  noData(label: 'No Evidence Data', wireId: 'no_data'),
  ungraded(label: 'Evidence not graded', wireId: 'ungraded');

  final String label;
  final String wireId;
  const EvidenceLevel({required this.label, required this.wireId});

  /// Parse a pipeline evidence string. Matches the canonical `wireId` (e.g.
  /// `no_data`) or the enum name. An unrecognized / missing value maps to
  /// [ungraded] — NEVER to a higher tier and NEVER to `safe`.
  static EvidenceLevel fromString(String value) {
    final v = value.toLowerCase().trim();
    return EvidenceLevel.values.firstWhere(
      (e) => e.wireId == v || e.name.toLowerCase() == v,
      orElse: () => EvidenceLevel.ungraded,
    );
  }
}
