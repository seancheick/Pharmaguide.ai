import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/synergy_result.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';

/// Internal score data only. User-facing tiers are derived exclusively by
/// [StackIntelligence], never from this score object.
class StackSafetyScore {
  final int score;
  final List<InteractionResult> issues;
  final List<SynergyResult> synergies;
  final List<TimingOptimization> optimizations;

  const StackSafetyScore({
    required this.score,
    required this.issues,
    required this.synergies,
    required this.optimizations,
  });
}
