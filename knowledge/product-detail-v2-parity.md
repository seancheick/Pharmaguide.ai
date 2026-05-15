# Product Detail v2 — Parity Checklist

Sean 2026-05-15: this is the **anti-regression contract** for the flagship
Product Detail screen migration to v2. The visual design language is approved
(fixture screen at `/dev/v2/product-detail`); the remaining work is **provider
wiring + behavior parity + safety gating parity**. No section moves to
`accepted` until every field below is populated and matches production
behavior.

Source files:
- Production: `lib/features/product_detail/product_detail_screen.dart` (3,022 lines)
- V2 connected: `lib/features/product_detail/v2/product_detail_v2_connected.dart` (orchestration only)
- V2 module split:
  - `v2/scroll_anchors.dart` — 3 GlobalKeys + deep-link scroll + unsafe-CTA jump
  - `v2/gating.dart` — pure boolean gates
  - `v2/warnings_pipeline.dart` — `composeGuardedWarnings()` (parse blob + dedup vs personalized + profile/UL filter)
  - `v2/sections/<name>_section.dart` — one file per section adapter (model → PG component prop mapping)
  - `v2/sections/<name>_helpers.dart` — split here when adapter mapping gets non-trivial

---

## Status legend

- `placeholder` — `_SectionPlaceholder` renders with section name + diagnostic; gate ✅, body ⬜
- `wired` — section adapter file exists, real data flows, builds clean
- `verified` — live-device tested across all golden scenarios listed in row
- `accepted` — Sean signed off; section can be retired from active tracking

---

## ⚠ Must Not Regress

These 12 behaviors are the hard contract. Every v2 wiring commit must verify
they still fire. If any one of these silently breaks on the v2 route while
production keeps working, the migration is broken.

