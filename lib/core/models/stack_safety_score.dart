import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/synergy_result.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';

enum RiskTier {
  excellent(label: 'Your stack looks great', color: Color(0xFF22C55E)),
  good(label: 'Minor optimizations available', color: Color(0xFF22C55E)),
  caution(label: 'Some concerns to review', color: Color(0xFFEAB308)),
  moderateRisk(label: 'Important issues found', color: Color(0xFFF97316)),
  highRisk(label: 'Serious interactions detected', color: Color(0xFFDC2626));

  final String label;
  final Color color;
  const RiskTier({required this.label, required this.color});

  static RiskTier fromScore(int score) {
    if (score >= 90) return RiskTier.excellent;
    if (score >= 75) return RiskTier.good;
    if (score >= 60) return RiskTier.caution;
    if (score >= 40) return RiskTier.moderateRisk;
    return RiskTier.highRisk;
  }
}

enum StackHealthLabel {
  optimized(label: 'Optimized', color: Color(0xFF0F9D7A)),
  solid(label: 'Solid', color: Color(0xFF22C55E)),
  decent(label: 'Decent', color: Color(0xFFF59E0B)),
  concerning(label: 'Concerning', color: Color(0xFFF97316)),
  unsafe(label: 'Unsafe', color: Color(0xFFDC2626));

  final String label;
  final Color color;

  const StackHealthLabel({required this.label, required this.color});
}

class StackSafetyScore {
  final int score;
  final RiskTier riskTier;
  final List<InteractionResult> issues;
  final List<SynergyResult> synergies;
  final List<TimingOptimization> optimizations;

  const StackSafetyScore({
    required this.score,
    required this.riskTier,
    required this.issues,
    required this.synergies,
    required this.optimizations,
  });

  int get seriousCount =>
      issues.where((i) => i.severity.weight >= Severity.avoid.weight).length;

  int get moderateCount =>
      issues.where((i) => i.severity == Severity.caution).length;

  int get monitorCount =>
      issues.where((i) => i.severity == Severity.monitor).length;

  Severity get maxSeverity {
    Severity highest = Severity.safe;
    for (final issue in issues) {
      if (issue.severity.weight > highest.weight) highest = issue.severity;
    }
    return highest;
  }

  bool get hasUnsafeIssue =>
      maxSeverity == Severity.contraindicated || maxSeverity == Severity.avoid;

  StackHealthLabel get healthLabel {
    if (hasUnsafeIssue) return StackHealthLabel.unsafe;

    var label = switch (score) {
      >= 85 => StackHealthLabel.optimized,
      >= 70 => StackHealthLabel.solid,
      >= 55 => StackHealthLabel.decent,
      _ => StackHealthLabel.concerning,
    };

    if (maxSeverity == Severity.caution &&
        (label == StackHealthLabel.optimized ||
            label == StackHealthLabel.solid)) {
      label = StackHealthLabel.decent;
    } else if (maxSeverity == Severity.monitor &&
        label == StackHealthLabel.optimized) {
      label = StackHealthLabel.solid;
    }

    return label;
  }
}
