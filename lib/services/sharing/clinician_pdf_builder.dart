import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/sharing/clinical_profile_labels.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';
import 'package:pharmaguide/services/medications/medication_class_bridge.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/timing_guidance_builder.dart';

class ClinicianPdfBuilder {
  const ClinicianPdfBuilder({this.compress = true});

  final bool compress;

  /// Short, stable identifier printed on every page.
  ///
  /// Derived only from the generation instant so the same report always
  /// carries the same id: pages separated from the set stay attributable, and
  /// a clinician can quote one token back. It is not a patient identifier.
  static String reportIdFor(DateTime generatedAt) {
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

  Future<Uint8List> build({
    required UserProfile? profile,
    required List<UserStacksLocalData> stack,
    required StackIntelligence intelligence,
    required StackSafetyReport safetyReport,
    required List<DepletionMatch> depletions,
    MedNutrientLoadStatus depletionStatus = MedNutrientLoadStatus.loaded,
    String? clinicalDataVersion,
    String? clinicalDataHash,
    String? productCatalogVersion,
    String? interactionRulesVersion,
    Map<String, MedicationIdentityStatus> medicationIdentityStatuses =
        const <String, MedicationIdentityStatus>{},
    Map<String, String> conditionLabels = const <String, String>{},
    required DateTime generatedAt,
    Uint8List? logoBytes,
    Uint8List? regularFontBytes,
    Uint8List? mediumFontBytes,
  }) async {
    final doc = pw.Document(
      compress: compress,
      title: 'PharmaGuide Medication & Supplement Review',
      author: 'PharmaGuide',
      creator: 'PharmaGuide',
      subject: 'Patient-generated medication and supplement summary',
    );

    final logo = _decodeLogo(logoBytes);
    final theme = _Theme(
      regularFont: _decodeFont(regularFontBytes),
      mediumFont: _decodeFont(mediumFontBytes),
    );

    final reportId = reportIdFor(generatedAt);
    final medications = stack
        .where((e) => e.type == 'medication')
        .toList(growable: false);
    final supplements = stack
        .where((e) => e.type == 'supplement')
        .toList(growable: false);

    // A declared drug class that no saved medication resolves means the
    // checks needing an exact medication ran at class granularity or not at
    // all. Testing `medications.isEmpty` marked this resolved as soon as ANY
    // medication existed — an unrelated aspirin silenced a missing ACE
    // inhibitor.
    //
    // Coverage is decided by `MedicationClassBridge.profileGateIdsForClasses`,
    // the single crosswalk between the medication `class:*` vocab and the
    // clinician-signed profile vocab. It is deliberately seeded with one
    // mapping and FAILS OPEN, so an unmapped medication class does not match
    // a differently-named profile id and the banner still fires. That is the
    // safe direction: over-warn, never silently clear.
    final declaredClasses = _decodeJsonStringList(
      profile?.drugClasses,
    ).map(_bareClassId).where((id) => id.isNotEmpty).toSet();
    final resolvedClasses = MedicationClassBridge.profileGateIdsForClasses(
      medications.expand(
        (medication) => _decodeJsonStringList(medication.drugClassesCol),
      ),
    ).map(_bareClassId).toSet();
    final unresolvedClasses = declaredClasses.difference(resolvedClasses);
    final unresolvedClassLabels = clinicalProfileLabels(
      unresolvedClasses.toList(growable: false),
      ClinicalProfileField.drugClass,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 42),
        footer: (context) => _footer(context, theme, reportId, generatedAt),
        // Sections are spread, not nested: MultiPage can only break between
        // the widgets it is handed.
        build: (context) => [
          _header(theme, logo, generatedAt, reportId),
          ..._reviewStatusSection(theme, unresolvedClassLabels),
          ..._about(theme),
          ..._profileSection(theme, profile, conditionLabels),
          ..._medicationSection(
            theme,
            medications,
            medicationIdentityStatuses: medicationIdentityStatuses,
          ),
          ..._supplementSection(
            theme,
            supplements,
            safetyReport.nutrientStatuses,
          ),
          ..._warningsSection(
            theme,
            intelligence,
            safetyReport,
            classOnlyReconciliation: unresolvedClassLabels.isNotEmpty,
          ),
          ..._nutrientSection(theme, safetyReport.nutrientStatuses),
          ..._timingSection(theme, safetyReport.timingOptimizations),
          ..._depletionSection(theme, depletions, depletionStatus),
          ..._questionsSection(theme),
          ..._limitations(theme),
          // Provenance is an appendix. It described artifact versions while
          // occupying the space a clinician needs for the patient's lists.
          ..._clinicalDataSection(
            theme,
            version: clinicalDataVersion,
            contentHash: clinicalDataHash,
            productCatalogVersion: productCatalogVersion,
            interactionRulesVersion: interactionRulesVersion,
            reportId: reportId,
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.ImageProvider? _decodeLogo(Uint8List? logoBytes) {
    if (logoBytes == null || logoBytes.isEmpty) return null;
    try {
      return pw.MemoryImage(logoBytes);
    } on Object {
      return null;
    }
  }

  pw.Font? _decodeFont(Uint8List? fontBytes) {
    if (fontBytes == null || fontBytes.isEmpty) return null;
    try {
      return pw.Font.ttf(ByteData.sublistView(fontBytes));
    } on Object {
      return null;
    }
  }

  pw.Widget _header(
    _Theme theme,
    pw.ImageProvider? logo,
    DateTime generatedAt,
    String reportId,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 18),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: theme.border)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null)
            pw.Container(
              width: 38,
              height: 38,
              margin: const pw.EdgeInsets.only(right: 12),
              child: pw.Image(logo),
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('PharmaGuide', style: theme.brand),
                pw.SizedBox(height: 4),
                pw.Text('Medication & Supplement Review', style: theme.title),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Generated ${_formatDate(generatedAt)} - '
                  'Report $reportId - For clinician review',
                  style: theme.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Leading banner for a report whose patient input is known to be partial.
  ///
  /// Empty when there is nothing to reconcile, so a complete report gains no
  /// standing noise and the banner keeps its signal value.
  List<pw.Widget> _reviewStatusSection(
    _Theme theme,
    List<String> unresolvedClassLabels,
  ) {
    if (unresolvedClassLabels.isEmpty) return const <pw.Widget>[];
    return [
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 18),
        padding: const pw.EdgeInsets.all(11),
        decoration: pw.BoxDecoration(
          color: theme.warningBg,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: theme.warningBorder),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Review status: Partial - medication reconciliation required',
              style: theme.bodyBold,
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              _clean(
                'No entered medication resolves this declared medication '
                'class: ${unresolvedClassLabels.join(', ')}. Medication and '
                'medication-nutrient checks are class-only or did not run for '
                'it. This is not an all-clear - an absent finding may mean the '
                'check could not run. Confirm the medication name, strength, '
                'dose, route, and schedule before relying on this report.',
              ),
              style: theme.body,
            ),
          ],
        ),
      ),
    ];
  }

  List<pw.Widget> _about(_Theme theme) {
    return _section(theme, 'About this report', [
      pw.Text(
        _clean(
          'This report summarizes supplements, medications, nutrient totals, timing guidance, and safety signals reported in the user\'s PharmaGuide stack. Generated entirely on this device; PharmaGuide does not upload or store this report on a server.',
        ),
        style: theme.body,
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        'Educational summary, not medical advice. It is not an EHR medication reconciliation or a substitute for clinician judgment.',
        style: theme.body,
      ),
    ]);
  }

  List<pw.Widget> _profileSection(
    _Theme theme,
    UserProfile? profile,
    Map<String, String> conditionLabels,
  ) {
    final rows = <(String, String)>[];

    void addOptional(String label, String? value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) return;
      rows.add((label, trimmed));
    }

    // Conditions, medication classes, and allergies are always stated. A
    // missing row cannot be distinguished from "none", and for allergies that
    // ambiguity is the dangerous one.
    void addRequired(
      String label,
      String? raw,
      ClinicalProfileField field, {
      Map<String, String> labels = const <String, String>{},
    }) {
      final values = clinicalProfileLabels(
        _decodeJsonStringList(raw),
        field,
        conditionLabels: labels,
      );
      rows.add((label, values.isEmpty ? 'Not entered' : values.join(', ')));
    }

    addOptional('Age', profile?.ageBracket);
    addOptional('Sex', profile?.sex);
    addRequired(
      'Conditions',
      profile?.conditions,
      ClinicalProfileField.condition,
      labels: conditionLabels,
    );
    addRequired(
      'Medication classes',
      profile?.drugClasses,
      ClinicalProfileField.drugClass,
    );
    addRequired(
      'Allergies/intolerances',
      profile?.allergens,
      ClinicalProfileField.allergen,
    );
    final goals = clinicalProfileLabels(
      _decodeJsonStringList(profile?.goals),
      ClinicalProfileField.goal,
    );
    if (goals.isNotEmpty) rows.add(('Goals', goals.join(', ')));

    return _section(theme, 'Patient profile', [_fieldTable(theme, rows)]);
  }

  List<pw.Widget> _medicationSection(
    _Theme theme,
    List<UserStacksLocalData> medications, {
    Map<String, MedicationIdentityStatus> medicationIdentityStatuses =
        const <String, MedicationIdentityStatus>{},
  }) {
    if (medications.isEmpty) {
      return _section(theme, 'Medications', [
        _dataTable(
          theme,
          headers: const ['Medication', 'Status'],
          widths: const [pw.FlexColumnWidth(3), pw.FlexColumnWidth(5)],
          rows: [
            [
              _cell(theme, 'Not entered'),
              _cell(
                theme,
                'Reconciliation required - no medication was entered in the '
                'app, so this is not a statement that none are taken.',
              ),
            ],
          ],
        ),
      ]);
    }

    return _section(theme, 'Medications (${medications.length})', [
      _dataTable(
        theme,
        headers: const [
          'Medication',
          'Dose and frequency',
          'Identity coverage',
        ],
        widths: const [
          pw.FlexColumnWidth(2.6),
          pw.FlexColumnWidth(2.2),
          pw.FlexColumnWidth(3.8),
        ],
        rows: [
          for (final item in medications)
            [
              _cell(theme, item.name),
              _cell(theme, _medicationSchedule(item)),
              _cell(
                theme,
                _identityCoverageLabel(medicationIdentityStatuses[item.id]),
              ),
            ],
        ],
      ),
    ]);
  }

  List<pw.Widget> _supplementSection(
    _Theme theme,
    List<UserStacksLocalData> supplements,
    List<NutrientStatus> nutrientStatuses,
  ) {
    if (supplements.isEmpty) {
      return _section(theme, 'Supplements', [
        _dataTable(
          theme,
          headers: const ['Supplement', 'Status'],
          widths: const [pw.FlexColumnWidth(3), pw.FlexColumnWidth(5)],
          rows: [
            [_cell(theme, 'Not entered'), _cell(theme, 'None in this stack.')],
          ],
        ),
      ]);
    }

    // A product that reached no nutrient total is a coverage finding, and it
    // is invisible if the report only lists names.
    //
    // But "excluded" is not the same as "unmapped". `compoundFormDuplicate`
    // and `declaredTotalDuplicate` are deliberate anti-double-counting
    // exclusions — the label IS represented, it is simply not summed twice.
    // Counting only `contributions` printed "label not represented in totals"
    // for a fully characterized product, which on a clinician document reads
    // as an accusation against a product that is fine.
    final mappedNutrients = <String, Set<String>>{};
    final countedElsewhere = <String>{};
    final unusableRows = <String>{};
    for (final status in nutrientStatuses) {
      for (final contribution in status.total.contributions) {
        final id = contribution.stackEntryId.trim();
        if (id.isEmpty) continue;
        (mappedNutrients[id] ??= <String>{}).add(status.total.canonicalId);
      }
      for (final excluded in status.total.excludedContributions) {
        final id = excluded.contribution.stackEntryId.trim();
        if (id.isEmpty) continue;
        switch (excluded.reason) {
          case NutrientExclusionReason.compoundFormDuplicate:
          case NutrientExclusionReason.declaredTotalDuplicate:
            countedElsewhere.add(id);
          case NutrientExclusionReason.missingUnit:
          case NutrientExclusionReason.notProvidedUnit:
          case NutrientExclusionReason.unsupportedUnit:
          case NutrientExclusionReason.unitConflict:
          case NutrientExclusionReason.skippedByPipeline:
            unusableRows.add(id);
        }
      }
    }

    String coverageLabel(String stackEntryId) {
      final count = mappedNutrients[stackEntryId]?.length ?? 0;
      if (count > 0) {
        return count == 1 ? 'One nutrient counted' : '$count nutrients counted';
      }
      // A real coverage gap outranks a benign de-duplication: reporting only
      // the benign reason would hide the unusable row entirely.
      if (unusableRows.contains(stackEntryId)) {
        return 'Not counted - a label amount used an unusable unit';
      }
      if (countedElsewhere.contains(stackEntryId)) {
        return 'Counted within another nutrient row on this label';
      }
      return 'Nothing counted from this label';
    }

    // A partly-mapped product still has a gap worth naming.
    List<String> coverageNotes(String stackEntryId) => <String>[
      if ((mappedNutrients[stackEntryId]?.length ?? 0) > 0 &&
          unusableRows.contains(stackEntryId))
        'One label amount used an unusable unit and was not counted.',
      if (countedElsewhere.contains(stackEntryId) &&
          unusableRows.contains(stackEntryId))
        'A duplicate form row was also excluded to avoid double-counting.',
    ];

    return _section(theme, 'Supplements (${supplements.length})', [
      _dataTable(
        theme,
        headers: const ['Supplement', 'Nutrients counted in totals'],
        widths: const [pw.FlexColumnWidth(4), pw.FlexColumnWidth(4.5)],
        rows: [
          for (final item in supplements)
            [
              _cell(theme, item.name),
              _noteCell(theme, coverageLabel(item.id), coverageNotes(item.id)),
            ],
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        _clean(
          'Amounts come from the verified product label, not from free-text '
          'entries. See Nutrient totals for per-product contributions.',
        ),
        style: theme.caption,
      ),
    ]);
  }

  List<pw.Widget> _clinicalDataSection(
    _Theme theme, {
    required String? version,
    required String? contentHash,
    required String? productCatalogVersion,
    required String? interactionRulesVersion,
    required String reportId,
  }) {
    String orUnavailable(String? value) {
      final trimmed = value?.trim() ?? '';
      return trimmed.isEmpty ? 'Unavailable' : trimmed;
    }

    return _section(theme, 'Clinical data provenance', [
      // Deliberately excludes the content hash (engineering forensics a
      // clinician cannot act on) and the medication-nutrient artifact state,
      // which the Medication-nutrient section already states in its own words
      // whenever it is unavailable or running on a fallback.
      _fieldTable(theme, [
        ('Report ID', reportId),
        ('Clinical data version', orUnavailable(version)),
        ('Product catalog version', orUnavailable(productCatalogVersion)),
        ('Interaction rules version', orUnavailable(interactionRulesVersion)),
      ]),
    ]);
  }

  // The "Stack summary" section was removed deliberately. It counted the same
  // findings that are listed in full immediately below it, and every count had
  // to carry an "- incomplete" caveat whenever a check had not run — which
  // read as a finding in its own right. A count that needs a caveat is worse
  // than no count. Contraindicated / banned / recalled states are not lost:
  // they arrive as issues and render in "Needs attention".

  List<pw.Widget> _warningsSection(
    _Theme theme,
    StackIntelligence intelligence,
    StackSafetyReport safetyReport, {
    required bool classOnlyReconciliation,
  }) {
    final signals = orderedSignalsFrom(safetyReport);
    final representedHeadlines = _representedIssueHeadlines(signals);
    final remainingIssues = _sortedIssues(
      intelligence.issues
          .where(
            (issue) => !representedHeadlines.contains(issue.headline.trim()),
          )
          .toList(growable: false),
    );
    // An empty warning list means "nothing found" ONLY when every check ran.
    // `checksIncomplete` (a safety subsystem failed) and `coverageIncomplete`
    // (a label fell below the mapped-coverage trust floor) both mean an
    // absent warning may be an unrun check. The app hedges on exactly these
    // two flags; the clinician report must not assert what the app declines
    // to assert. Same contract as the depletion section below.
    final incompleteNotices = _incompleteCheckNotices(
      theme,
      intelligence,
      safetyReport,
      classOnlyReconciliation: classOnlyReconciliation,
    );
    if (signals.isEmpty && remainingIssues.isEmpty) {
      return _section(theme, 'Needs attention', [
        if (incompleteNotices.isEmpty)
          _line(theme, 'No stack warnings in the current snapshot.')
        else
          ...incompleteNotices,
      ]);
    }

    // Recall/banned and other hard issues originate outside
    // StackSafetyReport. Keep them ahead of the rich typed blocks; otherwise a
    // single interaction signal could hide a release-blocking recall.
    final attentionSignals = signals
        .where(
          (signal) =>
              signal.consumerDisposition == ConsumerDisposition.block ||
              signal.consumerDisposition == ConsumerDisposition.review,
        )
        .toList(growable: false);
    final goodToKnowSignals = signals
        .where(
          (signal) =>
              signal.consumerDisposition == ConsumerDisposition.goodToKnow,
        )
        .toList(growable: false);
    final attentionIssues = remainingIssues
        .where((issue) => issue.severity.isHard || issue.severity.isActionable)
        .toList(growable: false);
    final informationalIssues = remainingIssues
        .where(
          (issue) => !issue.severity.isHard && !issue.severity.isActionable,
        )
        .toList(growable: false);

    return [
      ..._section(theme, 'Needs attention', [
        // Ahead of the findings: a partial list must be labeled partial
        // before it is read, not after.
        ...incompleteNotices,
        ...attentionIssues.map(
          (issue) => _severityLine(theme, issue.severity.label, issue.headline),
        ),
        ...attentionSignals.map(
          (signal) => _clinicalSignalBlock(theme, signal),
        ),
      ]),
      ..._section(theme, 'Good to know', [
        ...goodToKnowSignals.map(
          (signal) => _clinicalSignalBlock(theme, signal),
        ),
        ...informationalIssues.map(
          (issue) => _informationLine(theme, issue.headline),
        ),
      ]),
    ];
  }

  /// Hedge lines for a report whose checks did not all run. Empty when the
  /// analysis was complete, so a healthy report gains no noise.
  List<pw.Widget> _incompleteCheckNotices(
    _Theme theme,
    StackIntelligence intelligence,
    StackSafetyReport safetyReport, {
    required bool classOnlyReconciliation,
  }) {
    return <pw.Widget>[
      // An unresolved declared drug class is a missing INPUT, not a failed
      // subsystem, so none of the flags below catch it — yet it means the
      // medication checks may never have run. Without this, the banner would
      // declare the review partial while this section declared an all-clear.
      if (classOnlyReconciliation)
        _line(
          theme,
          'Medication checks could not fully run: a declared medication '
          'class has no matching entered medication. This is not an '
          'all-clear.',
        ),
      if (intelligence.analysisIncomplete &&
          !safetyReport.checksIncomplete &&
          !safetyReport.coverageIncomplete)
        _line(
          theme,
          'At least one safety check could not be completed when this report '
          'was generated. This is not an all-clear.',
        ),
      if (safetyReport.checksIncomplete)
        _line(
          theme,
          'Some safety checks could not be completed when this report was '
          'generated. This is not an all-clear - an absent warning may mean '
          'the check did not run.',
        ),
      if (safetyReport.coverageIncomplete)
        _line(
          theme,
          'At least one product label could not be fully analyzed, so its '
          'ingredients may not have reached every check. This is not an '
          'all-clear.',
        ),
    ];
  }

  Set<String> _representedIssueHeadlines(List<ClinicalSignal> signals) {
    final headlines = <String>{};
    for (final signal in signals) {
      switch (signal.payload) {
        case InteractionPayload(:final result):
          headlines.add(result.mechanism.trim());
        case MedicationProfilePayload(:final warning):
          headlines.add(
            '${warning.medicationName}: ${warning.headline}'.trim(),
          );
        case CumulativeExposurePayload(:final status):
          final warning = status.warning;
          if (warning == null && status.tier != NutrientTier.exceedsUl) {
            continue;
          }
          final hasUpperLimitDetail =
              status.ul != null && status.pctOfUl != null;
          headlines.add(
            status.tier == NutrientTier.exceedsUl && hasUpperLimitDetail
                ? StackSafetyReport.nutrientUpperLimitSummary(status)
                : warning!.trim(),
          );
        case MedicationNutrientPayload():
          break;
        case TimingSeparationPayload():
          // Timing separations are not wired into the aggregator until the unified Clinical Guidance work lands, so this cannot arrive yet. The adapter exists now on purpose: it is the shape the rule audit is written against. Asserted unreachable by clinical_signal_timing_adapter_test.dart. Timing already has its own section in this report.
          break;
      }
    }
    headlines.remove('');
    return headlines;
  }

  pw.Widget _clinicalSignalBlock(_Theme theme, ClinicalSignal signal) {
    final detail = <pw.Widget>[
      if (signal.consumerDisposition == ConsumerDisposition.goodToKnow)
        _informationLine(theme, signal.title)
      else
        _severityLine(theme, signal.clinicalSeverity.label, signal.title),
    ];

    switch (signal.payload) {
      case InteractionPayload(:final result):
        detail.add(
          _line(
            theme,
            'Evidence: ${_evidenceLabel(result.evidenceLevel.wireId)}',
          ),
        );
        if (result.mechanism.trim().isNotEmpty) {
          detail.add(_line(theme, 'Mechanism: ${result.mechanism.trim()}'));
        }
        if (result.management.trim().isNotEmpty) {
          detail.add(_line(theme, 'Management: ${result.management.trim()}'));
        }
      case MedicationProfilePayload(:final warning):
        if (warning.body.trim().isNotEmpty) {
          detail.add(_line(theme, 'Clinical context: ${warning.body.trim()}'));
        }
      case CumulativeExposurePayload():
        if (signal.body.trim().isNotEmpty) {
          detail.add(_line(theme, 'Clinical context: ${signal.body.trim()}'));
        }
      case MedicationNutrientPayload():
        // Medication-nutrient matches are rendered in their dedicated section.
        break;
      case TimingSeparationPayload():
        // Timing separations are not wired into the aggregator until the unified Clinical Guidance work lands, so this cannot arrive yet. The adapter exists now on purpose: it is the shape the rule audit is written against. Asserted unreachable by clinical_signal_timing_adapter_test.dart. Timing already has its own section in this report.
        break;
    }

    for (final url in signal.sourceUrls.where((url) => url.trim().isNotEmpty)) {
      detail.add(_line(theme, 'Source: ${url.trim()}'));
    }

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: detail,
      ),
    );
  }

  List<pw.Widget> _nutrientSection(
    _Theme theme,
    List<NutrientStatus> statuses,
  ) {
    if (statuses.isEmpty) return const <pw.Widget>[];

    final sorted = [...statuses]
      ..sort((a, b) {
        final warn = (b.shouldWarn ? 1 : 0).compareTo(a.shouldWarn ? 1 : 0);
        if (warn != 0) return warn;
        return (b.pctOfUl ?? b.pctOfRda ?? 0).compareTo(
          a.pctOfUl ?? a.pctOfRda ?? 0,
        );
      });

    return _section(theme, 'Nutrient totals', [
      _dataTable(
        theme,
        headers: const [
          'Nutrient',
          'Amount',
          '% of target',
          '% of UL',
          'Status',
          'Sources',
        ],
        // "Not comparable" sets the floor for the UL column; a narrower
        // column breaks it mid-word.
        widths: const [
          pw.FlexColumnWidth(2.0),
          pw.FlexColumnWidth(2.0),
          pw.FlexColumnWidth(1.5),
          pw.FlexColumnWidth(1.5),
          pw.FlexColumnWidth(2.5),
          pw.FlexColumnWidth(2.2),
        ],
        rows: [
          for (final status in sorted)
            [
              _cell(theme, status.total.displayName),
              _cell(theme, _amountCell(status)),
              _cell(theme, _targetCell(status)),
              // A UL exists but the label's form cannot support an honest
              // comparison: print the reason, never a fabricated percentage.
              _cell(
                theme,
                _isUnquantified(status)
                    ? '-'
                    : status.ulAssessmentIndeterminate
                    ? 'Not comparable'
                    : status.pctOfUl == null
                    ? '-'
                    : '${_formatNumber(status.pctOfUl!)}%',
              ),
              _noteCell(
                theme,
                // A tier label promises a comparison that an unquantified row
                // cannot support.
                _isUnquantified(status)
                    ? 'No usable label amount'
                    : _nutrientTierLabel(status.tier),
                _comparatorCaveats(status),
              ),
              _cell(theme, _contributionSummary(status)),
            ],
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        _clean(
          'Totals are supplement-only and exclude food, beverages, and '
          'fortified products. Targets are the reference intake matched to '
          'this profile; substances with no established reference intake show '
          'an amount only and are not assessed for adequacy.',
        ),
        style: theme.caption,
      ),
    ]);
  }

  /// Uncertainty the UL checker already recorded on the status.
  ///
  /// These flags exist precisely because the comparison is weaker than it
  /// looks. Dropping them presents a fallback demographic's target, or a
  /// deliberately least-restrictive upper limit, as if it were this patient's.
  List<String> _comparatorCaveats(NutrientStatus status) => <String>[
    if (status.rdaIsBaseline)
      'Target is a generic adult baseline, not profile-matched.',
    if (status.ulIsFallback)
      'Upper limit is a non-personalized fallback value.',
    if (status.ulAssessmentIndeterminate)
      'Upper-limit comparison not possible for this label form.',
  ];

  String _contributionSummary(NutrientStatus status) {
    final names = <String>[];
    for (final contribution in status.total.contributions) {
      final name = contribution.productName.trim();
      if (name.isEmpty || names.contains(name)) continue;
      names.add(name);
    }
    return names.isEmpty ? '-' : names.join(', ');
  }

  List<pw.Widget> _timingSection(
    _Theme theme,
    List<TimingOptimization> optimizations,
  ) {
    final guidance = const TimingGuidanceBuilder().build(optimizations);
    if (guidance.products.isEmpty && guidance.issues.isEmpty) {
      return const <pw.Widget>[];
    }

    // The app card and this report must agree on the CONCLUSION. They need not
    // agree on detail: the clinician copy additionally carries the audit trail —
    // which bottle, the exact interval, the evidence tier and what kind of
    // source it came from — so a reviewer can check the reasoning rather than
    // take the recommendation on trust.
    final rows = <List<pw.Widget>>[
      for (final product in guidance.products)
        for (final item in [
          ...product.importantSeparation,
          ...product.howToTake,
          ...product.optional,
        ])
          [
            _cell(theme, product.productName),
            _cell(theme, _categoryLabel(item.category)),
            _cell(theme, _instructionFor(item)),
            // Reuse the report's own evidence vocabulary rather than the
            // model's UI label, so one report never names the same tier two
            // ways. Authority is printed beside it, never merged into it: a
            // mechanism paper and a drug label can share a tier.
            _cell(
              theme,
              '${_evidenceLabel(item.evidenceLevel.wireId)} - '
              '${item.sourceAuthority.label}',
            ),
          ],
    ];

    return _section(theme, 'Timing guidance', [
      if (rows.isNotEmpty)
        _dataTable(
          theme,
          headers: const ['Product', 'Type', 'Instruction', 'Evidence'],
          widths: const [
            pw.FlexColumnWidth(2.0),
            pw.FlexColumnWidth(1.4),
            pw.FlexColumnWidth(3.4),
            pw.FlexColumnWidth(1.7),
          ],
          rows: rows,
        ),
      if (rows.isEmpty && guidance.canAssertNoFindings)
        _line(
          theme,
          'No important timing findings identified for the products '
          'successfully assessed.',
        ),
      // Unresolved inputs belong in a clinical report even when the app stays
      // silent about them: a reader must be able to tell "checked, nothing
      // found" from "could not check".
      for (final issue in guidance.issues) _line(theme, _issueSentence(issue)),
    ]);
  }

  static String _categoryLabel(TimingCategory category) => switch (category) {
    TimingCategory.importantSeparation => 'Important',
    TimingCategory.howToTake => 'Administration',
    TimingCategory.optional => 'Optional',
  };

  /// The authored advice plus the exact structured interval behind it.
  static String _instructionFor(TimingOptimization item) {
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

  static String _issueSentence(TimingEvaluationIssue issue) => switch (issue) {
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

  List<pw.Widget> _depletionSection(
    _Theme theme,
    List<DepletionMatch> depletions,
    MedNutrientLoadStatus status,
  ) {
    // An unavailable analysis must be stated, never silently omitted: a clinician
    // cannot otherwise tell "none found" from "the check did not run".
    if (status == MedNutrientLoadStatus.unavailable) {
      return _section(theme, 'Medication-nutrient relationships', [
        _line(
          theme,
          'Medication-nutrient analysis was unavailable when this '
          'report was generated. This is not evidence that no interactions '
          'exist - the check could not run.',
        ),
      ]);
    }
    final statusLines = status == MedNutrientLoadStatus.fallbackLoaded
        ? <pw.Widget>[
            _line(
              theme,
              'Partial medication-nutrient analysis: a fallback reference '
              'artifact was used. Review these notes in that context.',
            ),
          ]
        : const <pw.Widget>[];
    if (depletions.isEmpty && statusLines.isNotEmpty) {
      return _section(theme, 'Medication-nutrient relationships', statusLines);
    }
    if (depletions.isEmpty) return const <pw.Widget>[];

    return _section(theme, 'Medication-nutrient relationships', [
      ...statusLines,
      ...depletions.map((match) {
        final headline = match.alertHeadline?.trim().isNotEmpty == true
            ? match.alertHeadline!.trim()
            : '${match.drugDisplayName} may affect ${match.nutrientName}';
        final rows = <pw.Widget>[
          _line(theme, headline),
          _line(
            theme,
            'Relationship: ${medNutrientRelationshipLabel(match.depletionType)}',
          ),
          _line(theme, 'Evidence: ${_evidenceLabel(match.evidenceLevel)}'),
        ];
        if (match.mechanism.trim().isNotEmpty) {
          rows.add(_line(theme, 'Mechanism: ${match.mechanism.trim()}'));
        }
        final impact = match.clinicalImpact?.trim() ?? '';
        if (impact.isNotEmpty) {
          rows.add(_line(theme, 'Clinical impact: $impact'));
        }
        if (match.recommendation.trim().isNotEmpty) {
          rows.add(
            _line(theme, 'Recommendation: ${match.recommendation.trim()}'),
          );
        }
        final tip = match.monitoringTipShort?.trim() ?? '';
        if (tip.isNotEmpty) {
          rows.add(_line(theme, 'Monitoring: $tip'));
        }
        for (final url in match.sourceUrls.where(
          (url) => url.trim().isNotEmpty,
        )) {
          rows.add(_line(theme, 'Source: ${url.trim()}'));
        }
        return pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: rows,
          ),
        );
      }),
    ]);
  }

  List<pw.Widget> _limitations(_Theme theme) {
    return _section(theme, 'Limitations', [
      _line(
        theme,
        'This is patient-generated health data based on the user\'s current in-app stack.',
      ),
      _line(
        theme,
        'It may omit prescriptions, over-the-counter products, doses, labs, diagnoses, or changes not entered by the user.',
      ),
      _line(
        theme,
        'Do not use this report alone to start, stop, or change therapy.',
      ),
    ]);
  }

  List<pw.Widget> _questionsSection(_Theme theme) {
    return _section(theme, 'Questions to discuss', [
      _line(
        theme,
        'Do any listed combinations require a dose, timing, or therapy change?',
      ),
      _line(
        theme,
        'Are any monitoring tests appropriate based on medication duration, dose, symptoms, or individual risk factors?',
      ),
      _line(
        theme,
        'Are all medications, over-the-counter products, and supplements represented accurately?',
      ),
    ]);
  }

  pw.Widget _footer(
    pw.Context context,
    _Theme theme,
    String reportId,
    DateTime generatedAt,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: theme.border)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          // Repeated per page so a separated sheet stays attributable to one
          // report and one snapshot date.
          pw.Text(
            'PharmaGuide - $reportId - ${_formatDate(generatedAt)}',
            style: theme.footer,
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: theme.footer,
          ),
        ],
      ),
    );
  }

  /// Headerless label/value table for profile, summary, and provenance blocks.
  pw.Widget _fieldTable(_Theme theme, List<(String, String)> rows) {
    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: theme.border, width: 0.5),
        bottom: pw.BorderSide(color: theme.border, width: 0.5),
        top: pw.BorderSide(color: theme.border, width: 0.5),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.4),
        1: pw.FlexColumnWidth(5.6),
      },
      children: [
        for (final (label, value) in rows)
          pw.TableRow(
            children: [_cell(theme, label, bold: true), _cell(theme, value)],
          ),
      ],
    );
  }

  /// Column table whose header row repeats after every page break, so a
  /// continued table is never read against the wrong columns.
  pw.Widget _dataTable(
    _Theme theme, {
    required List<String> headers,
    required List<pw.FlexColumnWidth> widths,
    required List<List<pw.Widget>> rows,
  }) {
    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: theme.border, width: 0.5),
        bottom: pw.BorderSide(color: theme.border, width: 0.5),
      ),
      columnWidths: {for (var i = 0; i < widths.length; i++) i: widths[i]},
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: theme.tableHeaderBg),
          children: [
            for (final header in headers) _cell(theme, header, bold: true),
          ],
        ),
        for (final cells in rows) pw.TableRow(children: cells),
      ],
    );
  }

  pw.Widget _cell(_Theme theme, String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        _clean(text),
        style: bold ? theme.tableHead : theme.tableBody,
      ),
    );
  }

  pw.Widget _noteCell(_Theme theme, String text, List<String> notes) {
    if (notes.isEmpty) return _cell(theme, text);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(_clean(text), style: theme.tableBody),
          for (final note in notes)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(_clean(note), style: theme.tableNote),
            ),
        ],
      ),
    );
  }

  /// A section, flattened into top-level widgets.
  ///
  /// [pw.MultiPage] only breaks *between* the widgets it is given, and only
  /// splits a child that is itself spanning (a [pw.Table] is; a [pw.Container]
  /// wrapping a [pw.Column] is not). Returning a single wrapped Column meant
  /// any section taller than one page could never fit, and MultiPage looped
  /// until it threw PdfTooBigPageException — losing the whole report. A stack
  /// with ~40 nutrient rows is enough to trigger it.
  List<pw.Widget> _section(
    _Theme theme,
    String title,
    Iterable<pw.Widget> children,
  ) {
    final list = children.toList(growable: false);
    if (list.isEmpty) return const <pw.Widget>[];
    return <pw.Widget>[
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 18, bottom: 8),
        child: pw.Text(title.toUpperCase(), style: theme.sectionTitle),
      ),
      ...list,
    ];
  }

  pw.Widget _line(_Theme theme, String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Text(_clean(text), style: theme.body),
    );
  }

  pw.Widget _severityLine(_Theme theme, String label, String text) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: theme.warningBg,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: theme.warningBorder),
      ),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(text: '${_clean(label)}: ', style: theme.bodyBold),
            pw.TextSpan(text: _clean(text), style: theme.body),
          ],
        ),
      ),
    );
  }

  pw.Widget _informationLine(_Theme theme, String text) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: theme.informationBg,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: theme.border),
      ),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(text: 'Good to know: ', style: theme.bodyBold),
            pw.TextSpan(text: _clean(text), style: theme.body),
          ],
        ),
      ),
    );
  }

  /// Profile ids may carry the `class:` prefix; bridge ids always do.
  static String _bareClassId(String raw) {
    final trimmed = raw.trim().toLowerCase();
    return trimmed.startsWith('class:') ? trimmed.substring(6) : trimmed;
  }

  /// Exposure as one coherent quantity.
  ///
  /// `totalAmount` is the MAXIMUM label-directed exposure and `pctOfRda` is
  /// derived from the MINIMUM, so printing them in the same row stated two
  /// different doses as one. A ranged label prints the range on both.
  String _amountCell(NutrientStatus status) {
    final total = status.total;
    if (_isUnquantified(status)) return 'Not quantified';
    if (total.hasDoseRange && total.minimumTotalAmount != null) {
      return '${_formatNumber(total.minimumTotalAmount!)}-'
          '${_formatNumber(total.totalAmount)} ${total.unit}';
    }
    return '${_formatNumber(total.totalAmount)} ${total.unit}';
  }

  /// Nothing reached the sum AND there is no amount to show. Printing "0"
  /// there is a measured absence the report cannot support. A total that
  /// carries an amount without per-product attribution is still quantified —
  /// it simply cannot be sourced, so it keeps its amount and its comparison.
  bool _isUnquantified(NutrientStatus status) =>
      status.total.contributions.isEmpty && status.total.totalAmount == 0;

  String _targetCell(NutrientStatus status) {
    if (_isUnquantified(status)) return '-';
    final minimum = status.pctOfRda;
    if (minimum == null) return '-';
    final maximum = status.maximumPctOfRda;
    if (maximum != null && (maximum - minimum).abs() > 0.05) {
      return '${_formatNumber(minimum)}-${_formatNumber(maximum)}%';
    }
    return '${_formatNumber(minimum)}%';
  }

  List<String> _decodeJsonStringList(String? raw) {
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

  List<StackIssue> _sortedIssues(List<StackIssue> issues) {
    final sorted = issues.indexed
        .map((entry) => _RankedIssue(entry.$2, entry.$1))
        .toList(growable: false);
    sorted.sort((a, b) {
      final severity = b.issue.severity.weight.compareTo(
        a.issue.severity.weight,
      );
      if (severity != 0) return severity;
      return a.ordinal.compareTo(b.ordinal);
    });
    return sorted.map((entry) => entry.issue).toList(growable: false);
  }

  /// Medication dose and schedule as entered.
  ///
  /// Supplement amounts are deliberately absent from the supplement table:
  /// they are owned by the verified product label and the nutrient-total
  /// section. Historical free-text stack fields must not be presented to a
  /// clinician as if they were a validated supplement dose.
  String _medicationSchedule(UserStacksLocalData item) {
    final dosage = (item.dosage ?? '').trim();
    final frequency = (item.frequency ?? '').trim();
    if (dosage.isEmpty && frequency.isEmpty) return 'Not recorded';
    if (frequency.isEmpty) return dosage;
    if (dosage.isEmpty) return frequency;
    return '$dosage, $frequency';
  }

  String _identityCoverageLabel(MedicationIdentityStatus? status) =>
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

  String _nutrientTierLabel(NutrientTier tier) => switch (tier) {
    // Creatine, lutein, ALA and similar have no RDA or AI. Naming the missing
    // standard still frames them against it; state only what is known.
    NutrientTier.noRda =>
      'No daily reference - amount shown for reconciliation',
    NutrientTier.underFifty => 'Below 50% target',
    NutrientTier.adequate => 'Adequate',
    NutrientTier.aboveAdequateNoUl => 'Above target (no upper limit)',
    NutrientTier.abundant => 'Above target',
    NutrientTier.aboveTypical => 'Above typical',
    NutrientTier.approachingUl => 'Approaching upper limit',
    NutrientTier.exceedsUl => 'Exceeds upper limit',
  };

  String _evidenceLabel(String level) => switch (level.trim().toLowerCase()) {
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

  String _formatDate(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  /// Grouped digits, in the label's own unit.
  ///
  /// "5000 mg" invites "is that 5 grams?". Grouping answers it without
  /// restating the dose in a different unit — a reconciliation document must
  /// show what the bottle shows.
  String _formatNumber(num value) {
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

  String _clean(String value) {
    return value
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll('\u2022', '-')
        .replaceAll('\u00b7', '-')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"')
        .replaceAll(RegExp(r'[\u{10000}-\u{10FFFF}]', unicode: true), '');
  }
}

class _RankedIssue {
  const _RankedIssue(this.issue, this.ordinal);

  final StackIssue issue;
  final int ordinal;
}

class _Theme {
  _Theme({this.regularFont, this.mediumFont});

  final pw.Font? regularFont;
  final pw.Font? mediumFont;

  final accent = PdfColor.fromHex('#183B3F');
  final ink = PdfColor.fromHex('#181A1B');
  final muted = PdfColor.fromHex('#5C5F61');
  final subtle = PdfColor.fromHex('#8A8D90');
  final border = PdfColor.fromHex('#E5E2DB');
  final informationBg = PdfColor.fromHex('#F3F6F5');
  final tableHeaderBg = PdfColor.fromHex('#F0EEE8');
  final warningBg = PdfColor.fromHex('#F6F0E2');
  final warningBorder = PdfColor.fromHex('#AD7A24');

  late final brand = pw.TextStyle(
    font: mediumFont,
    color: accent,
    fontSize: 12,
  );

  late final title = pw.TextStyle(font: mediumFont, color: ink, fontSize: 22);

  late final sectionTitle = pw.TextStyle(
    font: mediumFont,
    color: accent,
    fontSize: 10,
    letterSpacing: 1,
  );

  late final body = pw.TextStyle(
    font: regularFont,
    color: ink,
    fontSize: 10.5,
    lineSpacing: 2,
  );
  late final bodyBold = pw.TextStyle(
    font: mediumFont,
    color: ink,
    fontSize: 10.5,
  );
  late final caption = pw.TextStyle(
    font: regularFont,
    color: muted,
    fontSize: 9.5,
  );
  late final tableHead = pw.TextStyle(
    font: mediumFont,
    color: accent,
    fontSize: 9,
  );
  late final tableBody = pw.TextStyle(
    font: regularFont,
    color: ink,
    fontSize: 9.5,
    lineSpacing: 1.5,
  );
  late final tableNote = pw.TextStyle(
    font: regularFont,
    color: muted,
    fontSize: 8,
    lineSpacing: 1,
  );
  late final footer = pw.TextStyle(
    font: regularFont,
    color: subtle,
    fontSize: 8,
  );
}
