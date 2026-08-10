// Shared visual vocabulary for stack safety signals.
//
// The Stack-screen overview card previews the same rows the detail sheet
// renders in full, so the two MUST agree glyph-for-glyph and colour-for-colour.
// A divergent icon between preview and sheet reads as a *different* finding —
// exactly the summary/detail mismatch this vocabulary exists to prevent.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';

/// Glyph for a signal, keyed on payload family rather than severity: the icon
/// answers "what kind of finding is this?" while colour answers "how urgent?".
IconData clinicalSignalIcon(ClinicalSignal signal) => switch (signal.payload) {
  InteractionPayload() => Icons.warning_amber_rounded,
  MedicationProfilePayload() => Icons.medical_information_outlined,
  CumulativeExposurePayload() => Icons.health_and_safety_outlined,
  DoseThresholdPayload() => Icons.speed_rounded,
  RegulatorySafetyPayload() => Icons.policy_outlined,
  MedicationNutrientPayload() => Icons.medical_information_outlined,
  TimingSeparationPayload() => Icons.schedule_rounded,
};

/// Review-surface severity colour. Deliberately coarser than the quick-check
/// detail palette: `avoid` folds into contraindicated and `monitor` into
/// caution, so a scannable list reads as two urgency levels rather than four.
Color clinicalSignalSeverityColor(V2Palette palette, Severity severity) =>
    switch (severity) {
      Severity.contraindicated || Severity.avoid => palette.contraindicated,
      Severity.caution || Severity.monitor => palette.caution,
      Severity.informational => palette.accent,
      Severity.safe => palette.safe,
    };
