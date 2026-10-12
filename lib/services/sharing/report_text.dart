import 'dart:convert';

import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/medications/medication_class_bridge.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';
import 'package:pharmaguide/services/sharing/clinical_profile_labels.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/timing_guidance_builder.dart';

/// Text semantics shared by every stack export (clinician PDF, AI brief).
///
/// A number, a tier label, a caveat or a schedule must read the same in every
/// document a user can produce from one snapshot. These helpers are the single
/// owner of that wording; renderers only lay it out.

/// Short, stable identifier printed on every exported page.
///
/// Derived only from the generation instant so the same snapshot always
/// carries the same id: pages separated from the set stay attributable, and
/// a clinician can quote one token back. It is not a patient identifier.
String stackReportIdFor(DateTime generatedAt) {
  final stamp = generatedAt
      .toUtc()
      .millisecondsSinceEpoch
      .toRadixString(36)
      .toUpperCase();
  final tail = stamp.length <= 6
      ? stamp.padLeft(6, '0')
      : stamp.substring(stamp.length - 6);
  return 'PG-$tail';
}

String formatReportDate(DateTime d) {
  final month = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$month-$day';
}

/// Grouped digits, in the label's own unit.
///
/// "5000 mg" invites "is that 5 grams?". Grouping answers it without
/// restating the dose in a different unit — a reconciliation document must
/// show what the bottle shows.
String formatReportNumber(num value) {
  final fixed = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  final parts = fixed.split('.');
  final negative = parts.first.startsWith('-');
  final digits = negative ? parts.first.substring(1) : parts.first;
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  final whole = negative ? '-$grouped' : '$grouped';
  return parts.length > 1 ? '$whole.${parts[1]}' : whole;
}

/// Normalizes typographic punctuation and strips astral-plane glyphs the PDF
/// fonts cannot shape. Plain-text exports share it so both documents agree.
String cleanReportText(String value) {
  return value
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('•', '-')
      .replaceAll('·', '-')
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll(RegExp(r'[\u{10000}-\u{10FFFF}]', unicode: true), '');
}

List<String> decodeJsonStringList(String? raw) {
  if (raw == null || raw.isEmpty) return const <String>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
  } on Object {
    return const <String>[];
  }
  return const <String>[];
}

String evidenceLevelLabel(String level) => switch (level.trim().toLowerCase()) {
  'established' => 'Established',
  'probable' => 'Probable',
  'moderate' => 'Moderate',
  'limited' => 'Limited',
  'theoretical' => 'Theoretical',
  'no_data' => 'No evidence data',
  'ungraded' => 'Not graded',
  'possible' => 'Possible',
  _ => 'Not graded',
};

String nutrientTierLabel(NutrientTier tier) => switch (tier) {
  // Creatine, lutein, ALA and similar have no RDA or AI. Naming the missing
  // standard still frames them against it; state only what is known.
  NutrientTier.noRda => 'No daily reference - amount shown for reconciliation',
  NutrientTier.underFifty => 'Below 50% target',
  NutrientTier.adequate => 'Adequate',
  NutrientTier.aboveAdequateNoUl => 'Above target (no upper limit)',
  NutrientTier.abundant => 'Above target',
  NutrientTier.aboveTypical => 'Above typical',
  NutrientTier.approachingUl => 'Approaching upper limit',
  NutrientTier.exceedsUl => 'Exceeds upper limit',
};

/// Nothing reached the sum AND there is no amount to show. Printing "0"
/// there is a measured absence the report cannot support. A total that
/// carries an amount without per-product attribution is still quantified —
/// it simply cannot be sourced, so it keeps its amount and its comparison.
bool isNutrientUnquantified(NutrientStatus status) =>
    status.total.contributions.isEmpty && status.total.totalAmount == 0;

