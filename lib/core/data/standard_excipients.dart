// Phase 1 formulation-purity helpers: whitelist of standard
// manufacturing excipients + dosage-form-aware allowance + hide-when-clean
// decision.
//
// The full ontology + penalty-based scorer lands in Sprint 3 (T3.2);
// this is the patch that buys time so KSM-66 from Transparent Labs (and
// other clean capsule products) stops getting flagged "High filler load"
// just because it has 3 standard fillers.
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 0, T0.5.

/// Dosage forms recognized by the purity classifier. `unknown` is the
/// safe fallback when the pipeline didn't ship a `delivery_form` field
/// — we treat it like a capsule (the most common form) so behavior is
/// reasonable for partial data.
enum DosageForm {
  capsule,
  softgel,
  tablet,
  powder,
  liquid,
  gummy,
  unknown,
}

/// Generic excipients that are normal manufacturing components, not
/// "fillers" in the negative sense. Branded functional ingredients
/// (BioPerine, AlphaSize, etc.) are deliberately excluded — those are
/// active enhancers, not whitelist entries.
const Set<String> _whitelistedExcipients = {
  // Capsule shells
  'gelatin',
  'hpmc',
  'hydroxypropyl methylcellulose',
  'vegetable cellulose',
  'plant cellulose',
  'pullulan',

  // Lubricants
  'magnesium stearate',
  'vegetable magnesium stearate',
  'stearic acid',

  // Flow agents / bulking
  'microcrystalline cellulose',
  'mcc',
  'silicon dioxide',
  'silica',
  'dicalcium phosphate',

  // Common solvents
  'water',
  'purified water',
};

/// `true` when the named excipient is a standard manufacturing
/// component that should not push the formulation toward "High filler
/// load". Lookup is lowercase + trimmed so pipeline-key drift
/// (`Magnesium Stearate` vs `magnesium stearate`) is tolerated.
bool isWhitelistedExcipient(String name) {
  return _whitelistedExcipients.contains(name.toLowerCase().trim());
}

/// Parse a `delivery_form` string from the pipeline blob. Lenient —
/// matches by substring so `Vegetable Capsule`, `Veggie Caps`, and
/// `Capsules` all map to [DosageForm.capsule].
DosageForm parseDosageForm(String? raw) {
  final normalized = (raw ?? '').toLowerCase().trim();
  if (normalized.isEmpty) return DosageForm.unknown;

  // Order matters: check `softgel` before `capsule` since softgels
  // often include "capsule" in the marketing copy.
  if (normalized.contains('softgel') || normalized.contains('soft gel')) {
    return DosageForm.softgel;
  }
  if (normalized.contains('gummy') || normalized.contains('gummies')) {
    return DosageForm.gummy;
  }
  if (normalized.contains('capsule') || normalized.contains('caps')) {
    return DosageForm.capsule;
  }
  if (normalized.contains('tablet') || normalized.contains('caplet')) {
    return DosageForm.tablet;
  }
  if (normalized.contains('powder')) return DosageForm.powder;
  if (normalized.contains('liquid') ||
      normalized.contains('tincture') ||
      normalized.contains('drops')) {
    return DosageForm.liquid;
  }
  return DosageForm.unknown;
}

/// Maximum number of whitelisted excipients tolerated before the card
/// renders. `null` for forms that always render (gummies — the dyes
/// and sugars are inherent and must be visible).
int? whitelistAllowance(DosageForm form) {
  switch (form) {
    case DosageForm.capsule:
    case DosageForm.softgel:
      return 4;
    case DosageForm.tablet:
      return 5;
    case DosageForm.powder:
      return 1;
    case DosageForm.liquid:
      return 2;
    case DosageForm.gummy:
      return null; // always render
    case DosageForm.unknown:
      return 4; // capsule-like default for partial data
  }
}

/// Decide whether the formulation-purity card should render. Returns
/// `false` (hide) when the formulation is clean by Phase 1 rules:
///
///   - inactive list is empty, OR
///   - every entry is whitelisted AND count ≤ form allowance
///
/// Returns `true` (show) otherwise. Gummies always show — the
/// inherent sugars/dyes are part of why a user might want to see the
/// card.
bool shouldShowPurityCard({
  required DosageForm form,
  required List<String> inactiveNames,
}) {
  final cleaned = inactiveNames
      .map((n) => n.trim())
      .where((n) => n.isNotEmpty)
      .toList(growable: false);
  if (cleaned.isEmpty) return false;

  final allowance = whitelistAllowance(form);
  if (allowance == null) return true; // gummies always show

  final hasNonWhitelisted = cleaned.any((n) => !isWhitelistedExcipient(n));
  if (hasNonWhitelisted) return true;

  // All whitelisted — hide unless count exceeds allowance.
  return cleaned.length > allowance;
}
