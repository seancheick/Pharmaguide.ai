import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/constants/schema_ids.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2a_goal_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2c_medical_calculator.dart';
import 'package:pharmaguide/services/warnings/profile_gate_evaluator.dart';
import 'package:pharmaguide/services/warnings/profile_gate_summary_filter.dart';

class FitScoreService {
  final E1DosageCalculator e1;
  final E2aGoalCalculator e2a;
  final E2bAgeCalculator e2b;
  final E2cMedicalCalculator e2c;

  FitScoreService({
    required this.e1,
    required this.e2a,
    required this.e2b,
    required this.e2c,
  });

  FitScoreResult calculate({
    required List<Map<String, dynamic>> nutrients,
    required List<String> productClusters,
    List<String> productGoalMatches = const [],
    double? productGoalMatchConfidence,
    required Map<String, dynamic> interactionSummary,
    String? ageBracket,
    String? sex,
    List<String> userGoals = const [],
    List<String> userConditions = const [],
    List<String> userDrugClasses = const [],
    double mappedCoverage = 1.0,
    // v6.0 profile_gate inputs — when [warnings] is non-empty, the
    // condition_summary / drug_class_summary are filtered against each
    // warning's profile_gate before any penalty is computed. Keeps Fit
    // Score consistent with the product detail screen, which suppresses
    // alerts via the same evaluator.
    //
    // When [warnings] is empty (legacy callers / pre-v6.0 cached blobs),
    // the unfiltered aggregation is used — preserving prior behavior.
    List<InteractionWarning> warnings = const [],
    Set<String> userProfileFlags = const <String>{},
    String? productForm,
    String? nutrientForm,
    num? dosePerDay,
  }) {
    // Apply v6.0 profile_gate filtering once, at the entry point. Both
    // _RelevantMatch (assessment) and E2c (penalty) consume the gated
    // summary so they never disagree about which conditions fire.
    final gatedSummary = warnings.isEmpty
        ? interactionSummary
        : _applyProfileGateFilter(
            interactionSummary: interactionSummary,
            warnings: warnings,
            userConditions: userConditions,
            userDrugClasses: userDrugClasses,
            userProfileFlags: userProfileFlags,
            productForm: productForm,
            nutrientForm: nutrientForm,
            dosePerDay: dosePerDay,
          );

    final e1Score = e1.calculate(
      nutrients: nutrients,
      ageBracket: ageBracket,
      sex: sex,
    );
    final selectedGoalMatches = _selectedGoalMatches(
      userGoals: userGoals,
      productGoalMatches: productGoalMatches,
    );
    final e2aScore = _goalAlignmentScore(
      userGoals: userGoals,
      selectedGoalMatches: selectedGoalMatches,
      productGoalMatchConfidence: productGoalMatchConfidence,
      productClusters: productClusters,
    );
    final e2bScore = e2b.calculate(
      nutrients: nutrients,
      ageBracket: ageBracket,
    );
    final e2cScore = e2c.calculate(
      interactionSummary: gatedSummary,
      userConditions: userConditions,
      userDrugClasses: userDrugClasses,
    );

    final scoreFit20 = e1Score + e2aScore + e2bScore + e2cScore;

    final missingFields = <String>[];
    if (ageBracket == null) missingFields.add('age');
    if (sex == null) missingFields.add('sex');
    if (userGoals.isEmpty) missingFields.add('goals');

    final maxPossible = _maxPossible(
      ageBracket,
      sex,
      userGoals,
      userConditions,
    );
    final assessment = _buildAssessment(
      scoreFit20: scoreFit20,
      maxPossible: maxPossible,
      e1Score: e1Score,
      e2aScore: e2aScore,
      e2bScore: e2bScore,
      interactionSummary: gatedSummary,
      userConditions: userConditions,
      userDrugClasses: userDrugClasses,
      missingFields: missingFields,
      mappedCoverage: mappedCoverage,
      userGoals: userGoals,
      selectedGoalMatches: selectedGoalMatches,
    );

    return FitScoreResult(
      scoreFit20: scoreFit20,
      e1: e1Score,
      e2a: e2aScore,
      e2b: e2bScore,
      e2c: e2cScore,
      missingFields: missingFields,
      maxPossible: maxPossible,
      state: assessment.state,
      reasons: assessment.reasons,
      maxRelevantSeverity: assessment.maxRelevantSeverity,
      mappedCoverage: mappedCoverage,
    );
  }

