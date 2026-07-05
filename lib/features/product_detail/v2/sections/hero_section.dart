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

/// Compose the hero's "60 Softgels" subtitle. Production uses
/// `servingsPerContainer + formFactor` (T11.1 — replaced netContents
/// which produced awkward strings like "1 Fluid Ounce(s)" for liquids).
///
/// Returns null when the product carries no servingsPerContainer so
/// callers can omit the line entirely rather than render an awkward
/// "0 capsule" string.
String? composeServingsLabel({
  required String formFactor,
  required int? servingsPerContainer,
}) {
  if (servingsPerContainer == null || servingsPerContainer <= 0) return null;
  final form = formFactor.trim();
  if (form.isEmpty) return '$servingsPerContainer servings';
  return '$servingsPerContainer $form';
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
  Widget? bottomBanner,
  // Pipeline verdict string (`_product?.verdict`). When `CAUTION` — incl.
  // the dose-driven `DOSE_OVER_UL_*` CAUTION — the hero surfaces a caution
  // cue beside the tier score. Optional/null-default so callers that have
  // not wired it yet keep compiling; BLOCKED / NOT_SCORED still route
  // through [isBlocked] / [isNotScored].
  String? verdict,
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
    servingsLabel: composeServingsLabel(
      formFactor: formFactor,
      servingsPerContainer: product?.servingsPerContainer,
    ),
    dosingSummary: product?.dosingSummary,
    trustTags: trustTags
        .map(
          (t) => PGTrustTag(label: t.label, isCertification: t.isCertification),
        )
        .toList(growable: false),
    score: score100?.round(),
    isNotScored: isNotScored,
    isBlocked: isBlocked,
    // FIX 2 — low-coverage guard. Derived from the same product row the
    // connected screen reads (`_product?.mappedCoverage ?? 0.0`), so the
    // hero hedges exactly when the LabelConfidence card does. When
    // coverage is below the 0.3 trust floor, PGHeroSection replaces the
    // tier-colored score line with the neutral "Limited data" hedge.
    lowCoverage: productHasLowCoverage(product),
    bottomBanner: bottomBanner,
    verdict: verdict,
  );
}
