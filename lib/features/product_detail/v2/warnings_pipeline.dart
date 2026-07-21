// Phase 11.7b.1 — Product Detail v2 warning compose pipeline.
//
// Pure functions that combine the 2 warning sources (personalized DB
// + blob-static) into the single `guardedWarnings` list every Product
// Detail surface consumes. No Riverpod, no BuildContext — designed to
// be unit-tested by passing canned inputs.
//
// Pipeline order:
//   1. Parse blob warnings (drop legacy product-status entries)
//   2. Merge personalized + blob without lossy source-level dedupe
//   3. Apply `filterProductDetailWarningsForProfile` — the shared
//      profile / UL / threshold gate
//   4. Partition, then dedupe once by stable consumer-visible identity
//
// Phase 11.11 will also extract `filterProductDetailWarningsForProfile`
// from into this same module so the heavy
// transitive import disappears. For now we import the production
// top-level fn as-is.

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/features/product_detail/product_detail_helpers.dart'
    show filterProductDetailWarningsForProfile;
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

const _lifeStageConditionIds = {'pregnancy', 'lactation', 'ttc'};

/// True only for profile-matched context that is useful to retain but should
/// not read like a danger signal.
///
/// Hard warnings, critical presentation, medication interactions, and
/// medical-condition risks never enter this lane. `no_data` is also excluded:
/// uncertainty alone is neither a warning nor useful reassurance.
bool isCalmProfileNote(InteractionWarning warning) {
  final hasProfileScope =
      warning.conditionIds.isNotEmpty ||
      warning.drugClassIds.isNotEmpty ||
      warning.profileGate != null;
  if (!hasProfileScope ||
      warning.severity.isHard ||
      warning.evidenceLevel == EvidenceLevel.noData ||
      _normalizedDisplayMode(warning.displayModeDefault) == 'critical') {
    return false;
  }
  final direction = _normalizeConsumerText(warning.direction);
  if (direction == 'beneficial') return true;
  if (!warning.severity.isActionable) return true;
  if (direction != 'neutral' || warning.drugClassIds.isNotEmpty) return false;

  // A neutral pregnancy/lactation/TTC rule is contextual guidance, not a
  // harm signal (for example, an RDA-range nutrient compatibility note).
  // Do not generalize this to other conditions: neutral lab-test and
  // medication context can still require action and must remain a warning.
  final conditions = warning.conditionIds
      .map(_normalizeConsumerText)
      .where((condition) => condition.isNotEmpty)
      .toSet();
  return conditions.isNotEmpty &&
      conditions.every(_lifeStageConditionIds.contains);
}

/// Compose the warning list every Product Detail surface renders.
///
/// Returns the same `guardedWarnings` list production passes to
/// ReviewBeforeUseCard, the For-You section, and BetterAlternatives.
List<InteractionWarning> composeGuardedWarnings({
  required Map<String, dynamic>? detailBlob,
  required List<InteractionWarning> personalizedWarnings,
  required Set<String> userConditions,
  required Set<String> userDrugClasses,
  required Set<String> userProfileFlags,
}) {
  final blobWarnings = parseBlobWarnings(detailBlob);
  final merged = <InteractionWarning>[...personalizedWarnings, ...blobWarnings];
  return filterProductDetailWarningsForProfile(
    detailBlob: detailBlob,
    warnings: merged,
    userConditions: userConditions,
    userDrugClasses: userDrugClasses,
    userProfileFlags: userProfileFlags,
  );
}

/// Drain the blob's `warnings` + `warnings_profile_gated` lists, drop
/// legacy product-status entries when structured product status is
/// present, and preserve every valid row until the final display boundary.
List<InteractionWarning> parseBlobWarnings(Map<String, dynamic>? blob) {
  if (blob == null) return const [];
  final result = <InteractionWarning>[];
  final hasStructuredProductStatus = blob['product_status'] is Map;
  final hasStructuredAllergens = _hasStructuredAllergens(blob['allergens']);
  for (final key in const ['warnings', 'warnings_profile_gated']) {
    final raw = blob[key];
    if (raw is! List) continue;
    final candidates = raw.whereType<Map<String, dynamic>>().where(
      (warning) =>
          !_isLegacyProductStatusWarning(
            warning,
            hasStructuredProductStatus: hasStructuredProductStatus,
          ) &&
          !_isStructuredAllergenDuplicate(
            warning,
            hasStructuredAllergens: hasStructuredAllergens,
          ),
    );
    // Parse per-element so one malformed blob entry can't throw away
    // every other (valid) warning in the list. A skipped entry is
    // recorded to Sentry; the rest of the warnings still render.
    for (final warning in candidates) {
      try {
        result.add(InteractionWarning.fromJson(warning));
      } on Object catch (e, st) {
        CrashReportingService().recordError(
          e,
          st,
          hint: 'warnings_pipeline:skip_malformed',
        );
      }
    }
  }
  return result;
}