  /// v6.0 — apply profile_gate filtering to the interaction_summary roll-up.
  ///
  /// Walks every condition_summary / drug_class_summary entry, keeps it
  /// only if at least one warning tagged with that condition/drug-class
  /// fires for the active user profile + product context. Reuses the
  /// shared evaluator at services/warnings/profile_gate_evaluator.dart —
  /// no duplicate gate logic.
  Map<String, dynamic> _applyProfileGateFilter({
    required Map<String, dynamic> interactionSummary,
    required List<InteractionWarning> warnings,
    required List<String> userConditions,
    required List<String> userDrugClasses,
    required Set<String> userProfileFlags,
    String? productForm,
    String? nutrientForm,
    num? dosePerDay,
  }) {
    final userProfile = UserProfile(
      conditions: userConditions.toSet(),
      drugClasses: userDrugClasses.toSet(),
      profileFlags: userProfileFlags,
    );
    final productContext = ProductContext(
      productForm: productForm,
      nutrientForm: nutrientForm,
      dosePerDay: dosePerDay,
    );

    final rawCond = interactionSummary['condition_summary'];
    final rawDrug = interactionSummary['drug_class_summary'];

    final gatedCondition = filterConditionSummaryByProfileGate(
      conditionSummary: rawCond is Map
          ? Map<String, dynamic>.from(rawCond)
          : const <String, dynamic>{},
      warnings: warnings,
      userProfile: userProfile,
      productContext: productContext,
    );
    final gatedDrug = filterDrugClassSummaryByProfileGate(
      drugClassSummary: rawDrug is Map
          ? Map<String, dynamic>.from(rawDrug)
          : const <String, dynamic>{},
      warnings: warnings,
      userProfile: userProfile,
      productContext: productContext,
    );

    return {
      ...interactionSummary,
      'condition_summary': gatedCondition,
      'drug_class_summary': gatedDrug,
    };
  }

  double _maxPossible(
    String? ageBracket,
    String? sex,
    List<String> goals,
    List<String> conditions,
  ) {
    double max = 80.0; // Base quality
    max += _maxPossibleE1(ageBracket, sex);
    if (goals.isNotEmpty) max += 2.0; // E2a
    if (ageBracket != null) max += 3.0; // E2b
    max += 8.0; // E2c always runs (no conditions = full points)
    return max;
  }

  double _maxPossibleE1(String? ageBracket, String? sex) {
    if (ageBracket == null) return 4.0;
    if (sex == null) return 0.0;
    return 7.0;
  }

  List<String> _selectedGoalMatches({
    required List<String> userGoals,
    required List<String> productGoalMatches,
  }) {
    if (userGoals.isEmpty || productGoalMatches.isEmpty) return const [];
    final matchSet = productGoalMatches.toSet();
    return userGoals.where(matchSet.contains).toList(growable: false);
  }

  double _goalAlignmentScore({
    required List<String> userGoals,
    required List<String> selectedGoalMatches,
    required double? productGoalMatchConfidence,
    required List<String> productClusters,
  }) {
    if (userGoals.isEmpty) return 0.0;
    if (selectedGoalMatches.isNotEmpty) {
      final matchedRatio = selectedGoalMatches.length / userGoals.length;
      final confidence = (productGoalMatchConfidence ?? 1.0).clamp(0.0, 1.0);
      return (2.0 * matchedRatio * confidence).clamp(0.0, 2.0);
    }

    // Fallback only when the pipeline hasn't populated goal matches yet.
    return e2a.calculate(
      productClusters: productClusters,
      userGoals: userGoals,
    );
  }

  _Assessment _buildAssessment({
    required double scoreFit20,
    required double maxPossible,
    required double e1Score,
    required double e2aScore,
    required double e2bScore,
    required Map<String, dynamic> interactionSummary,
    required List<String> userConditions,
    required List<String> userDrugClasses,
    required List<String> missingFields,
    required double mappedCoverage,
    required List<String> userGoals,
    required List<String> selectedGoalMatches,
  }) {
    final matches = _relevantMatches(
      interactionSummary: interactionSummary,
      userConditions: userConditions,
      userDrugClasses: userDrugClasses,
    );
    final maxSeverity = _maxSeverity(matches);
    final reasons = <String>[];

    if (maxSeverity == Severity.contraindicated ||
        maxSeverity == Severity.avoid) {
      reasons.addAll(_riskReasons(matches));
      return _Assessment(
        state: FitAssessmentState.notRecommended,
        maxRelevantSeverity: maxSeverity.name,
        reasons: reasons.take(3).toList(growable: false),
      );
    }

    if (missingFields.isNotEmpty) {
      reasons.add(
        'Add ${missingFields.join(', ')} to personalize this fit more accurately.',
      );
      if (matches.isNotEmpty) {
        reasons.addAll(_riskReasons(matches).take(2));
      }
      return _Assessment(
        state: FitAssessmentState.incompleteProfile,
        maxRelevantSeverity: maxSeverity == Severity.safe
            ? null
            : maxSeverity.name,
        reasons: reasons.take(3).toList(growable: false),
      );
    }

    if (mappedCoverage < 0.3) {
      reasons.add(
        'Ingredient mapping coverage is low, so this fit is conservative.',
      );
      reasons.addAll(
        _goalReasons(
          userGoals: userGoals,
          selectedGoalMatches: selectedGoalMatches,
        ),
      );
      return _Assessment(
        state: FitAssessmentState.limitedFit,
        maxRelevantSeverity: maxSeverity == Severity.safe
            ? null
            : maxSeverity.name,
        reasons: reasons.take(3).toList(growable: false),
      );
    }

    var state = FitAssessmentState.limitedFit;
    if (selectedGoalMatches.isNotEmpty) {
      final matchedAllGoals =
          userGoals.isNotEmpty &&
          selectedGoalMatches.length == userGoals.length;
      state = matchedAllGoals && e2aScore >= 1.5
          ? FitAssessmentState.strongMatch
          : FitAssessmentState.goodFit;
    }

    if (maxSeverity == Severity.caution || maxSeverity == Severity.monitor) {
      if (state == FitAssessmentState.strongMatch) {
        state = FitAssessmentState.goodFit;
      }
      reasons.addAll(_riskReasons(matches));
    }

    reasons.addAll(
      _goalReasons(
        userGoals: userGoals,
        selectedGoalMatches: selectedGoalMatches,
      ),
    );
    reasons.addAll(_signalReasons(e1Score: e1Score, e2bScore: e2bScore));

    return _Assessment(
      state: state,
      maxRelevantSeverity: maxSeverity == Severity.safe
          ? null
          : maxSeverity.name,
      reasons: reasons.take(3).toList(growable: false),
    );
  }

