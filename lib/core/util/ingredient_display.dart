// Display helpers for ingredient names + research-match summary lines
// surfaced in the score breakdown card and (later) other product-detail
// surfaces.
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 0, T0.1.

/// Branded / standardized ingredient forms that should render with
/// non-default casing. Pipeline-side keys are lowercase snake_case, but
/// the user-facing form often differs (KSM-66, BioPerine, Vitamin D3).
///
/// Add aliases on the same line — both `ksm_66` and `ksm66` map to
/// `KSM-66` so we tolerate pipeline-key drift.
const Map<String, String> _brandedForms = {
  // Branded standardized extracts
  'ksm_66': 'KSM-66',
  'ksm66': 'KSM-66',
  'sensoril': 'Sensoril',
  'shoden': 'Shoden',
  'bioperine': 'BioPerine',
  'piperine': 'Piperine',

  // Common acronym ingredients
  'coq10': 'CoQ10',
  'pqq': 'PQQ',
  'msm': 'MSM',
  'mct': 'MCT',
  'gaba': 'GABA',
  'epa': 'EPA',
  'dha': 'DHA',
  'ala': 'ALA',
  'gla': 'GLA',
  'tmg': 'TMG',
  'nadh': 'NADH',
  'sam_e': 'SAM-e',
  'hmb': 'HMB',
  'mk_4': 'MK-4',
  'mk_7': 'MK-7',

  // Hyphenated amino acids
  'l_theanine': 'L-Theanine',
  'l_carnitine': 'L-Carnitine',
  'l_arginine': 'L-Arginine',
  'l_glutamine': 'L-Glutamine',
  'l_lysine': 'L-Lysine',
  'l_tyrosine': 'L-Tyrosine',
  'd_aspartic_acid': 'D-Aspartic Acid',

  // Omega + fish-oil shorthand
  'omega_3': 'Omega-3',
  'omega_6': 'Omega-6',
  'omega_9': 'Omega-9',

  // Vitamins (common short forms)
  'vitamin_a': 'Vitamin A',
  'vitamin_b1': 'Vitamin B1',
  'vitamin_b2': 'Vitamin B2',
  'vitamin_b3': 'Vitamin B3',
  'vitamin_b5': 'Vitamin B5',
  'vitamin_b6': 'Vitamin B6',
  'vitamin_b12': 'Vitamin B12',
  'vitamin_c': 'Vitamin C',
  'vitamin_d': 'Vitamin D',
  'vitamin_d3': 'Vitamin D3',
  'vitamin_e': 'Vitamin E',
  'vitamin_k': 'Vitamin K',
  'vitamin_k2': 'Vitamin K2',
};

/// Render a pipeline ingredient key (e.g. `ksm_66`, `magnesium_glycinate`)
/// for display.
///
/// Branded / acronym forms in [_brandedForms] return their canonical
/// casing. Anything else gets word-by-word title casing
/// (`magnesium_glycinate` → `Magnesium Glycinate`). Empty input returns
/// an empty string.
String prettifyIngredientName(String key) {
  final normalized = key.toLowerCase().trim();
  if (normalized.isEmpty) return '';

  final brand = _brandedForms[normalized];
  if (brand != null) return brand;

  return normalized
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

/// Render the "{N} ingredient(s) backed by clinical research" line with
/// correct pluralization. Returns `null` for `0` or negative counts so
/// the caller can drop the bullet entirely instead of printing a
/// misleading "0 ingredients" line.
String? researchMatchSummary(int count) {
  if (count <= 0) return null;
  if (count == 1) return 'One ingredient backed by clinical research';
  return '$count ingredients backed by clinical research';
}
