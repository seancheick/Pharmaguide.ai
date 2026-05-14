/// # Product Detail v2 — Design Spec
///
/// **Status:** Phase 1 prototype. Lives alongside the production
/// [ProductDetailScreen] until Phase 8 sign-off.
///
/// ---
///
/// ## North Star
/// "I scanned a supplement, and PharmaGuide instantly turned it into a
/// beautiful, clinical-grade report I can understand."
///
/// NOT "Here is a database record with a score on top."
///
/// ---
///
/// ## Acceptance Line (stress test)
/// A product with a long name, missing image, and 20+ ingredients must
/// still look **intentional** — not like an edge case.
///
/// ---
///
/// ## Above-the-fold hierarchy (no scroll required)
/// 1. Product image (1:1 square frame — defined, never floats)
/// 2. Brand (mono caps eyebrow)
/// 3. Product name (Geist Sans, never serif — product names ARE clinical
///    context)
/// 4. Form + serving size (structured metadata pair)
/// 5. Key Takeaway card:
///    - Severity badge + evidence overline
///    - Verdict label (Geist Sans, max 2 lines)
///    - PGScoreRing on the trailing edge
///    - Plain-English explanation (Geist Sans body)
/// 6. Primary CTA: `PGPillButton(primary)` — "Add to Stack" / "Review Stack"
///
/// ---
///
/// ## Image Card Rules
/// - **Default aspect ratio**: 1:1 (square). Override to 4:5 only when
///   the layout has more vertical room than horizontal.
/// - **Border**: 1px outline + soft sm shadow. Never shadow-md or above —
///   the hero image should feel grounded, not floating.
/// - **Missing image**: designed placeholder with `Icons.medication_outlined`
///   + "IMAGE NOT YET AVAILABLE" eyebrow. **Never** a broken-image icon.
/// - **Low-quality image**: same placeholder. Detection happens upstream;
///   if a corrupt URL fails to load, `errorBuilder` falls through.
/// - **Repaint**: wrapped in `RepaintBoundary` (perf guardrail).
///
/// ---
///
/// ## Title Wrapping Rules
/// - Geist Sans (never serif — see typography governance)
/// - Default style: `V2Typography.title(24pt 500)`
/// - **Long-name detection** (`length > 40`): degrades to `titleSm` (20pt)
///   *before* constraining lines.
/// - **maxLines**: 3
/// - **No ellipsis on medical product names** — wrap to next line instead.
/// - **Soft wrap**: enabled (default).
/// - **ALL-CAPS brand handling**: brand renders as `PGEyebrow` mono caps,
///   so user-provided uppercase doesn't bleed into the title hierarchy.
///
/// ---
///
/// ## Ingredient Stack Rules
/// - Replaces "endless vertical tile list" anti-pattern.
/// - **Collapsed limit**: 5 ingredients visible by default.
/// - List length > collapsed limit → "View all (N more)" ghost pill.
/// - List length ≤ collapsed limit → no pill, all rows visible.
/// - **Severity tint**: only when the ingredient has a flagged severity.
///   Most ingredients render quietly with surface bg + outline border.
/// - **Dose**: right-aligned, Geist Mono.
/// - **Tap**: opens explain sheet (wires through `onExplain` callback).
/// - **Expand motion**: `AnimatedSize` over `V2Motion.base` (280ms).
/// - **Empty state**: eyebrow + "No data available for this product yet."
///   (calm, no scary "missing data" framing).
///
/// ---
///
/// ## Clinical Card Sections (each has ONE job)
/// 1. Hero (image + name + brand + meta + Key Takeaway + primary CTA)
/// 2. Quality Score (PGScoreRing + breakdown — Phase 1 prototype shows ring)
/// 3. Your Fit (personalized fit state)
/// 4. Interaction Flags (calm; severity hierarchy via spacing not saturation)
/// 5. Active Ingredients (compact stack)
/// 6. Additive / Inactive Concerns (compact stack with severity tints when relevant)
/// 7. Evidence (mono caps levels)
/// 8. Label & Source Data (PGLabelImage — first-class trust surface)
/// 9. Similar / Better Options (Phase 2+, not v2 Phase 1)
///
/// No section repeats info. 24pt gaps between sections.
///
/// ---
///
/// ## Motion Rules
/// - **Entrance**: no global stagger on Product Detail — the screen is
///   information-dense and stagger would delay clinical scanning.
/// - **Score ring**: animated arc sweep on first paint (640ms emphasized).
/// - **Ingredient expand**: 280ms smooth.
/// - **Press states**: 180ms smooth on the primary CTA.
/// - **No** spring curves. **No** celebratory animations on this screen.
///   Product Detail is a clinical surface; delight belongs on scan-complete
///   and onboarding-finished.
///
/// ---
///
/// ## Severity Communication
/// Hierarchy + spacing > color saturation.
///
/// - Top-of-page severity badge uses muted tier color + 10% tint background.
/// - High-risk verdicts surface via:
///   - Larger spacing around the Key Takeaway card (visual focus)
///   - Severity tier name in mono caps (compositional weight)
///   - Plain-English calm copy ("Worth a conversation with your doctor" —
///     never "STOP" / "AVOID" imperatives, per the established voice rule)
/// - Severity color brightness is **locked**. Never override.
///
/// ---
///
/// ## Empty & Missing-Data States
/// All sections degrade gracefully:
/// - No active ingredients → eyebrow + "No data available for this product yet."
/// - No label image → designed placeholder ("LABEL NOT YET AVAILABLE")
/// - No image → designed placeholder ("IMAGE NOT YET AVAILABLE")
/// - No interaction flags → safe-tier badge "No high-risk conflicts detected"
///
/// **No spinners** on Product Detail — `PGShimmerBox` / typed placeholders
/// only.
///
/// ---
///
/// ## Phase 1 Fixtures (renderable in `/dev/v2/product-detail/:id`)
/// - `normal` — short name, safe verdict, modest ingredient list
/// - `longName` — 100+ char name, ALL-CAPS brand, monitor severity
/// - `manyIngredients` — 22 active + 6 inactive (collapse stress test)
/// - `contraindicated` — high-risk verdict, calm copy
///
/// ---
///
/// ## Golden Test Variants (Phase 1.5)
/// - `normal_safe` (iPhone 13 frame)
/// - `long_name` (iPhone 13 frame)
/// - `many_ingredients_collapsed` (iPhone 13 frame, default 5-row state)
/// - `many_ingredients_expanded` (iPhone 13 frame, after View All tap)
/// - `missing_image` (iPhone 13 frame)
/// - `contraindicated` (iPhone 13 frame)
///
/// Goldens regenerate on iPhone 13 reference device only (640x1334 logical).
/// Cross-device parity verified in Phase 8 (Pixel 5a / Pixel 6).
library;
