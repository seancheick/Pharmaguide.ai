import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';

/// Checks safety when adding a new product to the supplement stack.
/// All checks use data from products_core (no network needed).
class StackInteractionChecker {
  /// Run all safety checks for adding newProduct to existing stack.
  List<InteractionResult> checkSafety({
    required Map<String, dynamic> newProductFingerprint,
    required List<Map<String, dynamic>> stackFingerprints,
    required bool newContainsStimulants,
    required bool newContainsSedatives,
    required bool newContainsBloodThinners,
    required List<bool> stackContainsStimulants,
    required List<bool> stackContainsSedatives,
    required List<bool> stackContainsBloodThinners,
    required List<String> stackProductNames,
    required String newProductName,
  }) {
    final results = <InteractionResult>[];

    // Check 1: Stimulant/sedative antagonism
    if (newContainsStimulants) {
      for (int i = 0; i < stackContainsSedatives.length; i++) {
        if (stackContainsSedatives[i]) {
          results.add(InteractionResult(
            id: 'STACK_STIM_SED_$i',
            type: InteractionType.supplementSupplement,
            severity: Severity.caution,
            evidenceLevel: EvidenceLevel.established,
            agent1Name: newProductName,
            agent2Name: stackProductNames[i],
            mechanism:
                'Stack contains both stimulants and sedatives — opposing effects may reduce effectiveness of both',
            management:
                'Consider taking at different times or choosing one over the other',
            doseDependant: false,
            doseThreshold: null,
            sourceUrls: [],
            source: InteractionSource.stackEngine,
          ));
        }
      }
    }
    if (newContainsSedatives) {
      for (int i = 0; i < stackContainsStimulants.length; i++) {
        if (stackContainsStimulants[i]) {
          results.add(InteractionResult(
            id: 'STACK_SED_STIM_$i',
            type: InteractionType.supplementSupplement,
            severity: Severity.caution,
            evidenceLevel: EvidenceLevel.established,
            agent1Name: newProductName,
            agent2Name: stackProductNames[i],
            mechanism:
                'Stack contains both sedatives and stimulants — opposing effects',
            management: 'Consider separating by time of day',
            doseDependant: false,
            doseThreshold: null,
            sourceUrls: [],
            source: InteractionSource.stackEngine,
          ));
        }
      }
    }

    // Check 2: Blood thinner stacking
    if (newContainsBloodThinners) {
      for (int i = 0; i < stackContainsBloodThinners.length; i++) {
        if (stackContainsBloodThinners[i]) {
          results.add(InteractionResult(
            id: 'STACK_BT_$i',
            type: InteractionType.supplementSupplement,
            severity: Severity.avoid,
            evidenceLevel: EvidenceLevel.established,
            agent1Name: newProductName,
            agent2Name: stackProductNames[i],
            mechanism:
                'Multiple blood-thinning supplements increase bleeding risk',
            management:
                'Consult healthcare provider before combining blood-thinning supplements',
            doseDependant: true,
            doseThreshold: null,
            sourceUrls: [],
            source: InteractionSource.stackEngine,
          ));
        }
      }
    }

    // Check 3: Duplicate active ingredients
    final newNutrients =
        (newProductFingerprint['nutrients'] as Map?)?.keys.toSet() ?? {};
    for (int i = 0; i < stackFingerprints.length; i++) {
      final stackNutrients =
          (stackFingerprints[i]['nutrients'] as Map?)?.keys.toSet() ?? {};
      final overlap = newNutrients.intersection(stackNutrients);
      if (overlap.length >= 3) {
        results.add(InteractionResult(
          id: 'STACK_DUP_$i',
          type: InteractionType.supplementSupplement,
          severity: Severity.monitor,
          evidenceLevel: EvidenceLevel.probable,
          agent1Name: newProductName,
          agent2Name: stackProductNames[i],
          mechanism:
              '${overlap.length} overlapping nutrients: ${overlap.take(3).join(", ")}${overlap.length > 3 ? "..." : ""}',
          management: 'Check cumulative doses against daily upper limits',
          doseDependant: true,
          doseThreshold: null,
          sourceUrls: [],
          source: InteractionSource.stackEngine,
        ));
      }
    }

    return results;
  }
}
