# Product Detail v2 — TestFlight Review Checklist

**Cycle date:** 2026-05-16 → 2026-05-?? (one TestFlight pass)
**Branch:** `design/v2-mobile-polish`
**Build target:** TestFlight IPA with `--dart-define=USE_V2_PRODUCT_DETAIL=true`
**Build command:** `make build-ipa-v2pd`
**Approval gate:** After one clean pass, promote `USE_V2_PRODUCT_DETAIL` default to `true` in `app.dart` (Phase 11.7g.3).

---

## What this build is

Product Detail v2 served on the production `/product/:dsldId` route,
flipped via the staged toggle. The legacy `ProductDetailScreen` is
NOT deleted — it's still imported and reachable; only the route
mapping serves v2 when the flag is on. Rolling back is one flag flip.

**No other v2 work in this build** beyond what's already on
`design/v2-mobile-polish` (Home, Stack, Profile, Splash, Auth, etc.
already swapped earlier in Phases 11.0–11.5).

---

## Review focus — products to scan

If a tester has access to these (or anything similar), please scan
or open them via the search and walk the entire page:

- [ ] **Long-name products** (50+ char product names) — verify hero
      title wrap + truncation feels intentional, not broken.
      Reference: `178767` Spring Valley Adults And Children 3+
      Gummies Vitamin C Supplement 180 mg.
- [ ] **Missing-image / low-quality image products** — placeholder
      should be the designed "Image not yet available" card, NOT a
      broken-image icon.
- [ ] **Blocked products** — Vinpocetine, Memoractiv, etc.
      Reference: `16012` Thorne Vinpocetine, `16072` Memoractiv.
      Verify FDA banned content + sticky CTA "See safer
      alternatives" + suppression of mid-page sections.
- [ ] **Discontinued products** — compact one-row LabelConfidence
      note tier. Reference: `65844` Thorne MediPro Vegan.
- [ ] **Products with populated ingredients blob** — active list +
      inactive count badge + tap-to-explain modal. Form chips
      (Excellent / Good / Fair / Poor) + dose labels visible.
- [ ] **Products with certifications** — Thorne / Pure Encapsulations
      products. Reference: `65844` (Purity Verified, Heavy Metal
      Tested, Label Accuracy Verified, NSF Sport, USP Verified).
- [ ] **Products with probiotic strains** — verify "CFU not
      disclosed" surfaces when missing, otherwise per-strain CFU
      renders. Reference: `65844` MediPro Vegan multi-strain shake.
- [ ] **Products with heavy metal warnings** — calm caution callout
      (not red) listing metals + Prop 65 / EPA footnote.
- [ ] **Products with manufacturer violations** — FDA violation rows
      sorted critical → high → moderate with severity-tinted dot.
- [ ] **Legacy-allergens product** (free-text `allergenSummary`, no
      structured `blob.allergens`) — S18 caution banner should fire
      below LabelConfidence.
- [ ] **Better Alternatives result list** — when the gate fires
      (score < 60 OR Limited/NotRecommended fit). The relevance
      bug is tracked separately in `knowledge/v2-audit-backlog.md` —
      we are NOT fixing it in this cycle, only watching for layout
      / tap-navigation regressions.

---

## Acceptance criteria — before promoting toggle default

All of these must hold across the test set for the cycle to count
as "clean":

- [ ] **No missing safety surfaces.** Every blocked product shows
      the BlockedBanner with FDA content. Every product with
      profile-matched warnings shows the ReviewBeforeUse warning
      rows. No clinical surface silently dropped.
- [ ] **No broken sticky CTA.** "Add to my stack" / "See safer
      alternatives" tap target works on every state (safe, blocked,
      not-scored, missing-image). Scroll-to-alternatives behavior
      lands on the correct anchor.
- [ ] **No blank sections that should suppress.** S6–S15 sections
      hide cleanly when their blob signals are absent (SizedBox.shrink).
      No empty cards, no "Section: Unavailable" placeholders.
- [ ] **No ugly hero wrapping.** Long product names truncate at 3
      lines max. Brand + serving subtitle doesn't overlap chips.
- [ ] **No excessive chip wrapping.** Trust chips grouped into 2
      tidy rows (certifications + dietary), never 3+ messy rows.