/// Exposure as one coherent quantity.
///
/// `totalAmount` is the MAXIMUM label-directed exposure and `pctOfRda` is
/// derived from the MINIMUM, so printing them in the same row stated two
/// different doses as one. A ranged label prints the range on both.
String nutrientAmountText(NutrientStatus status) {
  final total = status.total;
  if (isNutrientUnquantified(status)) return 'Not quantified';
  if (total.hasDoseRange && total.minimumTotalAmount != null) {
    return '${formatReportNumber(total.minimumTotalAmount!)}-'
        '${formatReportNumber(total.totalAmount)} ${total.unit}';
  }
  return '${formatReportNumber(total.totalAmount)} ${total.unit}';
}

String nutrientTargetText(NutrientStatus status) {
  if (isNutrientUnquantified(status)) return '-';
  final minimum = status.pctOfRda;
  if (minimum == null) return '-';
  final maximum = status.maximumPctOfRda;
  if (maximum != null && (maximum - minimum).abs() > 0.05) {
    return '${formatReportNumber(minimum)}-${formatReportNumber(maximum)}%';
  }
  return '${formatReportNumber(minimum)}%';
}

/// A UL exists but the label's form cannot support an honest comparison:
/// print the reason, never a fabricated percentage.
String nutrientUpperLimitText(NutrientStatus status) {
  if (isNutrientUnquantified(status)) return '-';
  if (status.ulAssessmentIndeterminate) return 'Not comparable';
  final pct = status.pctOfUl;
  return pct == null ? '-' : '${formatReportNumber(pct)}%';
}

/// Uncertainty the UL checker already recorded on the status.
///
/// These flags exist precisely because the comparison is weaker than it
/// looks. Dropping them presents a fallback demographic's target, or a
/// deliberately least-restrictive upper limit, as if it were this patient's.
List<String> nutrientComparatorCaveats(NutrientStatus status) => <String>[
  if (status.rdaIsBaseline)
    'Target is a generic adult baseline, not profile-matched.',
  if (status.ulIsFallback) 'Upper limit is a non-personalized fallback value.',
  if (status.ulAssessmentIndeterminate)
    'Upper-limit comparison not possible for this label form.',
];

String nutrientContributionSummary(NutrientStatus status) {
  final names = <String>[];
  for (final contribution in status.total.contributions) {
    final name = contribution.productName.trim();
    if (name.isEmpty || names.contains(name)) continue;
    names.add(name);
  }
  return names.isEmpty ? '-' : names.join(', ');
}

/// Nutrient rows sorted warnings-first, then by exposure.
List<NutrientStatus> sortNutrientStatuses(List<NutrientStatus> statuses) {
  final sorted = [...statuses]
    ..sort((a, b) {
      final warn = (b.shouldWarn ? 1 : 0).compareTo(a.shouldWarn ? 1 : 0);
      if (warn != 0) return warn;
      return (b.pctOfUl ?? b.pctOfRda ?? 0).compareTo(
        a.pctOfUl ?? a.pctOfRda ?? 0,
      );
    });
  return sorted;
}

/// Medication dose and schedule as entered.
///
/// Supplement amounts are deliberately absent from clinician supplement
/// tables: they are owned by the verified product label and the nutrient
/// totals. Historical free-text stack fields must not be presented to a
/// clinician as if they were a validated supplement dose.
String medicationScheduleText(UserStacksLocalData item) {
  final dosage = (item.dosage ?? '').trim();
  final frequency = (item.frequency ?? '').trim();
  if (dosage.isEmpty && frequency.isEmpty) return 'Not recorded';
  if (frequency.isEmpty) return dosage;
  if (dosage.isEmpty) return frequency;
  return '$dosage, $frequency';
}

String medicationIdentityCoverageLabel(MedicationIdentityStatus? status) =>
    switch (status) {
      MedicationIdentityStatus.complete => 'reviewed matching available',
      MedicationIdentityStatus.partial => 'reviewed matching is partial',
      MedicationIdentityStatus.classOnly =>
        'reviewed medication-group matching only',
      MedicationIdentityStatus.exactOnly =>
        'RxNorm identity saved; no reviewed direct or group coverage found',
      MedicationIdentityStatus.unresolved ||
      null => 'matching unresolved; medication checks may be incomplete',
    };