bool _hasStructuredAllergens(Object? raw) {
  if (raw is! List) return false;
  // "Structured present" MUST mean the matcher can actually use it:
  // matchAllergens keys strictly on a non-empty `allergen_id`. Treating a
  // display_name-only entry as structured would drop the legacy allergen
  // warning (see _isStructuredAllergenDuplicate) with nothing to replace it
  // — a silent allergen miss for a sensitized user. Require a usable id.
  return raw.whereType<Map<Object?, Object?>>().any((entry) {
    final id = entry['allergen_id']?.toString().trim();
    return id != null && id.isNotEmpty;
  });
}

/// Drop legacy allergen warning rows once the structured `allergens[]`
/// contract is present. Structured allergens are profile-matched via
/// `matchAllergens(profile.allergens, blob.allergens)`. Keeping the
/// duplicate warning row here makes "Allergen: X" show for users who
/// explicitly declared no allergies.
bool _isStructuredAllergenDuplicate(
  Map<String, dynamic> warning, {
  required bool hasStructuredAllergens,
}) {
  if (!hasStructuredAllergens) return false;
  final tokens = [
    warning['type'],
    warning['source'],
    warning['category'],
    warning['warning_type'],
  ].map((value) => value?.toString().trim().toLowerCase() ?? '');
  return tokens.contains('allergen') || tokens.contains('allergen_db');
}

/// Drop "status" entries that predate structured `product_status`.
/// When the blob carries structured product_status, the legacy
/// free-text status warnings duplicate what the structured surface
/// renders elsewhere. Mirrors production's
/// `_isLegacyProductStatusWarning` private method.
bool _isLegacyProductStatusWarning(
  Map<String, dynamic> warning, {
  required bool hasStructuredProductStatus,
}) {
  if (!hasStructuredProductStatus) return false;
  final tokens = [
    warning['type'],
    warning['source'],
    warning['category'],
    warning['warning_type'],
  ].map((value) => value?.toString().trim().toLowerCase() ?? '');
  return tokens.contains('status') || tokens.contains('product_status');
}

