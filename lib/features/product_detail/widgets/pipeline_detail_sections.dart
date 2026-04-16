// Barrel: re-exports the split pipeline detail section widgets so existing
// imports continue to work. Each section auto-hides when its data is absent.
//
// The original single-file implementation was split into focused files under
// `pipeline_sections/` for easier maintenance. Importers should prefer the
// granular files for new code but may continue to import this barrel.

export 'pipeline_sections/allergen_summary_banner.dart';
export 'pipeline_sections/certification_detail_section.dart';
export 'pipeline_sections/evidence_detail_section.dart';
export 'pipeline_sections/formulation_detail_section.dart';
export 'pipeline_sections/probiotic_detail_section.dart';
export 'pipeline_sections/synergy_detail_section.dart';
