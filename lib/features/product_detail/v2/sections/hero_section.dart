// Phase 11.7b.1 — Product Detail v2 Hero section adapter.
//
// First section-adapter file. Establishes the pattern every other
// section follows in 11.7c+:
//
//   1. One file per section in `v2/sections/`.
//   2. Export a builder fn `Widget build<Name>Section(...)` that takes
//      pre-derived inputs (provider outputs, gating booleans, callbacks)
//      and returns the configured PG component.
//   3. Map production data shapes → PG component prop shapes ONLY in
//      this file. The connected screen never touches PG component
//      constructors directly.
//   4. Pure functions / data helpers (e.g. `buildHeroTrustTags`,
//      `composeServingsLabel`) sit alongside the builder for unit
//      testing.
//
// Why this matters: the production Product Detail file is 3,022 lines
// because every section's model→prop mapping is inlined into the
// build method. Moving that mapping into one-file-per-section keeps
// the connected screen lean (~300 lines of orchestration) regardless
// of how many sections eventually wire.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_hero_section.dart';
import 'package:pharmaguide/core/presentation/package_identity.dart';
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';
import 'package:pharmaguide/core/scoring/score_tier.dart';
import 'package:pharmaguide/core/widgets/product_image.dart';
import 'package:pharmaguide/features/product_detail/v2/gating.dart';
import 'package:pharmaguide/features/product_detail/widgets/product_image_viewer.dart';
import 'package:pharmaguide/data/database/core_database.dart';

/// One trust tag — the label plus whether the badge gets a check-mark
/// (certifications) or a simple dot (dietary tags). Matches the
/// production helper `_buildAllTags()` output shape.
class HeroTrustTag {
  final String label;
  final bool isCertification;
  const HeroTrustTag({required this.label, required this.isCertification});
}

const _confidenceDriverLabels = <String, String>{
  'no_clinical_evidence_matched': 'No clinical evidence matched',
  'human_clinical_evidence_absent': 'No human clinical evidence matched',
  'limited_human_evidence': 'Human clinical evidence is limited',
  'product_specific_nct_absent':
      'Product-specific clinical evidence not verified',
  'sub_clinical_dose_detected': 'Clinical dose relevance is limited',
  'no_verified_third_party_certification':
      'Product-level certification not verified',
  'third_party_verification_unresolved':
      'Product-level certification not verified',
  'brand_cert_not_sku_verified': 'Product-level certification not verified',
  'cert_claimed_only_no_registry_match':
      'Product-level certification not verified',
  'cert_match_needs_review': 'Product-level certification not verified',
  'cert_registry_stale_or_blocked': 'Product-level certification not verified',
  'cert_brand_mismatch_ignored': 'Product-level certification not verified',
  'manufacturer_signal_present_no_sku_match':
      'Product-level certification not verified',
  'dose_not_disclosed': 'Dose disclosure incomplete',
  'total_cfu_not_disclosed': 'Dose disclosure incomplete',
  'epa_or_dha_not_disclosed': 'Dose disclosure incomplete',
  'sports_active_dose_not_disclosed': 'Dose disclosure incomplete',
  'sports_primary_dose_not_disclosed': 'Dose disclosure incomplete',
  'micronutrient_panel_dose_coverage_low': 'Dose disclosure incomplete',
  'per_strain_cfu_not_disclosed': 'Per-strain dose disclosure incomplete',
  'dose_window_not_evaluable_by_rda_proxy': 'Dose evidence is indirect',
  'dose_window_partial_without_rda_reference': 'Dose evidence is indirect',
  'conservative_blend_anchor_mass': 'Dose evidence is indirect',
  'active_anchor_mass_evidence': 'Dose evidence is indirect',
  'botanical_anchor_only_evidence': 'Dose evidence is indirect',
  'percent_dv_only_dose_evidence': 'Only % Daily Value was available',
  'enzyme_activity_dose_evidence':
      'Enzyme activity limits direct dose comparison',
  'ingredient_identity_confidence_below_80_percent':
      'Ingredient identity uncertain',
  'ingredient_identity_confidence_below_95_percent':
      'Ingredient identity uncertain',
  'safety_identity_match_needs_review': 'Ingredient identity uncertain',
  'mapped_coverage_below_95_percent':
      'Ingredient identity coverage is incomplete',
  'low_mapped_coverage': 'Ingredient identity coverage is incomplete',
  'form_factor_inferred': 'Product form inferred',
  'form_factor_not_disclosed': 'Product form is uncertain',
  'taxonomy_classification_low_confidence': 'Product category inferred',
  'high_proprietary_blend_opacity': 'Proprietary blend limits evaluation',
  'partial_proprietary_blend_opacity': 'Proprietary blend limits evaluation',
  'label_claim_contradiction': 'Label information is inconsistent',
  'disease_claim_penalty_present': 'Label claims limit evaluation',
  'named_strain_not_disclosed': 'Strain identity disclosure incomplete',
  'low_confidence_omega_breakdown': 'Omega dose breakdown is uncertain',
  'product_status_not_active': 'Catalog status requires review',
};

