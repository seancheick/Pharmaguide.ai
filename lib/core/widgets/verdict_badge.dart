import 'package:flutter/material.dart';
import 'package:pharmaguide/core/data/vocab_registry.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

/// Unknown verdicts already breadcrumbed this session. colorFor/labelFor run
/// on the render path (potentially every frame), so dedup keeps a corrupted
/// verdict from flooding the breadcrumb trail — one signal per unique value.
final Set<String> _breadcrumbedUnknownVerdicts = <String>{};

/// An unrecognized, non-empty verdict reaching the UI is contract drift (the
/// pipeline emitted a verdict the app doesn't map). Breadcrumb it once so the
/// drift is visible in crash reports without spamming.
void _reportUnknownVerdict(String normalizedId) {
  if (normalizedId.isEmpty) return;
  if (!_breadcrumbedUnknownVerdicts.add(normalizedId)) return;
  CrashReportingService().log(
    'verdict_badge: unrecognized verdict "$normalizedId" — rendering '
    'caution-tone (contract drift)',
  );
}

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
  /// Brightness-aware colour for a verdict string.
  ///
  /// Takes the palette explicitly: the previous signature promised
  /// brightness-awareness in its doc while returning fixed light tokens, so a
  /// BLOCKED verdict rendered at 2.38:1 on a dark surface. Requiring the
  /// palette makes the promise checkable at the call site.
  static Color colorFor(V2Palette p, String verdict) {
    switch (verdict.trim().toUpperCase()) {
      case 'RECOMMENDED':
        return p.safe;
      case 'SAFE':
      case 'GOOD':
        return p.safe;
      case 'CAUTION':
      case 'REVIEW':
        return p.caution;
      case 'POOR':
      case 'MODERATE':
        return p.avoid;
      case 'UNSAFE':
      case 'BLOCKED':
        return p.contraindicated;
      case 'NOT_SCORED':
      case 'NUTRITION_ONLY':
        return p.fgSubtle;
      default:
        // Fail-open guard: an unrecognized, non-empty verdict must NOT
        // render as a calm neutral chip — a future/corrupted BLOCKED-class
        // verdict would bypass every blocked gate. Fail toward CAUTION tone
        // (not neutral, not safe) and breadcrumb the drift. An empty string
        // is "no verdict yet / not-scored placeholder", which stays neutral.
        final normalized = verdict.trim().toUpperCase();
        if (normalized.isEmpty) return p.fgSubtle;
        _reportUnknownVerdict(normalized);
        return p.caution;
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
        // Contract drift: breadcrumb the unknown verdict (deduped, shared
        // with colorFor) so it's visible in crash reports. Still echo the
        // raw value — the actual corrupt string is more useful for triage
        // than a generic placeholder, and colorFor already forces the chip
        // to caution tone so it can't read as a calm all-clear.
        _reportUnknownVerdict(id);
        return verdict;
    }
  }
}