/// Split guarded warnings into the ones that belong in the
/// "Review for your profile" card vs. global/educational notes.
///
/// A warning stays in the profile bucket when it is a hard safety warning
/// (contraindicated / avoid) OR it actually fires for the current profile
/// ([InteractionWarning.matchesProfile]) AND is actionable (caution / monitor —
/// severities that carry a real penalty).
///
/// Everything else moves to [general]: unmatched "if you have X…" notes, and —
/// even when the profile matches — informational / safe rows, which are neutral
/// context or positive notes (e.g. "B12 recommended preconception"). This keeps
/// the profile card and its "N things to review" count focused on what actually
/// needs attention, not benefits or FYIs.
({List<InteractionWarning> profile, List<InteractionWarning> general})
partitionProfileWarnings({
  required List<InteractionWarning> warnings,
  required Set<String> userConditions,
  required Set<String> userDrugClasses,
  required Set<String> userProfileFlags,
}) {
  final representatives = <InteractionWarning>[];
  final representativeIsProfile = <bool>[];
  final representativeMatchesProfile = <bool>[];
  final representativeIdentities = <Set<String>>[];
  for (final w in warnings) {
    final matched = w.matchesProfile(
      userConditions: userConditions,
      userDrugClasses: userDrugClasses,
      userProfileFlags: userProfileFlags,
    );
    final isHard = w.severity.isHard;
    // Only actionable severities (caution / monitor — a real, if mild,
    // negative signal) count as "review before use". Informational / safe
    // rows carry no penalty: they are neutral context or positive notes
    // (e.g. "B12 recommended preconception", "may support PCOS-related
    // fertility") and move to the calm general surface even when the profile
    // matches, so the "N things to review" count reflects only what needs
    // attention. Hard warnings always surface regardless of profile.
    // Critical-mode caution rows with no profile gate (for example product
    // quality additives such as P80) remain visible, but in the general surface
    // instead of inflating "Review for your profile".
    // `no_data` is uncertainty, not evidence of harm. POLICY — "if we don't
    // know, we don't flag": an unresolved-evidence advisory is INTENTIONALLY
    // suppressed. It is excluded from BOTH this amber review lane AND the calm
    // "Good to know" lane (isCalmProfileNote also excludes noData), rather than
    // surfaced as a generic "limited safety data" note that would recreate the
    // meaningless-warning noise across many pregnancy/lactation products. This
    // drop is deliberate and test-locked (review_before_use_card_test —
    // "intentionally suppressed"); do NOT "restore" it to Good to know.
    // Hard warnings remain hard regardless of evidence availability.
    final isActionable =
        w.severity.isActionable &&
        w.evidenceLevel != EvidenceLevel.noData &&
        !isCalmProfileNote(w);
    final belongsInProfile = isHard || (matched && isActionable);
    final identities = _consumerWarningIdentities(w);
    final existingIndex = representativeIdentities.indexWhere(
      (existing) => existing.intersection(identities).isNotEmpty,
    );
    if (existingIndex == -1) {
      representatives.add(w);
      representativeIsProfile.add(belongsInProfile);
      representativeMatchesProfile.add(matched);
      representativeIdentities.add(identities);
    } else {
      final existing = representatives[existingIndex];
      final existingBelongsInProfile = representativeIsProfile[existingIndex];
      final existingMatchesProfile =
          representativeMatchesProfile[existingIndex];
      final doseSpecificityDiffers =
          _hasSameDoseSubject(existing, w) &&
          _doseSpecificity(existing) != _doseSpecificity(w);
      final preferred = _preferredWarning(
        existing,
        w,
        existingMatchesProfile: existingMatchesProfile,
        incomingMatchesProfile: matched,
      );
      final mergedSources = <String>{
        ...existing.sourceUrls.map((url) => url.trim()),
        ...w.sourceUrls.map((url) => url.trim()),
      }.where((url) => url.isNotEmpty).toList(growable: false)..sort();
      representatives[existingIndex] = preferred.withSourceUrls(mergedSources);
      representativeIsProfile[existingIndex] = doseSpecificityDiffers
          ? (identical(preferred, w)
                ? belongsInProfile
                : existingBelongsInProfile)
          : existingBelongsInProfile || belongsInProfile;
      representativeMatchesProfile[existingIndex] =
          existingMatchesProfile || matched;
      representativeIdentities[existingIndex].addAll(identities);
    }
  }

  final profile = <InteractionWarning>[];
  final general = <InteractionWarning>[];
  for (var i = 0; i < representatives.length; i++) {
    if (representativeIsProfile[i]) {
      profile.add(representatives[i]);
    } else {
      general.add(representatives[i]);
    }
  }
  return (profile: profile, general: general);
}

Set<String> _consumerWarningIdentities(InteractionWarning warning) {
  final identities = <String>{_visibleWarningIdentity(warning)};
  final subject = _canonicalWarningSubject(warning);
  final isCriticalIncident =
      warning.severity.isHard ||
      _normalizedDisplayMode(warning.displayModeDefault) == 'critical';
  if (subject.isNotEmpty && isCriticalIncident) {
    final conditions = [...warning.conditionIds.map(_normalizeConsumerText)]
      ..sort();
    final drugClasses = [...warning.drugClassIds.map(_normalizeConsumerText)]
      ..sort();
    identities.add(
      [
        'hazard',
        subject,
        conditions.join(','),
        drugClasses.join(','),
        _normalizeConsumerText(warning.banContext),
        _normalizeConsumerText(warning.additiveCategory),
      ].join('\u001f'),
    );
  }
  if (subject.isNotEmpty &&
      (warning.conditionIds.isNotEmpty ||
          warning.drugClassIds.isNotEmpty ||
          warning.profileGate != null)) {
    final rawConditions = warning.conditionIds
        .map(_normalizeConsumerText)
        .where((condition) => condition.isNotEmpty)
        .toSet();
    final conditions =
        rawConditions.isNotEmpty &&
            rawConditions.every(_lifeStageConditionIds.contains)
        ? const ['life-stage']
        : (rawConditions.toList()..sort());
    final drugClasses = [...warning.drugClassIds.map(_normalizeConsumerText)]
      ..sort();
    identities.add(
      [
        'profile-hazard',
        subject,
        _normalizeConsumerText(warning.displayHeadline),
        conditions.join(','),
        drugClasses.join(','),
        _normalizedDisplayMode(warning.displayModeDefault),
      ].join('\u001f'),
    );
  }
  return identities;
}

