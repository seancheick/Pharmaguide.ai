import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/sharing/clinical_profile_labels.dart';
import 'package:pharmaguide/services/sharing/report_text.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';
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
  static String reportIdFor(DateTime generatedAt) =>
      stackReportIdFor(generatedAt);

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

    final unresolvedClassLabels = unresolvedDeclaredClassLabels(
      profile,
      medications,
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
                  'Generated ${formatReportDate(generatedAt)} - '
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
              cleanReportText(
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
        cleanReportText(
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
        decodeJsonStringList(raw),
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
      decodeJsonStringList(profile?.goals),
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
              _cell(theme, medicationScheduleText(item)),
              _cell(
                theme,
                medicationIdentityCoverageLabel(
                  medicationIdentityStatuses[item.id],
                ),
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

    final coverage = SupplementNutrientCoverage(nutrientStatuses);

    return _section(theme, 'Supplements (${supplements.length})', [
      _dataTable(
        theme,
        headers: const ['Supplement', 'Nutrients counted in totals'],
        widths: const [pw.FlexColumnWidth(4), pw.FlexColumnWidth(4.5)],
        rows: [
          for (final item in supplements)
            [
              _cell(theme, item.name),
              _noteCell(
                theme,
                coverage.labelFor(item.id),
                coverage.notesFor(item.id),
              ),
            ],
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        cleanReportText(
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
    final representedHeadlines = representedIssueHeadlines(signals);
    final remainingIssues = sortIssuesBySeverity(
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
            'Evidence: ${evidenceLevelLabel(result.evidenceLevel.wireId)}',
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
      case DoseThresholdPayload():
        if (signal.body.trim().isNotEmpty) {
          detail.add(_line(theme, 'Clinical context: ${signal.body.trim()}'));
        }
      case RegulatorySafetyPayload():
        if (signal.body.trim().isNotEmpty) {
          detail.add(_line(theme, 'Regulatory update: ${signal.body.trim()}'));
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

    final sorted = sortNutrientStatuses(statuses);

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
              _cell(theme, nutrientAmountText(status)),
              _cell(theme, nutrientTargetText(status)),
              // A UL exists but the label's form cannot support an honest
              // comparison: print the reason, never a fabricated percentage.
              _cell(theme, nutrientUpperLimitText(status)),
              _noteCell(
                theme,
                // A tier label promises a comparison that an unquantified row
                // cannot support.
                isNutrientUnquantified(status)
                    ? 'No usable label amount'
                    : nutrientTierLabel(status.tier),
                nutrientComparatorCaveats(status),
              ),
              _cell(theme, nutrientContributionSummary(status)),
            ],
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        cleanReportText(
          'Totals are supplement-only and exclude food, beverages, and '
          'fortified products. Targets are the reference intake matched to '
          'this profile; substances with no established reference intake show '
          'an amount only and are not assessed for adequacy.',
        ),
        style: theme.caption,
      ),
    ]);
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
            _cell(theme, timingCategoryLabel(item.category)),
            _cell(theme, timingInstructionText(item)),
            // Reuse the report's own evidence vocabulary rather than the
            // model's UI label, so one report never names the same tier two
            // ways. Authority is printed beside it, never merged into it: a
            // mechanism paper and a drug label can share a tier.
            _cell(
              theme,
              '${evidenceLevelLabel(item.evidenceLevel.wireId)} - '
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
      for (final issue in guidance.issues)
        _line(theme, timingIssueSentence(issue)),
    ]);
  }

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
          _line(theme, 'Evidence: ${evidenceLevelLabel(match.evidenceLevel)}'),
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
            'PharmaGuide - $reportId - ${formatReportDate(generatedAt)}',
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
        cleanReportText(text),
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
          pw.Text(cleanReportText(text), style: theme.tableBody),
          for (final note in notes)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(cleanReportText(note), style: theme.tableNote),
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
      child: pw.Text(cleanReportText(text), style: theme.body),
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
            pw.TextSpan(
              text: '${cleanReportText(label)}: ',
              style: theme.bodyBold,
            ),
            pw.TextSpan(text: cleanReportText(text), style: theme.body),
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
            pw.TextSpan(text: cleanReportText(text), style: theme.body),
          ],
        ),
      ),
    );
  }
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