  List<_RelevantMatch> _relevantMatches({
    required Map<String, dynamic> interactionSummary,
    required List<String> userConditions,
    required List<String> userDrugClasses,
  }) {
    final out = <_RelevantMatch>[];
    final conditionSummary =
        interactionSummary['condition_summary'] as Map<String, dynamic>? ?? {};
    final drugSummary =
        interactionSummary['drug_class_summary'] as Map<String, dynamic>? ?? {};

    for (final id in userConditions) {
      final raw = conditionSummary[id];
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      out.add(
        _RelevantMatch(
          label: data['label']?.toString() ?? id,
          severity: Severity.fromString(
            data['highest_severity']?.toString() ?? 'safe',
          ),
          ingredients:
              (data['ingredients'] as List?)
                  ?.map((e) => e.toString())
                  .toList(growable: false) ??
              const <String>[],
        ),
      );
    }

    for (final id in userDrugClasses) {
      final raw = drugSummary[id];
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      out.add(
        _RelevantMatch(
          label: data['label']?.toString() ?? id,
          severity: Severity.fromString(
            data['highest_severity']?.toString() ?? 'safe',
          ),
          ingredients:
              (data['ingredients'] as List?)
                  ?.map((e) => e.toString())
                  .toList(growable: false) ??
              const <String>[],
        ),
      );
    }

    out.sort((a, b) => b.severity.weight.compareTo(a.severity.weight));
    return out;
  }

  Severity _maxSeverity(List<_RelevantMatch> matches) {
    if (matches.isEmpty) return Severity.safe;
    return matches.first.severity;
  }

  List<String> _riskReasons(List<_RelevantMatch> matches) {
    return matches
        .take(2)
        .map((match) {
          final ingredients = match.ingredients.isEmpty
              ? ''
              : ' from ${match.ingredients.join(', ')}';
          return '${match.label}: ${match.severity.label.toLowerCase()}$ingredients.';
        })
        .toList(growable: false);
  }

  List<String> _goalReasons({
    required List<String> userGoals,
    required List<String> selectedGoalMatches,
  }) {
    if (userGoals.isEmpty) return const [];
    if (selectedGoalMatches.isEmpty) {
      return const ['Does not strongly support your selected goals.'];
    }

    return selectedGoalMatches
        .take(2)
        .map((goalId) {
          final label = SchemaIds.goalLabels[goalId] ?? goalId;
          return 'Supports your $label goal.';
        })
        .toList(growable: false);
  }

  List<String> _signalReasons({
    required double e1Score,
    required double e2bScore,
  }) {
    final out = <String>[];
    if (e1Score < 0) {
      out.add('Dose safety needs extra caution.');
    } else if (e1Score >= 5) {
      out.add('Dosing looks appropriate for the nutrients we could map.');
    }
    if (e2bScore >= 2.5) {
      out.add('The nutrient profile looks age-appropriate.');
    }
    return out;
  }
}

class _Assessment {
  final FitAssessmentState state;
  final String? maxRelevantSeverity;
  final List<String> reasons;

  const _Assessment({
    required this.state,
    required this.maxRelevantSeverity,
    required this.reasons,
  });
}

class _RelevantMatch {
  final String label;
  final Severity severity;
  final List<String> ingredients;

  const _RelevantMatch({
    required this.label,
    required this.severity,
    required this.ingredients,
  });
}
