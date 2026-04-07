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
}
