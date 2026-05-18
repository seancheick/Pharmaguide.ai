import 'package:flutter/material.dart';
import 'package:pharmaguide/core/data/vocab_registry.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';

/// Returns true when a verdict string represents a hard-stop
/// ban — BLOCKED only. Drives the FLTR-10 full-screen override:
/// banned/illegal products replace the product detail surface
/// entirely. UNSAFE is deliberately NOT included here — those
/// products still render the full detail screen with strong alerts.
bool isBlockedVerdict(String? verdict) {
  return (verdict ?? '').trim().toUpperCase() == 'BLOCKED';
}

/// Returns true when a verdict string is BLOCKED or legacy UNSAFE — i.e.
/// unsafe to add to a supplement stack under any circumstances.
/// Drives the FLTR-16 stack-add guard (domain + UI), which is
/// stricter than the BLOCKED renderer override (`_BlockedBanner` in
///): we still show detail for UNSAFE
/// products but never let them be tracked.
bool isUnsafeVerdict(String? verdict) {
  final v = (verdict ?? '').trim().toUpperCase();
  return v == 'BLOCKED' || v == 'UNSAFE';
}

/// A "verdict" is the final single-word rating from the scoring pipeline
/// (SAFE / CAUTION / POOR / BLOCKED / NOT_SCORED / NUTRITION_ONLY).
/// Retired labels are still accepted for old fixtures / cached rows.
abstract final class VerdictBadge {
  /// Brightness-aware color for a verdict string. Used externally by
  /// consumers that need to color text or icons to match.
  static Color colorFor(String verdict) {
    switch (verdict.trim().toUpperCase()) {
      case 'RECOMMENDED':
        return V2Colors.safe;
      case 'SAFE':
      case 'GOOD':
        return V2Colors.safe;
      case 'CAUTION':
      case 'REVIEW':
        return V2Colors.caution;
      case 'POOR':
      case 'MODERATE':
        return V2Colors.avoid;
      case 'UNSAFE':
      case 'BLOCKED':
        return V2Colors.contraindicated;
      case 'NOT_SCORED':
      case 'NUTRITION_ONLY':
        return V2Colors.fgSubtle;
      default:
        return V2Colors.fgSubtle;
    }
  }

  /// Human-friendly label. Avoids all-caps for verdicts longer than 12 chars.
  ///
  /// Vocab-first lookup (added 2026-05-02): if VocabRegistry is initialized
  /// and contains the verdict ID, returns vocab[id].name. Falls back to the
  /// legacy switch for retired labels still cached in older blobs
  /// (RECOMMENDED, GOOD, MODERATE, REVIEW, NOT_SCORED) and for the early-
  /// boot window before VocabRegistry.init() completes.
  ///
  /// The drift-contract test in test/core/verdict_vocab_drift_test.dart
  /// asserts vocab labels match this switch — both sources stay in lockstep
  /// until the legacy switch is deleted in a follow-up cleanup PR.
  static String labelFor(String verdict) {
    final id = verdict.trim().toUpperCase();
    final fromVocab = VocabRegistry.instance.verdict(id);
    if (fromVocab != null) return fromVocab.name;
    switch (id) {
      case 'RECOMMENDED':
        return 'Recommended';
      case 'SAFE':
        return 'Safe';
      case 'GOOD':
        return 'Good';
      case 'CAUTION':
        return 'Caution';
      case 'POOR':
        return 'Poor';
      case 'MODERATE':
        return 'Moderate';
      case 'REVIEW':
        return 'Review';
      case 'UNSAFE':
        return 'Unsafe';
      case 'BLOCKED':
        return 'Blocked';
      case 'NOT_SCORED':
        return 'Not scored';
      case 'NUTRITION_ONLY':
        return 'Nutrition only';
      default:
        return verdict;
    }
  }
}