/// Translate the worst-band confidence drivers into at most two stable,
/// consumer-readable reasons. Positive evidence drivers are intentionally not
/// repeated; this surface explains uncertainty, not score credit.
List<String> scoreConfidenceDriverLabels(
  Map<String, dynamic>? confidenceDetail,
) {
  if (confidenceDetail == null) return const [];
  final band = confidenceDetail['band']?.toString().trim().toLowerCase();
  if (band == null || band.isEmpty) return const [];

  const sectionOrder = [
    'label_completeness',
    'identity',
    'verification',
    'evidence',
  ];
  final labels = <String>[];
  for (final sectionName in sectionOrder) {
    final section = confidenceDetail[sectionName];
    if (section is! Map) continue;
    if (section['level']?.toString().trim().toLowerCase() != band) continue;
    final drivers = section['drivers'];
    if (drivers is! List) continue;
    for (final rawDriver in drivers) {
      final label = _confidenceDriverLabels[rawDriver.toString().trim()];
      if (label != null && !labels.contains(label)) labels.add(label);
      if (labels.length == 2) return labels;
    }
  }
  return labels;
}

/// Build the production tag list from a `ProductsCoreData` row. Reads
/// the 8 boolean columns production reads in `_buildAllTags()`, in
/// the same order (certifications first, dietary tags second) so the
/// hero chip-row visual sequence stays parity.
List<HeroTrustTag> buildHeroTrustTags(ProductsCoreData? product) {
  final tags = <HeroTrustTag>[];
  if (product?.hasThirdPartyTesting == 1) {
    tags.add(
      const HeroTrustTag(label: 'Third-Party Tested', isCertification: true),
    );
  }
  if (product?.isTrustedManufacturer == 1) {
    tags.add(
      const HeroTrustTag(label: 'Trusted Manufacturer', isCertification: true),
    );
  }
  if (product?.isVegan == 1) {
    tags.add(const HeroTrustTag(label: 'Vegan', isCertification: false));
  }
  if (product?.isGlutenFree == 1) {
    tags.add(const HeroTrustTag(label: 'Gluten-Free', isCertification: false));
  }
  if (product?.isDairyFree == 1) {
    tags.add(const HeroTrustTag(label: 'Dairy-Free', isCertification: false));
  }
  if (product?.isSoyFree == 1) {
    tags.add(const HeroTrustTag(label: 'Soy-Free', isCertification: false));
  }
  if (product?.isOrganic == 1) {
    tags.add(const HeroTrustTag(label: 'Organic', isCertification: true));
  }
  if (product?.isNonGmo == 1) {
    tags.add(const HeroTrustTag(label: 'Non-GMO', isCertification: false));
  }
  return tags;
}

/// Build the Hero section widget. Pure render — takes pre-derived
/// values from the connected screen, returns a PGHeroSection ready to
/// drop into the v2 sliver list.
///
/// `bottomBanner` slot: 11.7c will pass a `BlockedBanner` adapter here
/// when [isBlocked] is true, fed by `_topWarnings()` and
/// `detailBlob['banned_substance_detail']`. For now callers pass null
/// and the section renders without a banner.
Widget buildHeroSection({
  required BuildContext context,
  required String dsldId,
  required ProductsCoreData? product,
  required String productName,
  required String brandName,
  required String formFactor,
  required double? score100,
  required bool isBlocked,
  required bool isNotScored,
  required List<HeroTrustTag> trustTags,
  Map<String, dynamic>? scoreConfidenceDetail,
  Widget? bottomBanner,
}) {
  return PGHeroSection(
    imageWidget: ProductImage(
      dsldId: dsldId,
      upc: product?.upcSku,
      dsldImagePath: product?.imageThumbnailUrl,
      productName: productName,
      brandName: brandName,
      formFactor: formFactor,
      score: score100,
      size: 84,
      compact: true,
      // Tap the hero image → open fullscreen viewer with pinch-zoom.
      // The Hero tag matches the carousel→detail flight convention so
      // the lift animation stays smooth.
      onTap: (imageUrl) => ProductImageViewer.show(
        context,
        imageUrl: imageUrl,
        heroTag: 'product-$dsldId',
        productName: productName,
      ),
    ),
    productName: productName,
    brandName: brandName,
    servingsLabel: packageSizeLabel(
      quantity: product?.netContentsQuantity,
      unit: product?.netContentsUnit,
      fallbackFormFactor: formFactor,
    ),
    servingCountLabel: packageServingCountLabel(product?.servingsPerContainer),
    dosingSummary: product?.dosingSummary,
    trustTags: trustTags
        .map(
          (t) => PGTrustTag(label: t.label, isCertification: t.isCertification),
        )
        .toList(growable: false),
    score: score100?.round(),
    qualityTier: product?.qualityTier,
    isNotScored: isNotScored,
    isBlocked: isBlocked,
    // Defensive release guard: an incomplete record must never receive a
    // positive quality verdict. Consumer copy stays neutral; the underlying
    // catalog diagnosis belongs to the release gate.
    lowCoverage: productHasLowCoverage(product),
    limitedAssessment: hasLimitedAssessmentConfidence(product?.v4Confidence),
    scoreConfidence: product?.v4Confidence,
    scoreConfidenceDrivers: scoreConfidenceDriverLabels(scoreConfidenceDetail),
    bottomBanner: bottomBanner,
    hasCatalogCaution:
        product != null &&
        catalogProductSafetyStatus(product) ==
            CatalogProductSafetyStatus.caution,
  );
}