String _visibleWarningIdentity(InteractionWarning warning) {
  // The collapsed warning row renders severity, evidence, headline, and body,
  // but repeating the same message solely because two producers disagree on
  // metadata is worse than selecting one authoritative representative.
  // Severity/evidence differences from duplicate producers do not justify
  // repeating the same consumer message. The representative selector below
  // retains the safest, most product-specific version, and citation URLs are
  // unioned when representatives merge.
  return [
    'visible',
    _normalizedDisplayMode(warning.displayModeDefault),
    _normalizeConsumerText(warning.displayHeadline),
    _normalizeConsumerText(warning.displayBody),
  ].join('\u001f');
}

String _canonicalWarningSubject(InteractionWarning warning) {
  final identifiers = warning.identifiers;
  if (identifiers != null) {
    for (final key in const ['canonical_id', 'cui', 'unii', 'cas']) {
      final value = _normalizeConsumerText(identifiers[key]?.toString());
      if (value.isNotEmpty) return '$key:$value';
    }
  }
  return _normalizeConsumerText(warning.ingredientName);
}

InteractionWarning _preferredWarning(
  InteractionWarning existing,
  InteractionWarning incoming, {
  required bool existingMatchesProfile,
  required bool incomingMatchesProfile,
}) {
  // A hard warning can never be displaced by a lower tier, even when the
  // latter has richer product metadata.
  if (incoming.severity.isHard != existing.severity.isHard) {
    return incoming.severity.isHard ? incoming : existing;
  }
  // Prefer the row that was actually evaluated against this product's dose.
  // Older catalog producers can emit a generic pregnancy/lactation row beside
  // a dose-aware condition row for the same hazard; choosing by severity first
  // would turn a normal-dose informational result back into a false caution.
  final existingDoseSpecificity = _doseSpecificity(existing);
  final incomingDoseSpecificity = _doseSpecificity(incoming);
  if (_hasSameDoseSubject(existing, incoming) &&
      incomingDoseSpecificity != existingDoseSpecificity) {
    return incomingDoseSpecificity > existingDoseSpecificity
        ? incoming
        : existing;
  }
  if (incoming.severity.weight != existing.severity.weight) {
    return incoming.severity.weight > existing.severity.weight
        ? incoming
        : existing;
  }
  if (incomingMatchesProfile != existingMatchesProfile) {
    return incomingMatchesProfile ? incoming : existing;
  }
  int copyScore(InteractionWarning warning) =>
      (warning.alertHeadline?.trim().isNotEmpty == true ? 2 : 0) +
      (warning.alertBody?.trim().isNotEmpty == true ? 3 : 0) +
      (warning.management.trim().isNotEmpty ? 1 : 0);
  return copyScore(incoming) > copyScore(existing) ? incoming : existing;
}

int _doseSpecificity(InteractionWarning warning) {
  if (warning.doseThresholdEvaluation?['evaluated'] == true) return 3;
  if (_normalizeConsumerText(warning.doseFloorStatus).isNotEmpty) return 2;
  if (warning.profileGate?['dose'] is Map) return 1;
  return 0;
}

bool _hasSameDoseSubject(
  InteractionWarning existing,
  InteractionWarning incoming,
) {
  final existingSubject = _canonicalWarningSubject(existing);
  return existingSubject.isNotEmpty &&
      existingSubject == _canonicalWarningSubject(incoming);
}

String _normalizeConsumerText(String? value) =>
    (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

String _normalizedDisplayMode(String? value) {
  final normalized = _normalizeConsumerText(value);
  // Legacy blobs treat an absent display mode as informational.
  return normalized.isEmpty ? 'informational' : normalized;
}

/// Worst-case severity across a warning list. Empty list returns
/// `Severity.safe` (the no-issues baseline). Used by For-You section
/// to gate the risk surface + by BetterAlternatives to compute fit
/// display verdict.
Severity worstSeverityOf(List<InteractionWarning> warnings) {
  Severity worst = Severity.safe;
  for (final w in warnings) {
    if (w.severity.weight > worst.weight) worst = w.severity;
  }
  return worst;
}