/// Profile ids may carry the `class:` prefix; bridge ids always do.
String bareClassId(String raw) {
  final trimmed = raw.trim().toLowerCase();
  return trimmed.startsWith('class:') ? trimmed.substring(6) : trimmed;
}

/// Declared medication classes that no entered medication resolves.
///
/// Testing `medications.isEmpty` marked this resolved as soon as ANY
/// medication existed — an unrelated aspirin silenced a missing ACE
/// inhibitor. Coverage is decided by
/// `MedicationClassBridge.profileGateIdsForClasses`, the single crosswalk
/// between the medication `class:*` vocab and the clinician-signed profile
/// vocab. It is deliberately seeded with one mapping and FAILS OPEN, so an
/// unmapped medication class does not match a differently-named profile id
/// and the banner still fires. That is the safe direction: over-warn, never
/// silently clear.
List<String> unresolvedDeclaredClassLabels(
  UserProfile? profile,
  List<UserStacksLocalData> medications,
) {
  final declaredClasses = decodeJsonStringList(
    profile?.drugClasses,
  ).map(bareClassId).where((id) => id.isNotEmpty).toSet();
  final resolvedClasses = MedicationClassBridge.profileGateIdsForClasses(
    medications.expand(
      (medication) => decodeJsonStringList(medication.drugClassesCol),
    ),
  ).map(bareClassId).toSet();
  final unresolvedClasses = declaredClasses.difference(resolvedClasses);
  return clinicalProfileLabels(
    unresolvedClasses.toList(growable: false),
    ClinicalProfileField.drugClass,
  );
}

/// Issues by severity (worst first), stable within a severity.
List<StackIssue> sortIssuesBySeverity(List<StackIssue> issues) {
  final ranked = issues.indexed.toList(growable: false)
    ..sort((a, b) {
      final severity = b.$2.severity.weight.compareTo(a.$2.severity.weight);
      if (severity != 0) return severity;
      return a.$1.compareTo(b.$1);
    });
  return ranked.map((entry) => entry.$2).toList(growable: false);
}

/// Headlines of untyped issues that a typed signal already represents, so a
/// finding is never listed twice in one document.
Set<String> representedIssueHeadlines(List<ClinicalSignal> signals) {
  final headlines = <String>{};
  for (final signal in signals) {
    switch (signal.payload) {
      case InteractionPayload(:final result):
        headlines.add(result.mechanism.trim());
      case MedicationProfilePayload(:final warning):
        headlines.add('${warning.medicationName}: ${warning.headline}'.trim());
      case CumulativeExposurePayload(:final status):
        final warning = status.warning;
        if (warning == null && status.tier != NutrientTier.exceedsUl) {
          continue;
        }
        final hasUpperLimitDetail = status.ul != null && status.pctOfUl != null;
        headlines.add(
          status.tier == NutrientTier.exceedsUl && hasUpperLimitDetail
              ? StackSafetyReport.nutrientUpperLimitSummary(status)
              : warning!.trim(),
        );
      case DoseThresholdPayload():
        headlines.add(signal.body.trim());
      case RegulatorySafetyPayload():
        headlines.add(signal.body.trim());
      case MedicationNutrientPayload():
        break;
      case TimingSeparationPayload():
        // Timing separations are not wired into the aggregator until the
        // unified Clinical Guidance work lands. Timing has its own section.
        break;
    }
  }
  headlines.remove('');
  return headlines;
}