- [ ] **No regression in Add to Stack / Remove from Stack.** Sticky
      CTA + stack state stays consistent with the legacy build's
      behavior. Add → verify in Stack tab. Remove → verify hero
      CTA reverts to "Add".
- [ ] **No regression in blocked-product flow.** Blocked products
      land on BlockedBanner; sticky CTA reads "See safer
      alternatives"; scroll-to-alternatives anchor still works (or
      degrades cleanly when category is null — same as production).
- [ ] **No route crash from rare blob shapes.** A blob with
      unexpected nesting (heavy_metal_detail.signals shape, blend
      grouping, clinical_strains with null cfu_per_day) doesn't
      throw. Sentry should be quiet on Product Detail crashes.
- [ ] **Product Detail feels visually ready on a real iPhone.** Not
      just the simulator. Font rendering, spacing, scroll FPS,
      tap targets all feel polished. Hero compactness reads
      premium, not cramped.

---

## Known issues (not blocking the cycle)

These exist in production today and are NOT new in v2. They are
documented elsewhere and should be ignored during this review
unless they get materially worse:

1. **Better Alternatives recommendation quality** —
   `knowledge/v2-audit-backlog.md` → "Better Alternatives —
   recommendation relevance". v2 renders the same `findAlternatives`
   output as production. Layout regressions DO matter; recommendation
   quality regressions do not (the baseline is already weak).

2. **Better Alternatives null-category suppression** — when a blocked
   product has `primary_category == null` (e.g. Vinpocetine 16012),
   the section renders blank. Production has the same behavior. Not
   a v2 regression.

3. **Long-name truncation** — 88-char names truncate with "..."
   after 3 lines. Acceptable per the v2 hero contract. Compare with
   production behavior — should match.

4. **Tile-render-only gaps (not yet live-verified):**
   - S12 HeavyMetal — needs product with `heavy_metal_detail.signals[]`
   - S15 ManufacturerViolations — needs product with violations
   - S16 BetterAlternatives result list — needs gate-firing product
     with category matches
   - S18 AllergenSummaryBanner — needs legacy product with free-text
     allergenSummary
   This TestFlight cycle is the first real chance to exercise these
   on user-encountered products.

5. **Impeller validation message** — Flutter engine logs an
   `ImpellerValidationBreak` line in dev builds; not user-visible.
   Should be present in both legacy + v2 builds. Not a v2 regression.

---

## Rollback if the cycle fails

The toggle is `--dart-define=USE_V2_PRODUCT_DETAIL`. To roll back:

1. **Immediate (any user):** ship a new TestFlight build with
   `make build-ipa` (no flag) — production route goes back to
   legacy `ProductDetailScreen` instantly.
2. **Codebase:** the toggle plumbing in `app.dart` + `main.dart`
   stays; only the build-time flag changes. No revert needed.

The legacy `ProductDetailScreen` is still imported, the route
table still references it, and the dev `/dev/v2/product/:dsldId`
route stays live for QA regardless of which production route is
serving.

---

## What happens after a clean cycle

When acceptance criteria all hold:

1. Promote `USE_V2_PRODUCT_DETAIL` default to `true` in `main.dart`
   (`bool.fromEnvironment` → `defaultValue: true`). Single-line change.
2. Mark Phase 11.7g.3 complete in `knowledge/product-detail-v2-parity.md`.
3. **STILL DO NOT delete legacy `ProductDetailScreen`** — defer to
   Phase 11.11 cleanup sprint once we have confidence that no other
   call sites need it.
4. Unblock Phase 11.8 Scanner v2 work (which depends on Product
   Detail v2 being stable).

---

## How to file feedback during the cycle

Use the issue tracker / shared doc / Sentry as appropriate. For
each issue:

- Product UPC / dsldId
- Which section (use the S-number from the parity doc:
  `knowledge/product-detail-v2-parity.md`)
- Expected vs actual behavior
- Whether the same issue exists on the legacy route (open same
  product on `/dev/v2/product/:dsldId` vs `/product/:dsldId` with
  the flag off — though both reach v2 in this build; for true
  legacy comparison, install a build without the flag side-by-side)