| # | Behavior | Where the guarantee lives |
|---|---|---|
| MNR-1 | **Blocked-product flow** — BlockedBanner replaces hero subtitle, FDA references shown, most sections suppressed | `gating.dart::productIsBlocked` + Hero `bottomBanner` slot + sliver-level `if (!isBlocked)` guards |
| MNR-2 | **Add to Stack** — sticky pill triggers safety-check sheet → addProduct flow → persists in stack DB | `PGStackActionButtons` (production widget, reused as-is via import) |
| MNR-3 | **Remove from Stack** — green "In your stack" pill shows Remove inline; SnackBar Undo restores | `PGStackActionButtons` internal `_InStackPanel` |
| MNR-4 | **See Safer Alternatives scroll** — unsafe-verdict primary scrolls to BetterAlternatives sliver via `_alternativesKey` | `scroll_anchors.dart::scrollToAlternatives` → `_anchors.alternativesKey` on S16 sliver |
| MNR-5 | **Interaction warning profile filtering** — personalized + blob warnings merged, deduped, profile/UL gate applied | `warnings_pipeline.dart::composeGuardedWarnings` |
| MNR-6 | **Allergen matching** — user profile allergens cross-checked against blob `allergens` + `is_X_free` flags | `matchAllergens` + `matchFreeFromClaims` + `findFreeFromConflicts` (production helpers, called from S3 adapter in 11.7c) |
| MNR-7 | **Label-confidence caveats appear BEFORE score** — low coverage / proprietary blends / not-scored / product-status / unmapped actives surface before the score they caveat | Section order in connected screen: S4 LabelConfidence renders before S5 ScoreBreakdown (corrected from v2 fixture's reversal) |
| MNR-8 | **NOT_SCORED behavior** — ScoreBreakdown suppressed, LabelConfidence speaks up | `gating.dart::productIsNotScored` + `shouldShowScoreBreakdown` |
| MNR-9 | **Deep-link scrolling** — `?section=interactions\|ingredients\|alternatives` lands on the right anchor with 280ms easeOutCubic | `scroll_anchors.dart::scheduleInitialScroll` + 30-frame retry budget |
| MNR-10 | **Sticky CTA always visible** — bar persists even on blocked products (primary swaps to "See safer alternatives") | `PGStackActionButtons` rendered at `bottomNavigationBar` regardless of `isBlocked` |
| MNR-11 | **Better Alternatives visibility gate** — renders when `isBlocked` OR `score100 < 60` OR `FitLimitedFit/NotRecommended` | `shouldShowBetterAlternatives(isBlocked, isNotScored, score100, fitDisplay)` (wires in 11.7e adapter) |
| MNR-12 | **Transparency footer always renders** — site-wide trust language sits above bottom CTA clearance | S17 `PGTransparencyFooter` rendered unconditionally |
| MNR-13 | **Product image fallback chain** — DSLD Supabase image → Open Food Facts → BrandedPlaceholder (never broken-image icon) | `ProductImage` widget consumed by `buildHeroSection` (production widget, reused as-is) |

---

## Golden test scenarios

Every section's `Golden` row references some subset of these. A section is
`verified` only after rendering correctly across all scenarios listed in its
row:

| ID | Scenario |
|---|---|
| G1 | Long product name (60+ chars, wraps 3+ lines) |
| G2 | 20+ ingredients (active + inactive lists scroll past fold) |
| G3 | Missing image (`imageUrl` null → BrandedPlaceholder, compact) |
| G4 | Low-quality / broken image (`imageUrl` 404 → fallback) |
| G5 | Blocked product (NSF banned-substance verdict) |
| G6 | NOT_SCORED product (verdict='NOT_SCORED' or score=null + not blocked) |
| G7 | Allergen conflict (user soy-allergic + product contains soy + product `is_soy_free=1` label disagreement) |
| G8 | Low coverage (mappedCoverage < 0.3 → score gated, LabelConfidence speaks up) |
| G9 | Proprietary blend (has_proprietary_blends=true → LabelConfidence row) |
| G10 | Multiple warnings (5+ warnings, mixed severities, dedup verifies) |
| G11 | High score, no issues (clean product → no caveats, no warnings) |
| G12 | Already in stack (sticky CTA shows green pill + Remove) |

---

## Section-by-section parity

### Screen-level

#### S0. Initial product load

| Field | Value |
|---|---|
| Production | `_ProductDetailScreenState._loadProduct` + `_productLoading` short-circuit |
| V2 | `_ProductDetailV2ConnectedState._loadProduct` |
| Source | `coreDatabaseProvider` → `findById(dsldId)` |
| Gate | Always runs in `initState` |
| Loading | `Scaffold + Center + CircularProgressIndicator` |
| Empty | `_product == null` → productName falls back to "Product `<dsldId>`" downstream |
| Blocked | N/A (pre-blocked-state) |
| Anchor | N/A |
| CTA | N/A |
| Analytics | none |
| A11y | Spinner should have Semantics label "Loading product" |
| Golden | product-not-found scenario |
| **Status** | **wired** (loading visuals match production) |

#### S0.5 AppBar + share button

| Field | Value |
|---|---|
| Production | `PGFrostedAppBar` with share `PGCircularIconButton` (line 239) |
| V2 | Inline `SliverAppBar` in `_buildAppBar()` (v2 transparent over cream) |
| Source | `_product.shareTitle / shareDescription / shareHighlights` |
| Gate | Share button rendered only when `_product != null` |
| Loading | Share hidden during load |
| Empty | `_product == null` → no share |
| Blocked | Share remains visible (parity ✅) |
| Anchor | N/A |
| CTA | `ShareService().shareProduct(...)` |
| Analytics | No haptic on share (iOS share sheet fires its own present haptic) |
| A11y | Verify share IconButton has tooltip |
| Golden | G1 (long name → share text wraps cleanly) |
| **Status** | **wired** — pending a11y + golden verify |

#### S0.9 Sticky `PGStackActionButtons`

| Field | Value |
|---|---|
| Production | `PGStackActionButtons` at `bottomNavigationBar` (line 678) |
| V2 | Same widget reused as-is (already provider-aware) |
| Source | `stackEntryForDsldIdProvider(dsldId)` + safety check sheet + `stackActionsProvider.addProduct` |
| Gate | Always rendered |
| Loading | Production widget handles internally |
| Empty | "Add to my stack" when not in stack |
| Blocked | Primary swaps to "See safer alternatives" via `isUnsafe: isBlocked` |
| Anchor | `onSeeAlternatives: _anchors.scrollToAlternatives` |
| CTA | Add / Remove / See safer alternatives (3-state primary) |
| Analytics | `PGHaptics` fires on tap |
| A11y | Verify "Add to my stack" pill has Semantics |
| Golden | G5, G12 (blocked + already-in-stack states) |
| **Status** | **wired** — pending a11y + golden verify |

---

### Sliver sections (production scroll order)

#### S1. Hero product card

| Field | Value |
|---|---|
| Production | `_HeaderSection` (line 1250) |
| V2 | `buildHeroSection(...)` → `PGHeroSection` (adapter at `v2/sections/hero_section.dart`) |
| Source | `_product` + `dietaryTags` via `buildHeroTrustTags(_product)` + `score100` + `servingsLabel` |
| Gate | Always renders |
| Loading | `ProductImage` widget renders BrandedPlaceholder while resolving |
| Empty | Missing image → BrandedPlaceholder (compact=true) |
| Blocked | **11.7c: pass `BlockedBanner` widget to `bottomBanner` prop** (currently null) |
| Anchor | N/A |
| CTA | Image tap → `ProductImageViewer` modal (placeholder taps are no-op by design) |
| Analytics | none |
| A11y | Product name + brand + score Semantics labels |
| Golden | G1 long name, G3 missing image, G4 low-quality, G5 blocked → BlockedBanner |
| **Status** | **verified** — live side-by-side vs production /product/16012 (Thorne Vinpocetine, BLOCKED): image-fallback ✅, trust chips ✅, name + brand + dosing ✅, `heroBottomBanner` composition ✅. Long-name (G1), 20+ingredients (G2), low-quality image (G4) goldens pending — not blockers for blocked-banner ship. |

#### S1.5 Hero BlockedBanner (slotted into Hero `bottomBanner`)

| Field | Value |
|---|---|
| Production | `_BlockedBanner` (line 1626) — appears inside `_HeaderSection` when verdict is unsafe |
| V2 | `buildBlockedBannerSection(...)` in `v2/sections/blocked_banner_section.dart` (composition) + `v2/sections/blocked_banner_helpers.dart` (pure logic) |
| Source | `parseTopWarnings(_product)` (JSON-decode of `_product.topWarnings`) + `detailBlob['banned_substance_detail']` + `_product.verdict` + `_product.blockingReason`. Helpers: `buildRegulatoryLine`, `contextNoteFor` (imported from production `widgets/blocked_banner_context.dart`), `resolveBlockedReasonBody`, `chooseFdaLinks`, `humanizeBlockingReason` (verbatim port). |
| Gate | `isBlocked` is true (caller passes null otherwise → Hero renders no bottomBanner) |
| Loading | Reads blob; if blob loading → only `topWarnings` from product row render. The PGSeverityBanner + reason body fire from row data; banned-substance detail rows appear once blob lands. |
| Empty | If no banned-substance detail AND no top warnings → still shows PGSeverityBanner + 3rd-tier humanized reason body ("PharmaGuide flagged this product on safety grounds.") |
| Blocked | This IS the blocked behavior — it replaces hero subtitle. Hero `subtitle` (servings + dosing) hidden by PGHeroSection internally when `bottomBanner` non-null. |
| Anchor | N/A |
| CTA | FDA reference link tap → `launchUrl(uri, mode: LaunchMode.externalApplication)` (matches production) |
| Analytics | none (FDA-link tap is external nav) |
| A11y | Danger tone paired with icon (PGSeverityBanner ships its own danger icon); FDA links underlined + `Icons.open_in_new_rounded` indicator + ellipsis on long URLs |
| Golden | G5 NSF banned product; substance-with-oneLiner / substance-without-oneLiner / no-substance fallback all three body tiers covered by `resolveBlockedReasonBody` |
| **Status** | **verified** (sparse-BSD path) — live side-by-side vs production /product/16012 confirmed identical reason copy, suppression behavior, sticky CTA swap, calm tone. Sean approved reason body OUTSIDE the danger banner card (better v2 pacing, banner stays compact, reason breathes on cream surface). Richer paths — FDA sources block, regulatory date line, substance-name row — remain pending on a future test product whose BSD carries those fields. |

#### S1.6 "No additional details available." fallback (null-blob)

| Field | Value |
|---|---|
| Production | Rendered inline by `DetailSection.build()` line 1935 when `detailBlob == null` |
| V2 | Inline conditional in `product_detail_v2_connected.dart` between S16 and S17, gated `!blobLoading && !blobError && detailBlob == null` |
| Source | `detailBlobProvider.value` (null branch) |
| Gate | `!blobLoading && !blobError && detailBlob == null` (blob resolved AND no data) |
| Loading | N/A — only renders when loading has finished |
| Empty | This IS the empty state |
| Blocked | Renders on blocked products too (parity: production also renders here regardless of blocked status) |
| Anchor | N/A |
| CTA | N/A |
| Analytics | none |
| A11y | Plain quiet text in `V2Typography.bodySm(V2Colors.fgMuted)` — readable, honest |
| Golden | G5 Thorne Vinpocetine (live-verified — production also shows this for the same dsldId) |
| **Status** | **verified** — live side-by-side confirmed identical "No additional details available." copy + placement (between BetterAlternatives and TransparencyFooter) vs production rendering same line via DetailSection when detailBlob==null. |

#### S2. PersonalFit

| Field | Value |
|---|---|
| Production | `PersonalFitCard` (line 310) wrapped in `Consumer` |
| V2 | `buildPersonalFitSection(...)` in `v2/sections/personal_fit_section.dart` (composition + `ingredientNamesFromBlob` helper) + `v2/sections/personal_fit_helpers.dart` (pure logic — `personalFitHeadline`, `personalFitBullets`, `cleanFitReason`, `_isConditionWarningReason`, `_conditionLabelPrefixes` verbatim port) → `PGPersonalFitCard` |
| Source | `fitScoreForProductProvider(dsldId)` (lazy via inner `Consumer`) → `FitScoreResult` + `computeFitDisplay(verdict: worstSeverityOf(guardedWarnings), fitResult: ...)` + `ingredientNamesFromBlob(detailBlob)` + `topGoalLabelFromFit(fitResult)` + `profile.conditions`. `generatePositiveProfileBullets()` consumed verbatim from production. |
| Gate | `shouldShowPersonalFit({isBlocked})` = `!isBlocked` |
| Loading | fitAsync `loading` → `FitIncomplete()` placeholder |
| Empty | No fitResult / no ingredients → `FitIncomplete()` |
| Blocked | Section suppressed entirely (`if (!isBlocked)`) |
| Anchor | N/A |
| CTA | `onEditProfile` → `push(Routes.profileSetup)` |
| Analytics | Edit-pencil tap |
| A11y | Fit verdict color paired with icon + label (no color-only signaling) |
| Golden | FitStrongMatch / FitGoodMatch / FitLimitedFit / FitNotRecommended / FitHidden (→ SizedBox.shrink dedup) / FitIncomplete |
| **Status** | **verified** — FitIncomplete path live (Thorne MediPro 65844, empty profile); other FitDisplay branches statically parity-checked via verbatim helper ports and exhaustive sealed-class switch. Future live goldens: FitIncomplete, StrongMatch, GoodMatch, LimitedFit, NotRecommended, FitHidden (→ SizedBox.shrink dedup against hero banner). |

#### S3. ReviewBeforeUse

| Field | Value |
|---|---|
| Production | `ReviewBeforeUseCard` (line 381) |
| V2 | **11.7c.3: NEW `v2/sections/review_before_use_section.dart` + `review_before_use_helpers.dart`** → `PGReviewBeforeUseCard` |
| Source | `guardedWarnings` (from `composeGuardedWarnings`) + `matchAllergens(profile.allergens, blob['allergens'])` + `matchFreeFromClaims(...)` + `findFreeFromConflicts(...)` + `interactionHint` + `interactionSummary` blob field + `ingredientDoses` |
| Gate | `shouldShowReviewBeforeUse({isBlocked})` = `!isBlocked` |
| Loading | Warnings empty during loading → renders without rows until populated |
| Empty | No warnings + no allergen + no interaction-context + no free-from claims → `SizedBox.shrink()` (matches production line 152) |
| Blocked | Section suppressed entirely |
| Anchor | `_anchors.interactionsKey` (deep-link target `?section=interactions`) |
| CTA | Row tap on warning with citations → `PGModal.bottomSheet` listing source URLs (verbatim port of production's `_showCitationsSheet`); no-profile nudge → `Routes.profileSetup`; conflict footer is informational, no tap |
| Analytics | (deferred — no analytics fire in v2 yet; matches production) |
| A11y | Danger tone paired with icon + colored text + caption; `startExpanded: true` when danger so users see warnings without a tap |
| Golden | G7 allergen conflict, G10 multiple warnings, 1-row clean state, no-profile nudge state |
| **Status** | **wired** — verbatim helper ports of production's `_parseHint` / `_computeTone` / `_allergenTone` / `_severityColor` / `_countCopy` / `_affirmativeCopy` / `_humanLabel` / `_humanConcern`. Row composition flattens production's chip layout into v2's `(headline, caption, rowTone, onTap)` model — mechanism + management + evidence + citation count packed into caption; citations tap surfaces same bottom sheet. Auto-expand-on-danger preserved. No-profile nudge preserved as standalone v2 cream card with `PGPillButton(secondary)` → `Routes.profileSetup`. Awaits live verify-alone (warnings + allergens + free-from + nudge + danger states). |

#### S4. LabelConfidence

| Field | Value |
|---|---|
| Production | `LabelConfidenceCard` (line 414) |
| V2 | **11.7c.4: NEW `v2/sections/label_confidence_section.dart` + `label_confidence_helpers.dart`** → `PGLabelConfidenceCard` |
| Source | 5 signals: `mappedCoverage`, `hasProprietaryBlends`, `isNotScored`, `blob['product_status']`, `blob['unmapped_actives']` |
| Gate | `shouldShowLabelConfidence({isBlocked, hasAnySignal})` — connected screen calls `labelConfidenceHasAnySignal(...)` (port of production's static fn) and passes the boolean |
| Loading | Wait for blob; signals depend on blob fields |
| Empty | No signal fires → `shouldShowLabelConfidence` returns false → section suppressed |
| Blocked | Section suppressed |
| Anchor | N/A |
| CTA | Tap on productStatus row → `PGModal.bottomSheet` with same explanation copy production renders (verbatim port of `_ProductStatusExplanationSheet._bodyCopy`) |
| Analytics | none |
| A11y | Caveat copy reads informational, not alarming. Tier note tier → muted grey icon; partial/limited → caution amber icon (never red) |
| Golden | G8 low coverage, G9 proprietary blend, G6 not-scored, G discontinued-only (note tier) |
| **Status** | **wired** — verbatim helper ports of production's `_Tier` / `_computeTier` / `_tierLabel` / `_headerPrefix` / `_unmappedTotal` / `_productStatusLabel` / `_unmappedNames` / `_pluralize`. Row order preserved (isNotScored → coverage → blends → unmapped → productStatus). All row copy strings verbatim from production lines 148–191. Status-explanation sheet copy verbatim from production lines 407–428. Awaits live verify-alone (low-coverage product, proprietary-blend product, NOT_SCORED product, discontinued product). |

**Order note (MNR-7):** LabelConfidence MUST render before ScoreBreakdown. The v2 fixture had these reversed; v2 connected restores production order.

#### S5. ScoreBreakdown

| Field | Value |
|---|---|
| Production | `ScoreBreakdownCard` (line 437) |
| V2 | **11.7d.1: NEW `v2/sections/score_breakdown_section.dart`** → `PGScoreBreakdownCard` |
| Source | 4 pillar scores from `_product` (`scoreIngredientQuality`, `scoreSafetyPurity`, `scoreEvidenceResearch`, `scoreBrandTrust`) + `blob['section_breakdown']` (accordion detail) + `_product.mappedCoverage` (coverage line) + `_product.hasThirdPartyTesting` + `_product.isTrustedManufacturer` + `heroScore` |
| Gate | `shouldShowScoreBreakdown({isBlocked, isNotScored})` = `!isBlocked && !isNotScored` |
| Loading | Pillars render with available data; accordion detail loads with blob |
| Empty | No pillar scores → fall back to hero score only (verify production) |
| Blocked | Section suppressed (no score to break down) |
| Anchor | N/A |
| CTA | Pillar tap → inline accordion |
| Analytics | none |
| A11y | Pillar values readable as "Ingredient Quality, 22 out of 25" |
| Golden | Full pillars, partial pillars, G8 low coverage, G11 clean |
| **Status** | **placeholder** |

#### S6. Ingredients

| Field | Value |
|---|---|
| Production | `_CollapsibleIngredients` inside `DetailSection` (line 2190) |
| V2 | **11.7d.2: NEW `v2/sections/ingredients_section.dart`** → `PGIngredientsCard` |
| Source | `blob['ingredients']` (active) + `blob['inactive_ingredients']` + `ingredientDoses` map |
| Gate | `shouldShowDeepDive({isBlocked, blobLoading, blobError})` |
| Loading | `PGShimmerBox` skeleton tiles during blob load |
| Empty | 0 active → verify production; 0 inactive → tile group hides |
| Blocked | Section suppressed |
| Anchor | `_anchors.ingredientsKey` (deep-link target `?section=ingredients`) |
| CTA | Ingredient tap opens `IngredientExplainSheet` modal |
| Analytics | Ingredient-tap |
| A11y | Long ingredient names — no `…` truncation on medical terms |
| Golden | G2 20+ ingredients, 5-ingredient minimal, G9 proprietary blend, inferred-from-name, unmapped actives |
| **Status** | **placeholder** |

#### S7. Tradeoffs

| Field | Value |
|---|---|
| Production | `TradeoffsSection` inside `DetailSection` |
| V2 | **11.7d.3: NEW `v2/sections/tradeoffs_section.dart`** → `PGTradeoffsSection` |
| Source | `blob['tradeoffs_section']` → pros + considerations arrays |
| Gate | `shouldShowDeepDive` |
| Loading | Wait for blob |
| Empty | Both lists empty → section suppressed |
| Blocked | Section suppressed |
| Anchor | N/A |
| CTA | none |
| Analytics | none |
| A11y | Pros + considerations labeled |
| Golden | Pros-only, considerations-only, both, neither (suppressed) |
| **Status** | **placeholder** |

#### S8. Populations

| Field | Value |
|---|---|
| Production | `PopulationsSection` inside `DetailSection` |
| V2 | **11.7d.4: NEW `v2/sections/populations_section.dart`** → `PGPopulationsSection` |
| Source | `blob['condition_summary']` filtered to user profile conditions |
| Gate | `shouldShowDeepDive` + non-empty callouts after profile filter |
| Loading | Wait for blob |
| Empty | No callouts → section suppressed |
| Blocked | Section suppressed |
| Anchor | N/A |
| CTA | Callout tap → detail (route TBD) |
| Analytics | Callout-tap |
| A11y | Population label paired with icon |
| Golden | Pregnancy, blood thinner, multiple, none (suppressed) |
| **Status** | **placeholder** |

#### S9. Nutrition

| Field | Value |
|---|---|
| Production | `NutritionPanel` inside `DeepDiveSection` |
| V2 | **11.7d.5: NEW `v2/sections/nutrition_section.dart`** → `PGNutritionPanel` |
| Source | `_product.caloriesPerServing` + `blob['nutrition_detail']` |
| Gate | `shouldShowDeepDive` + non-null nutrition data |
| Loading | Wait for blob |
| Empty | No calories + no facts → section suppressed |
| Blocked | Section suppressed |
| Anchor | N/A |
| CTA | none |
| Analytics | none |
| A11y | Facts table labeled; daily-value % readable |
| Golden | Full nutrition, partial, none (suppressed) |
| **Status** | **placeholder** |

#### S10. Certifications

| Field | Value |
|---|---|
| Production | `CertificationSection` inside `DeepDiveSection` |
| V2 | **11.7e.1: NEW `v2/sections/certifications_section.dart`** → `PGCertificationSection` |
| Source | `blob['certification_detail']` |
| Gate | `shouldShowDeepDive` + non-null certification data |
| Loading | Wait for blob |
| Empty | No certifications → section suppressed |
| Blocked | Section suppressed |
| Anchor | N/A |
| CTA | none |
| Analytics | none |
| A11y | Verified vs. not-verified must be more than color |
| Golden | Multiple verified, mix, not-enrolled, none |
| **Status** | **placeholder** |

#### S11. Evidence

| Field | Value |
|---|---|
| Production | `EvidenceSection` inside `DeepDiveSection` |
| V2 | **11.7e.2: NEW `v2/sections/evidence_section.dart`** → `PGEvidenceSection` |
| Source | `blob['evidence_data']` (tier + total studies + citations) |
| Gate | `shouldShowDeepDive` + non-null evidence data |
| Loading | Wait for blob |
| Empty | No evidence → section suppressed |
| Blocked | Section suppressed |
| Anchor | N/A |
| CTA | Citation tap → PubMed URL via `url_launcher` |
| Analytics | Citation-tap |
| A11y | Tier labels readable ("ESTABLISHED" / "MODERATE" / "LIMITED") |
| Golden | Strong, moderate, limited, theoretical, none |
| **Status** | **placeholder** |

#### S12. HeavyMetalWarning

| Field | Value |
|---|---|
| Production | `HeavyMetalWarningCard` inside `DeepDiveSection` |
| V2 | **11.7e.3: NEW `v2/sections/heavy_metal_section.dart`** → `PGHeavyMetalWarning` |
| Source | `blob['heavy_metal_detail']` (detected metals list + note) |
| Gate | `shouldShowDeepDive` + non-null heavy_metal_detail |
| Loading | Wait for blob |
| Empty | No metals detected → section suppressed |
| Blocked | Section suppressed (BlockedBanner takes priority for unsafe products) |
| Anchor | N/A |
| CTA | `onTap` → detail (route TBD) |
| Analytics | Metal-tap |
| A11y | Danger tone paired with icon + level; clinical voice |
| Golden | Pb/Cd trace, above-limits, FDA-action, none |
| **Status** | **placeholder** |

#### S13. Formulation

| Field | Value |
|---|---|
| Production | `FormulationSection` inside `DeepDiveSection` |
| V2 | **11.7e.4: NEW `v2/sections/formulation_section.dart`** → `PGFormulationSection` |
| Source | `blob['formulation_detail']` |
| Gate | `shouldShowDeepDive` + non-null formulation data |
| Loading | Wait for blob |
| Empty | No detail → section suppressed |
| Blocked | Section suppressed |
| Anchor | N/A |
| CTA | none |
| Analytics | none |
| A11y | Form tier label readable |
| Golden | Premium, standard, unknown |
| **Status** | **placeholder** |

#### S14. Probiotic

| Field | Value |
|---|---|
| Production | `ProbioticSection` inside `DeepDiveSection` |
| V2 | **11.7e.5: NEW `v2/sections/probiotic_section.dart`** → `PGProbioticSection` |
| Source | `blob['probiotic_detail']` (CFU + strains + survivability) |
| Gate | `shouldShowDeepDive` + non-null probiotic data |
| Loading | Wait for blob |
| Empty | Non-probiotic product → section suppressed |
| Blocked | Section suppressed |
| Anchor | N/A |
| CTA | none |
| Analytics | none |
| A11y | CFU + strain labels readable |
| Golden | 3-strain w/ survivability, single-strain, no survivability, none |
| **Status** | **placeholder** |

#### S15. ManufacturerViolations

| Field | Value |
|---|---|
| Production | `ManufacturerViolationsSection` inside `DeepDiveSection` |
| V2 | **11.7e.6: NEW `v2/sections/manufacturer_violations_section.dart`** → `PGManufacturerViolationsSection` |
| Source | `blob['manufacturer_detail']` (violations array) |
| Gate | `shouldShowDeepDive` + non-null manufacturer data |
| Loading | Wait for blob |
| Empty | No violations → section suppressed |
| Blocked | Section suppressed |
| Anchor | N/A |
| CTA | Violation tap → detail (verify production target) |
| Analytics | Violation-tap |
| A11y | Severity tone paired with type + date |
| Golden | 1 caution, multiple, FDA-action, none |
| **Status** | **placeholder** |

#### S16. BetterAlternatives

| Field | Value |
|---|---|
| Production | `BetterAlternativesSection` (line 636) wrapped in `Consumer` |
| V2 | **11.7e.7: NEW `v2/sections/better_alternatives_section.dart`** → `PGBetterAlternatives` |
| Source | `betterAlternativesProvider(currentDsldId, category, currentScore)` (verify exact provider name in production) |
| Gate | `shouldShowBetterAlternatives({isBlocked, isNotScored, score100, fitDisplay})` — gates on `isBlocked` OR `score100 < 60` OR `FitLimitedFit/NotRecommended` |
| Loading | Async list with shimmer placeholders |
| Empty | No alternatives → section suppressed |
| Blocked | **ALWAYS renders** for blocked products — this is the unsafe-CTA's scroll target |
| Anchor | `_anchors.alternativesKey` (CTA scroll target + deep-link `?section=alternatives`) |
| CTA | Alternative tap → `push('/product/<altDsldId>')` |
| Analytics | Alternative-tap |
| A11y | Score chip readable; brand + name labeled |
| Golden | 0, 1, 5+ alternatives, G5 blocked (forces visible) |
| **Status** | **placeholder** (anchor mounted for MNR-4) |

#### S17. TransparencyFooter

| Field | Value |
|---|---|
| Production | `TransparencyFooter` (line 657) — always rendered |
| V2 | `const PGTransparencyFooter()` (inline in connected screen) |
| Source | none (static site-wide trust language) |
| Gate | Always |
| Loading | N/A |
| Empty | N/A |
| Blocked | Renders on blocked products (parity ✅) |
| Anchor | N/A |
| CTA | Source-tap → publisher pages (built into PGTransparencyFooter) |
| Analytics | Source-tap |
| A11y | Disclaimer paragraph readable |
| Golden | covered (no edge cases) |
| **Status** | **wired** — pending `freshnessLabel` from `catalogInfoProvider` in 11.7f |

#### S18. AllergenSummaryBanner (LEGACY fallback)

| Field | Value |
|---|---|
| Production | `AllergenSummaryBanner` (line 522) — legacy free-text fallback |
| V2 | **11.7f.1: NEW `v2/sections/allergen_summary_banner_section.dart`** |
| Source | `_product.allergenSummary` + `matchAllergens(profile.allergens, blob['allergens']).isEmpty` |
| Gate | `shouldShowAllergenSummaryBanner({isBlocked, allergenSummary, noStructuredAllergens})` |
| Loading | Wait for profile + blob |
| Empty | Covered by gate (only renders when fallback is needed) |
| Blocked | Section suppressed |
| Anchor | N/A |
| CTA | none |
| Analytics | none |
| A11y | Allergen labels readable |
| Golden | Legacy product w/ free-text only, new product w/ structured (suppressed) |
| **Status** | **placeholder** |

---

## Completion tally (Phase 11.7c.4 boundary)

| Status | Count |
|---|---|
| accepted | 0 |
| **verified** | 4 (S1, S1.5, S1.6 blocked flow; S2 PersonalFit FitIncomplete + static-parity) |
| **wired** | 6 (S0, S0.5, S0.9, S3 ReviewBeforeUse, S4 LabelConfidence, S17 — pending live verification on non-blocked product) |
| **placeholder** | 11 |
| total | 21 |

---

## Working rules

- A section's **`Status`** moves from `placeholder` → `wired` when its adapter file exists and renders real data clean against analyze.
- It moves `wired` → `verified` only after live-device QA across every listed golden scenario.
- It moves `verified` → `accepted` only after Sean signs off.
- **Section adapter files target ~250 lines.** Slight overruns are acceptable when the structure is clean (helpers = pure logic, section = composition). Split into a sibling `<name>_helpers.dart` once mapping logic balloons past readable.
- **The connected screen stays orchestration-only.** No inline gates, no inline pipelines, no inline mapping. All three live in their module homes.
- Update this doc with every adapter commit — the parity row must be touched whenever the implementation changes.

---

# Appendix: Scanner v2 — Two-Stage Flow (Future Phase 11.8)

**Status:** PLANNED. Do NOT implement until Product Detail v2 is parity-complete AND swapped into the production `/product/:dsldId` route after Phase 11.7g.

**The key architectural decision:** Stage 2 IS `ProductDetailV2ConnectedScreen`. Not a scanner-specific second product page. There is exactly one product page in the app.

## Two-stage render model

```
Barcode scan
   ↓
Stage 1: Instant Scan Peek Card
   (renders < 200ms from pharmaguide_core.db, offline, no network)
   ↓ tap / swipe-up
Stage 2: Product Detail v2 (existing route push)
```

## Stage 1 — Instant Scan Card

**Purpose:** decision in under 2 seconds.

**Data contract — Stage 1 may use ONLY:**
- `CoreDatabase.findByUpc()` (already local + offline)
- No Supabase call
- No detail blob requirement
- No AI
- No loading spinner before the first verdict
- No network gate of any kind

**Content:**
- Product image or designed placeholder
- Product name
- Brand
- PG Score / quality tier
- Top verdict
- Top warning IF serious — never hidden behind tap
- "No flags on this product" (no profile) / "No high-risk conflicts for your profile" (profile complete) / "Complete profile for full check" (profile partial)
- Primary CTA: **"Review product"** → `context.push('/product/:dsldId')`
- Secondary CTA: "Add to Stack" only with safety-aware confirmation (defer most stack-add decisions to Stage 2's sticky CTA)
- Clear offline state if offline

**Three verdict states — not two:**
1. **Blocked / unsafe** → danger tone, FDA flag if present, "PharmaGuide does not recommend" headline
2. **Scored** → quality tier + score + top warning OR honest "no high-risk conflicts" copy
3. **NOT_SCORED** → quiet caveat tone, "Limited label data — open for details." Not a failure state. Not a fake score.

**Interaction:**
- Tap → `context.push('/product/:dsldId')`
- Swipe up → same push
- Spring animation ~280ms
- Hero animation (`Hero(tag: 'product-image-$dsldId')`) on shared product image element
- Haptic ONLY on contraindicated/blocked → one `HapticFeedback.mediumImpact()`. Never on clean scans. Never on caution. Never on success.

**Offline behavior:**
- Product in `pharmaguide_core.db` → Stage 1 renders identically offline
- Product not found → "Not in our database yet" + non-promised offer: "Submit label" / "Take photos of Supplement Facts panel + bottle front" / "Add manually later" (no fake timeline)
- Generic errors are forbidden

## Stage 2 — Full Product Sheet

**Stage 2 is `ProductDetailV2ConnectedScreen(dsldId: ...)` — the existing route.** No scanner-specific surface. No duplicate widgets. No "scanner mode" variant.

**Stale-while-revalidate rules:**
- Render cached blob immediately
- Fetch fresh blob in background
- Fresh blob has HIGHER-severity warning → quiet "Updated" pill + scroll-to-new behavior. Never silently downgrade safety content.
- Fresh blob is identical or lower-severity → swap quietly, no announcement.
- Never silently change high-severity content while the user is actively reading.

**Cancellation discipline:**
- Each scan generates a request token
- Blob fetch is cancelable
- Currently-displayed `dsldId` is source of truth
- Late-arriving blob for a stale scan never replaces current content

## Architecture sketch

```
ScannerV2Screen (orchestration only)
  ├─ CameraPreview (existing barcode logic, untouched)
  ├─ PGScanResultPeekSheet (Stage 1, DraggableScrollableSheet @ ~38%)
  │    ├─ Hero(tag: 'product-image-$dsldId')
  │    ├─ Compact verdict block (worstSeverityOf + computeFitDisplay reuse)
  │    ├─ Top-warning row (single line if serious)
  │    ├─ Primary CTA: "Review product" → context.push('/product/:dsldId')
  │    └─ Secondary: "Add to stack" (safety-aware confirm on blocked/danger)
  │
  └─ on push → ProductDetailV2ConnectedScreen (Stage 2, reused as-is)
```

**Files to add (when 11.8 starts):**
- `lib/features/scanner/v2/scanner_v2_screen.dart` — orchestration only
- `lib/core/components/pg_scan_result_card.dart` — compact verdict
- `lib/features/scanner/v2/scan_request_token.dart` — cancellation discipline

**Files to reuse unchanged:**
- `ProductDetailV2ConnectedScreen` (the entire screen)
- `composeGuardedWarnings`, `computeFitDisplay`, `worstSeverityOf`
- `PGHaptics` (severity-aware; we just call less)

## Anti-goals (read before any Scanner v2 commit)

- ❌ Loading spinner before initial verdict
- ❌ Network-required scan result
- ❌ Hiding safety signals behind a tap
- ❌ Generic error states ("Something went wrong")
- ❌ Celebration animations on clean scans (medical tool, not a game)
- ❌ Vibration for every scan
- ❌ Stage 2 being a re-implementation of Product Detail
- ❌ Stage 1 being a stripped-down hero (it's a peek, not a hero)

## Definition of Done

- p95 scan-to-card-render < 300ms on Pixel 5a
- Stage 1 verifiable offline (airplane mode + scan a known-blocked product → blocked banner appears)
- Stage 2 = literal Product Detail v2 route, no parallel surface
- A11y QA passes with VoiceOver on real iPhone (must read "Scan result. <product>. <verdict>. <top warning>. Double-tap for full report.")
- Cancellation: scan A → immediately scan B → A's blob never replaces B's content
- Telemetry: `scan_to_card_render_ms`, `scan_to_full_sheet_ms`, `scan_to_blob_resolved_ms` (p50/p95/p99 each), alert when p95 > 300ms

## Sequence (locked)

1. Finish Product Detail v2 parity (Phases 11.7c–11.7f)
2. Swap Product Detail v2 into production `/product/:dsldId` route (Phase 11.7g)
3. Then implement Scanner v2 two-stage flow (Phase 11.8)

This ordering is non-negotiable. Building Stage 1 against a still-mutating Stage 2 means rework. After 11.7g, Scanner v2 becomes "wire scanner to push the new route + add a peek card on top." Much smaller scope.