/// Per-supplement "what reached the nutrient totals" wording.
///
/// A product that reached no nutrient total is a coverage finding, and it is
/// invisible if the report only lists names. But "excluded" is not the same
/// as "unmapped": `compoundFormDuplicate` and `declaredTotalDuplicate` are
/// deliberate anti-double-counting exclusions — the label IS represented, it
/// is simply not summed twice.
class SupplementNutrientCoverage {
  SupplementNutrientCoverage(List<NutrientStatus> nutrientStatuses) {
    for (final status in nutrientStatuses) {
      for (final contribution in status.total.contributions) {
        final id = contribution.stackEntryId.trim();
        if (id.isEmpty) continue;
        (_mappedNutrients[id] ??= <String>{}).add(status.total.canonicalId);
      }
      for (final excluded in status.total.excludedContributions) {
        final id = excluded.contribution.stackEntryId.trim();
        if (id.isEmpty) continue;
        switch (excluded.reason) {
          case NutrientExclusionReason.compoundFormDuplicate:
          case NutrientExclusionReason.declaredTotalDuplicate:
            _countedElsewhere.add(id);
          case NutrientExclusionReason.missingUnit:
          case NutrientExclusionReason.notProvidedUnit:
          case NutrientExclusionReason.unsupportedUnit:
          case NutrientExclusionReason.unitConflict:
          case NutrientExclusionReason.skippedByPipeline:
            _unusableRows.add(id);
        }
      }
    }
  }

  final Map<String, Set<String>> _mappedNutrients = {};
  final Set<String> _countedElsewhere = {};
  final Set<String> _unusableRows = {};

  String labelFor(String stackEntryId) {
    final count = _mappedNutrients[stackEntryId]?.length ?? 0;
    if (count > 0) {
      return count == 1 ? 'One nutrient counted' : '$count nutrients counted';
    }
    // A real coverage gap outranks a benign de-duplication: reporting only
    // the benign reason would hide the unusable row entirely.
    if (_unusableRows.contains(stackEntryId)) {
      return 'Not counted - a label amount used an unusable unit';
    }
    if (_countedElsewhere.contains(stackEntryId)) {
      return 'Counted within another nutrient row on this label';
    }
    return 'Nothing counted from this label';
  }

  /// A partly-mapped product still has a gap worth naming.
  List<String> notesFor(String stackEntryId) => <String>[
    if ((_mappedNutrients[stackEntryId]?.length ?? 0) > 0 &&
        _unusableRows.contains(stackEntryId))
      'One label amount used an unusable unit and was not counted.',
    if (_countedElsewhere.contains(stackEntryId) &&
        _unusableRows.contains(stackEntryId))
      'A duplicate form row was also excluded to avoid double-counting.',
  ];
}

String timingCategoryLabel(TimingCategory category) => switch (category) {
  TimingCategory.importantSeparation => 'Important',
  TimingCategory.howToTake => 'Administration',
  TimingCategory.optional => 'Optional',
};

/// The authored advice plus the exact structured interval behind it.
String timingInstructionText(TimingOptimization item) {
  final relation = item.relation;
  final detail = switch (relation.type) {
    TimingRelationType.separateFrom ||
    TimingRelationType.separateFromMedications =>
      relation.minimumHours == null
          ? ''
          : ' (minimum ${relation.minimumHours}h separation)',
    TimingRelationType.beforeEvent || TimingRelationType.afterEvent =>
      relation.minimumMinutes == null
          ? ''
          : ' (${relation.minimumMinutes}'
                '${relation.maximumMinutes == null ? '' : '-${relation.maximumMinutes}'}'
                ' minutes)',
    _ => '',
  };
  final prescription = item.involvesMedication
      ? ' Medication schedule remains as prescribed.'
      : '';
  return '${item.advice}$detail$prescription';
}

String timingIssueSentence(TimingEvaluationIssue issue) => switch (issue) {
  ConflictingProductGuidance(:final productName) =>
    '$productName: applicable timing rules conflict for a single product; '
        'no instruction was issued.',
  FormulationUnknown(:final productName) =>
    '$productName: formulation could not be determined, so timing guidance '
        'was not issued.',
  IdentityUnresolved(:final ingredient) =>
    'A timing rule matched $ingredient but could not be tied to a specific '
        'product in the stack.',
  AnalysisUnavailable(:final reason) =>
    'Timing analysis unavailable ($reason). This is not a clean result.',
};
