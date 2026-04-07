
PharmaGuide
Flutter MVP — Developer Specification
Version 5.3  |  Pipeline Contract Aligned  |  UX/Accessibility Audit Applied
B&Br Technology  ·  Confidential

March 2026

Data Contract Changelog
Date	Change	Impact
2026-03-18	interaction_summary added to detail blob (condition_summary + drug_class_summary)	New Condition Alert Banner on scan result. Profile condition/medication chips must map to exact taxonomy IDs.
2026-03-18	dose_threshold_evaluation added to interaction warnings	Interaction warnings can now show dose-specific context (e.g. "600mcg exceeds 200mcg/day pregnancy limit").
2026-03-18	score_bonuses/score_penalties enriched with type, source, category, mechanism	Enables richer Pros and Considerations UI. See Section 6.10.
2026-03-18	reference_data.interaction_rules grew to ~95KB (45 rules)	Adjust memory budget for startup parse. Still well within limits.
2026-03-18	clinical_risk_taxonomy: 14 conditions, 9 drug classes	Profile chips must map exactly to these IDs. Any mismatch breaks interaction flagging.
2026-03-18	harmful_additive warnings now carry notes and mechanism	Card 2 can show richer additive detail (why it's harmful, not just that it is).
2026-03-30	Omega-3 dose adequacy export moved to ingredient_quality.sub.omega3_breakdown	Still folded into quality score. Show as sub-row in Card 1 when omega3_breakdown.applicable = true.
2026-03-30	v5.3 UX/Accessibility Audit: 7 color contrast failures fixed (WCAG AA), full accessibility section added, dark mode tokens defined	All score badge colors darkened. Primary brand adjusted for text use. See Section 2.
2026-03-30	v5.3 New pipeline data surfaced: formulation_detail, synergy_detail, serving_info, dietary_sensitivity_detail, certification_detail, B7/B5 evidence, probiotic clinical strains, rda_ul_data	Richer accordion card content. See Section 6.6.
2026-03-30	v5.3 Search UX expanded: autocomplete, recent searches, category filters, empty states	See Section 5.6.
2026-03-30	v5.3 Share + Deep Linking added	See Section 6.11 and Section 15.
2026-03-30	v5.3 Score Education overlay, analytics events, notification strategy, splash screen defined	See Sections 6.12, 14, 9.5, 1.
2026-03-30	v5.3 supplement_type (7 values) and form_factor (11 values) enums documented	See Section 10.7.
2026-03-31	v5.3 Execution hardening: bundled DB default, verified background swap + rollback, hard min_app_version gate, cache policy, debounced/limited FTS, Crashlytics/Sentry required	See Sections 1, 5.6, 10.3, 10.4, 11, 12.

Section 1 — Project Overview & Architecture

What We Are Building
PharmaGuide is a premium health-tech Flutter app: scan supplement barcodes, get instant clinical-grade safety scores, manage a personal stack, and chat with an AI Pharmacist. Built fast, privacy-first, and premium from day one.

PIPELINE DELTA — Changed from previous spec version
v5 MAJOR CHANGE: Data architecture updated to match the frozen pipeline contract (Export Schema v1.2.1).
Primary scan/search data source is now local SQLite (pharmaguide_core.db), NOT direct Supabase queries.
Supabase is used ONLY for: detail blobs, user stack/auth data, AI proxy, DB version checks.
Score sub-section maxima corrected: /25 /30 /20 /5 (not /25 /35 /15 /5 as in prior versions).
FitScore (personal 20pts) is now formally named score_fit_20. Computed on-device. Never stored in DB.
Interaction summary added to scan result for instant condition flagging (MVP: banner only).

Tech Stack
Frontend	Flutter (iOS + Android) — Impeller rendering engine enabled
Local DB	SQLite via drift (RECOMMENDED over raw sqflite) — split into pharmaguide_core.db (bundled/read-only) and user_data.db (local/read-write). Primary data source.
User / Cache DB	user_data.db stores product_detail_cache, user_profile, user_stacks_local, user_favorites, user_scan_history. Never overwritten by OTA DB swaps.
Remote Auth/Data	Supabase Auth (Google, Apple, Email, Anon) + detail blob storage + limited structured user data
State Mgmt	Riverpod 2.0+ with @riverpod generator. Mandatory. No Bloc.
Local Form State	For Profile and Stack edit flows, standardize on flutter_hooks + Form/validators (or an equivalent single explicit pattern). Do not let each screen invent its own local form state model.
Scoring	score_quality_80 from SQLite. score_fit_20 computed on-device via ScoreFitCalculator.
AI Chat	Gemini 2.5 Flash-Lite via Supabase Edge Function proxy. Verify current free tier limits before launch.
Animations	MVP ships with Flutter-native animations first (AnimationController / Animated widgets). Rive is optional post-MVP enhancement once the core scan loop is stable.
Fonts	Inter (Google Fonts package)
Images	cached_network_image for product images with automatic disk caching.
Icons	Lucide Icons (lucide_icons package). Never use emojis as structural icons.

App Identity
Splash Screen	Brand color (#0A7D6F) full background. Centered white PharmaGuide logo + tagline "Know What You Take". 1.5s max, animated fade to home. Use flutter_native_splash for native splash, then a lightweight Flutter fade/scale transition.
App Icon	Teal shield with white checkmark/pill motif. Rounded corners per platform (iOS: superellipse, Android: adaptive icon with teal background layer + white foreground).

Data Architecture — Hybrid SQLite + Supabase
The Two-Layer Data Model
Layer 1 — Local SQLite (pharmaguide_core.db):
  Ships bundled with the app by default. First-launch download is fallback only if build size becomes unacceptable.
  Contains: products_core (~180k products), products_fts, reference_data, export_manifest.
  Instant offline access for scan lookups and search. No network required.
  Updated in background when pipeline produces a new export version via full-file replacement in v1. No binary diffing in v1.

Layer 2 — Supabase (remote):
  Detail blobs: app reads `products_core.detail_blob_sha256`, derives the hashed shared payload path, and fetches it on demand. `detail_index.json` remains a compatibility/audit fallback if a row-level hash is absent.
  User data: Supabase Auth plus structured Supabase tables only where required in MVP:
    user_stacks, user_usage, pending_products.
  Health profile / fit inputs remain local-only in SQLite user_profile for MVP. No generic user_sync_data blob table.
  AI proxy: Supabase Edge Function wrapping Gemini API.
  DB version check: app reads export_manifest on launch, compares to Supabase manifest.
  Crash / error observability: use Firebase Crashlytics or Sentry, not a generic Supabase error_logs table.
  Signed-in offline availability comes from user_data.db: stack, favorites, scan history, and profile remain usable offline. Supabase is sync target, not runtime dependency.

Technical Decisions & Risk Mitigation
Accepted principles:
  Hybrid local SQLite + remote detail blobs is the locked architecture.
  drift is required over raw sqflite for compile-time contract safety.
  B0 safety gate is non-negotiable.
  Core scan loop and safety rendering are prioritized over deeper card polish.

Execution decisions:
  Database seeding: bundle the DB with the app on day 1. Do not require a first-launch download in the normal case.
  OTA updates: use full-file background replacement in v1. Do not introduce binary diffing (for example bsdiff) in v1.
  Guest limits: Hive guest counters are accepted as soft limits. Server-side enforcement remains strict for authenticated users.
  Edge Functions: do not prioritize warm-up pings in v1. Focus first on timeout handling, retry UX, and token/cost controls.
  Animation implementation: treat Rive references in older UX notes as motion intent only. Ship Flutter-native motion first to reduce build risk.

Hard requirements:
  DB swap safety: always download to a staging file, verify checksum against the remote export_manifest.json, then atomically swap in. Never overwrite the current DB in place.
  Rollback: if download, checksum verification, or open/parse validation fails, keep using the previous known-good DB and record the failure in Crashlytics or Sentry.
  Version gate: treat min_app_version as a hard client gate. If the app version is below the manifest requirement, force an app-store update before parsing the new release.
  Detail blob cache policy: product_detail_cache must have explicit max size, LRU eviction, and release-version-driven invalidation rules.
  Search throttling: all text search must be debounced (300ms) and query results must be strictly capped (LIMIT 50) to avoid UI jank on broad terms.
  Search result correctness: implement latest-query-wins behavior so an older slower search cannot overwrite a newer query result in the UI.
  Taxonomy integrity: load clinical_risk_taxonomy from reference_data at app startup and validate all UI chip mappings against exact pipeline IDs in debug builds.
  AI proxy hardening: enforce input validation, rate limiting, and request timeout handling on the Edge Function.
  Observability: minimal Crashlytics or Sentry integration is required from day 1 to capture DB swap, JSON parsing, and runtime contract failures.

Scoring Architecture
Score Fields and Their Sources
score_quality_80 — Pipeline precomputed. Stored in products_core SQLite. Max 80 pts.
score_100_equivalent — Derived convenience field (score_quality_80 / 80 * 100). Also in SQLite.
score_fit_20 — NEVER in DB. Computed on-device by ScoreFitCalculator using user_profile + reference_data.
score_combined_100 — (score_quality_80 + score_fit_20) * 100/100. Computed on-device.

Sub-section scores (from products_core, used in accordion cards):
  score_ingredient_quality  — max 25
  score_safety_purity       — max 30  (NOTE: was listed as /35 in prior spec — pipeline is authoritative)
  score_evidence_research   — max 20  (NOTE: was listed as /15 in prior spec — corrected)
  score_brand_trust         — max 5

Display logic:
  No profile: show score_100_equivalent. Label: "Base Quality Score".
  Profile exists: show score_combined_100. Label: "Your Match Score".
  NOT_SCORED products: show "Not Scored" — NEVER show 0 or null.

Grade Scale (deterministic thresholds):
  90-100 -> Exceptional
  80-89  -> Excellent
  70-79  -> Good
  60-69  -> Fair
  50-59  -> Below Average
  32-49  -> Low
  0-31   -> Very Poor

Freemium Limits
Scan Limits by Auth State
Guest: 10 scans lifetime — tracked in Hive (guest_scan_count). No SharedPreferences.
Signed In (free): 20 scans/day. Tracked in Supabase user_usage table.
AI Chat: 5 messages/day for free users. Tracked in Supabase user_usage.
Guest AI: 3 messages/day. Tracked locally in Hive.
Client check (Hive/Riverpod) gates UI. Supabase enforces server-side for signed-in users.

Supabase Tables (Remote Only)
user_stacks	id, user_id, dsld_id, dosage, timing, supply_count, source_device_id, client_updated_at, deleted_at, added_at, updated_at
user_usage	id, user_id, scans_today, ai_messages_today, reset_day_utc
pending_products	id, user_id, upc, normalized_upc, product_name, brand, image_url, submitter_note, status, review_notes, reviewed_at, reviewed_by, submitted_at
user_profiles is NOT a Supabase table. Health/fit data lives in local SQLite user_profile table. Never synced to cloud in MVP.

Section 2 — Global Design System

Color Palette — Light Mode (WCAG AA Verified)
Primary Brand	#0A7D6F  — buttons, active states, links (4.51:1 on white — PASSES AA)
Primary Dark	#087060  — text on white when higher contrast needed (5.14:1)
Brand Light	#E6F7F5  — tinted info boxes, tease banners
Background	#FAFAFA  — page background (never pure white)
Card Surface	#FFFFFF  — cards, modals, sheets
Heading Text	#1A1A1A  — never pure #000000
Body Text	#374151
Muted / Labels	#6B7280
Dividers	#E5E7EB
Score Green	#059669  — score >= 70 / positive flags (4.58:1 on white — PASSES AA)
Score Yellow	#D97706  — score 40-69 / warnings (4.56:1 on white — PASSES AA)
Score Red	#DC2626  — score < 40 / critical flags (4.63:1 on white — PASSES AA)
Score Orange	#EA580C  — sub-clinical dose / moderate clinical warnings (4.53:1 on white — PASSES AA)

IMPORTANT: Previous primary #0D9B8A FAILED WCAG AA (3.46:1). Previous score colors (#10B981, #F59E0B, #F97316) all FAILED. These corrected values pass 4.5:1 minimum.

Score Badge Usage:
  Score badges with colored backgrounds: use DARK TEXT (#1A1A1A), not white text.
  Exception: Score Red #DC2626 background can use white text (passes 4.63:1).
  Alternative: use colored text on white/light badge background instead.

Color Palette — Dark Mode
Dark Background	#0F1419  — page background
Dark Card Surface	#1C2128  — cards, modals
Dark Card Elevated	#242B33  — elevated cards, sheets
Dark Heading Text	#F0F2F5
Dark Body Text	#C9CDD3
Dark Muted	#8B949E
Dark Dividers	#2D333B
Dark Brand Light	#0D2924  — tinted info boxes (dark variant)
Dark Score Green	#34D399  — adjusted for dark backgrounds
Dark Score Yellow	#FBBF24  — adjusted for dark backgrounds
Dark Score Red	#F87171  — adjusted for dark backgrounds
Dark Score Orange	#FB923C  — adjusted for dark backgrounds
Dark Primary	#14B8A6  — brand color brightened for dark mode (3.5:1 on #1C2128 — passes AA for large text/icons)

All dark mode colors verified for minimum 4.5:1 text contrast on their intended backgrounds.
Frosted glass tab bar dark mode: color: Color(0xCC1C2128) (80% opacity dark card).
Alert banner dark variants: #3B1010 (red), #3B2D0A (yellow), #0D2924 (green), #3B1A05 (orange).

Typography — Inter
Display / Hero	Inter Bold, 32sp
Page Title	Inter Bold, 24sp
Section Header	Inter SemiBold, 18sp
Body	Inter Regular, 14sp (minimum body size — never smaller)
Caption	Inter Regular, 12sp, Muted color (use only for non-essential labels, never for actionable text)
Button	Inter SemiBold, 15sp
Code / Tech	Courier New, 13sp — for raw label text display only

Dynamic Type: All text MUST scale with system font size (MediaQuery.textScaleFactor). Test at 200% scale. No text truncation — wrap or use ellipsis with full text available via tap/long-press.

Spacing & Grid
Base Grid	8dp — all spacing is multiples of 8
Page Padding	16dp horizontal, 16dp vertical
Card Padding	16dp all sides
Card Radius	16dp
Button Radius	12dp
Sheet Radius	24dp top corners only
Chip Radius	20dp
Touch Target	Minimum 44x44dp for ALL interactive elements (Apple HIG). Use hitSlop if visual element is smaller.
Touch Spacing	Minimum 8dp gap between adjacent touch targets.

Shadows — One Style Only
BoxShadow(
  color: Color(0x1A000000),
  blurRadius: 20,
  offset: Offset(0, 4),
)
// No other shadow variants. No harsh or dark shadows anywhere.
// Dark mode: reduce shadow opacity to 0x0D or use elevation-based tonal surfaces.

Motion & Haptics
  Score ring: Flutter-native count-up/ring animation from 0 to final score, 650ms ease-out-back (NOTE: reduced from 900ms — premium apps use 600-700ms for count-up).
  Scanner bracket: Flutter-native 3-state animation — idle (static), scanning (pulse), success (green fill + checkmark).
  Bottom sheets: slide up 280ms ease-out.
  Accordion cards: AnimatedSize for expand/collapse, 250ms. Chevron rotates 180deg with Curves.easeOutBack (spring feel).
  Page transitions: Shared element / hero transition for product image between scan card and result screen.
  Staggered entrance: Accordion cards stagger in by 40ms each on first load.
  Successful scan haptic: HapticFeedback.mediumImpact() (NOTE: changed from heavyImpact — heavy is jarring for a scan).
  B0 critical warning haptic: HapticFeedback.vibrate() double pulse.
  Primary button tap: HapticFeedback.lightImpact().
  Accordion expand: HapticFeedback.selectionClick().
  Swipe-to-delete confirm: HapticFeedback.mediumImpact().
  Reduced Motion: When MediaQuery.disableAnimations is true, skip all non-essential animations (show static final state), disable stagger, set all durations to 0. Score ring shows final score immediately without count-up.

Modal / Sheet Rules
  NEVER use showDialog() or AlertDialog for any user-facing interaction.
  ALWAYS use showModalBottomSheet() with rounded top corners (radius 24dp).
  Sheets must have a drag handle: 4x36dp rounded pill, #E5E7EB, centered top.
  Sticky action buttons inside sheets fixed to bottom with safe area padding.
  Sheets with unsaved changes: confirm before dismiss ("Discard changes?" bottom sheet).

Animations — MVP Implementation
  Use Flutter AnimationController / implicit animations for: scanner bracket, score ring, success checkmarks, empty state illustrations, and simple transitions.
  Rive is an optional post-MVP enhancement after the core scan/result loop is stable.
  Do NOT use Lottie in MVP.
  Provide static fallback states for all animations when Reduce Motion is enabled.

State Management — Riverpod 2.0+
// All providers use @riverpod annotation.
@riverpod
Future<ScanCardData?> productByUpc(ProductByUpcRef ref, String upc) async {
  return ref.read(localDbRepoProvider).fetchProductByUpc(upc);
}

// AsyncValue in UI:
// productAsync.when(
//   loading: () => ShimmerCard(),
//   error: (e, _) => ErrorToast(message: e.toString()),
//   data: (p) => ScanResultScreen(product: p),
// )

Section 3 — Authentication & Freemium Logic

Auth Providers
  Google Sign-In (google_sign_in + Supabase OAuth)
  Apple Sign-In (sign_in_with_apple — REQUIRED for iOS App Store)
  Email + Password (Supabase Auth built-in)
  Anonymous Guest (Supabase anon session — no sign-in required to open app)

Auth Flow — First Launch
1.	App opens. Check for existing Supabase session.
2.	If none: create anonymous Supabase session silently (no prompt).
3.	User can scan up to 10 times as guest. Tracked in Hive guest_scan_count.
4.	After the 10th guest scan is consumed: show sign-up bottom sheet (not a blocking page).
5.	On sign-in: migrate anonymous scan history to authenticated user ID.

User State Enum
enum UserState {
  guest,        // Anon session. 10 lifetime scans from Hive, 3 AI msgs/day local.
  freeUser,     // Signed in. 20 scans/day, 5 AI msgs/day.
  premiumUser,  // Future. Unlimited.
}

Freemium Enforcement
Scan Limit Logic
Guest: Hive guest_scan_count. If >= 10 show upgrade sheet.
Do NOT use SharedPreferences. Hive is the only local KV store.
Free user: query Supabase user_usage (scans_today, reset_day_utc).
If scans_today >= 20 AND reset_day_utc = current UTC day: show upgrade sheet.
Increment AFTER successful score fetch, not on barcode read.
Supabase RLS validates server-side for signed-in users.

Scan Limit Sheet UI
  Title: "You've hit your daily limit"
  Guest subtext: "You've used your 10 free guest scans. Sign in for 20 scans per day."
  Free user subtext: "Upgrade to PharmaGuide Pro for unlimited scans."
  Guest CTA: "Sign In — It's Free" (primary brand color)
  Free user CTA: "Explore Pro" (leads to coming-soon screen — no paywall yet)
  "Maybe Later" text button (muted)

Section 4 — Navigation: Floating Tab Bar

Overview
Custom floating nav bar above the bottom safe area. Frosted glass background (BackdropFilter blur). Subtle top shadow. Floats with 16dp margin on all sides — does NOT sit flush with the edge.

Implementation
Stack(
  children: [
    Positioned.fill(child: _currentTab),
    Positioned(bottom: 16, left: 16, right: 16, child: FloatingTabBar()),
  ],
)

ClipRRect(
  borderRadius: BorderRadius.circular(24),
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),  // Dark mode: Color(0xCC1C2128)
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, 4))],
      ),
    ),
  ),
)

Tab Items
State	Trigger	Design / Content	Dev Notes
Home	Index 0	House icon. Active: filled brand. Inactive: outline grey.	Semantics(label: "Home")
Stack	Index 1	Layers icon. Active: filled brand. Inactive: outline grey.	Semantics(label: "My Stack")
Scan	Index 2	56dp circular button, brand color BG, white icon. Elevated above bar via Transform.translate(offset: Offset(0,-8)).	Semantics(label: "Scan product"). Primary CTA — must feel prominent.
AI Chat	Index 3	Chat bubble icon. Active: filled brand. Inactive: outline grey.	Semantics(label: "AI Pharmacist")
Profile	Index 4	Person icon. Active: filled brand. Inactive: outline grey.	Semantics(label: "Profile")

Labels: Show compact 10sp labels under ALL icons (not just active tab). Active label uses brand color, inactive uses muted grey. This ensures discoverability and accessibility without enlarging the bar.

Gesture Safety: Tab bar must not conflict with iOS home indicator or Android gesture navigation. Test on devices without hardware nav buttons.

State Preservation: Switching tabs MUST preserve scroll position and state. Use AutomaticKeepAliveClientMixin or equivalent.

Section 5 — Home Tab

Screen Layout
1.	Header (greeting + connectivity status)
2.	Search Bar
3.	Hero Card (two states)
4.	Recent Scans Carousel
5.	Daily AI Insight Card
Bottom padding: 100dp for floating tab bar.
Pull-to-refresh: RefreshIndicator wrapping the scroll view. On pull: refresh AI insight card + check DB version + re-sync stack (if signed in).

5.1 — Header
Top Left	"Good morning," — Inter Regular 14sp, grey. "[First Name]" — Inter Bold 28sp, charcoal.
Top Right	Connectivity: online = hidden. Offline = grey cloud-off icon 20dp.
Offline tap	Bottom sheet: "You're offline. Scanning and AI chat require internet. Your stack, favorites, scan history, and profile are available locally."
Greeting logic: "Good morning" (5-11), "Good afternoon" (12-16), "Good evening" (17-4). Guest: "Hello there".

5.2 — Search Bar
Style	Full-width, 48dp height, background #F3F4F6, radius 12dp, no border.
Icons	Left: search icon 20dp grey. Right: filter icon (not microphone — remove mic if voice search is not implemented).
Placeholder	"Search supplements or brands..."
On tap	Navigate to SearchScreen (Section 5.6). Uses local SQLite FTS (products_fts table). Instant results.

5.3 — Hero Card
State A: New User (Zero Stack)
Onboarding Hero Card
Teal-to-green gradient background. No score ring.
Caption: "Welcome to PharmaGuide".
Headline: "Let's build your health stack."
Subtext: "Scan your first supplement to get started."
CTA button (white, brand text): "Scan First Product" — navigates to Scan tab.

State B: Active User
Active Hero Card
Same gradient. 80dp animated score ring left. Right column white text:
  "X products in stack"
  "Interaction risk: Low / Moderate / High"
  "X meds scheduled today"
Ring color: green >= 70, yellow 40-69, red < 40.
Tap: navigates to Stack tab.

5.4 — Recent Scans Carousel
Header	"Recent Scans" + "View All" (brand color right)
Layout	Horizontal ListView.builder with snap. Item width 140dp.
Card	White card, radius 12dp, shadow. Product image 80x80dp (CachedNetworkImage with placeholder). Name (2 lines max). Score badge.
Score Badge	Pill: colored BG (WCAG-corrected colors), dark text. Bottom-right of image.
NOT_SCORED	Show "Not Scored" badge (grey) instead of score. Never show 0.
PDF image	If image_url ends in .pdf: show placeholder illustration, not a broken image.
Image error	If CachedNetworkImage fails (404, timeout): show branded placeholder (pill icon on light grey).
Empty	Dashed border card: "Scan something to see it here."

5.5 — Daily AI Insight
Style	White card, radius 12dp, shadow. Sparkle icon (brand color) left.
Content	One AI-generated tip. Personalized if user_profile has data. Generic fallback if not.
Cache	New tip each app open. Cached 24h in Hive. Do not call AI on every home screen render.

5.6 — Search Screen (NEW — expanded from previous spec)

Search screen opens on tap of home search bar. Full-screen with back button.

Search Input	Auto-focused, 48dp height, same style as home bar. Clear button appears when text is present.
Debounce	300ms debounce on text input before querying FTS. Instant feel without over-querying.
FTS Limit	Every search query must include LIMIT 50. Broad terms like "vitamin" must never materialize thousands of rows into Dart memory.
Result ordering correctness	Latest-query-wins. If an older slower search finishes after a newer query, discard the stale result instead of overwriting the current UI.

Empty State (no query entered):
  "Recent Searches" section: last 5 searches from Hive recent_searches box. Tap re-executes. Swipe to remove.
  "Popular Categories" chips row: "Multivitamins", "Omega-3", "Probiotics", "Vitamin D", "Magnesium", "Protein".
    Tapping a category chip executes FTS search for that term.

Results State:
  Virtualized list (ListView.builder with itemExtent: 72). Critical for 180K product database — search for "vitamin" may return thousands.
  Each row: 48x48dp product image + name + brand + score badge + form factor pill (e.g. "Capsule", "Gummy").
  Tap: navigates to full product result screen.
  Filter chips row (horizontal scroll, below search input): "All", "Capsule", "Tablet", "Gummy", "Liquid", "Powder" — filters by form_factor column.
  Sort: default by score_quality_80 DESC. Toggle to sort by name.

No Results State:
  "No supplements found for '[query]'."
  "Try a different name, brand, or scan the barcode."
  CTA: "Scan Instead" — navigates to Scan tab.

Section 6 — Scan Tab

6.1 — Camera View
Package	mobile_scanner
Overlay	Animated scanner bracket: 3 states — idle (white static), scanning (pulse), success (green + checkmark).
Controls	Top-left: back/close (44x44dp touch target). Top-right: flash toggle (44x44dp). Bottom-center: "Enter Code Manually" text btn.
No lasers	No animated scan lines. Bracket animation only.

6.2 — Permission Handling
State	Trigger	Design / Content	Dev Notes
First launch	Tab opened	OS native camera permission dialog.	permission_handler package.
Granted	User approves	Camera activates immediately.	—
Denied	User denies	Bottom sheet: lock icon + "Camera access needed." + "Enable in Settings" + "Enter Code Manually".	openAppSettings().

6.3 — Scan Flow (Happy Path)
1.	Camera detects UPC/EAN barcode.
2.	Haptic: HapticFeedback.mediumImpact(). Trigger scanner success state.
3.	Pause camera.
4.	Green banner slides from top: "Product Identified" — auto-dismiss 1.5s.
5.	Check scan limit (Section 3). If over limit: show limit sheet. Stop.
6.	Query LOCAL SQLite products_core WHERE upc_sku = ?. Instant. No network.
7.	Handle UPC collision: if COUNT(*) > 1 for this UPC, apply deterministic ordering (active first, highest score_quality_80, lowest dsld_id). Show chooser if still ambiguous.
8.	If verdict = BLOCKED or UNSAFE: navigate to B0 Critical Warning screen (Section 6.4). Stop.
9.	If user_profile has health data: run ScoreFitCalculator.calculate() locally.
10.	Run instant condition check via interaction_summary from detail blob IF already cached. Show condition banner if flagged (Section 6.5.4).
11.	Slide up full Result Screen.
12.	In background: check product_detail_cache. If not cached and online: read `detail_blob_sha256` from `products_core`, derive the hashed detail payload path, fetch from Supabase, cache it, then hydrate accordion cards. Fall back to active `detail_index.json` only if the row-level hash is missing.
13.	Log analytics event: scan_completed (Section 14).

6.4 — B0 Gate: Critical Warning Screen
B0 Gate fires when: verdict = BLOCKED or verdict = UNSAFE
Standard score ring: HIDDEN.
5-pillar accordion cards: HIDDEN.

Score ring replaced by solid red circle (100dp):
  Center: X icon (white, 40dp). No number. No animation.
  Label below: "BLOCKED" or "UNSAFE" — Inter Bold 16sp red.
  Semantics(label: "Critical safety warning. This product is [BLOCKED/UNSAFE].")

Critical Warning card (full-width, bg #FEF2F2, border #DC2626):
  "CRITICAL WARNING" — Inter Bold 18sp red + warning icon 32dp.
  "Severity:" + blocking_reason value from products_core (e.g. "banned_ingredient").
  Full warning detail from warnings[] where type = banned_substance or recalled_ingredient.
  "Do not use this product. Consult your healthcare provider."

Sticky buttons: "Report This Product" (red filled) + "Scan Another Product" (outline).
Haptic: double pulse vibration.
Never show score, grade, or any positive UI element when B0 fires. Safety overrides design.

6.5 — Result Screen: Full Clinical Breakdown
6.5.1 — Screen Layout
1.	Hero Section — sticky top
2.	Verdict Banner — full-width color strip (with icon, not color-only)
3.	Condition Alert Banner — if user conditions intersect interaction_summary
4.	Pros & Considerations summary (NEW)
5.	5 Pillar Smart Cards — scrollable accordion
6.	Sticky Action Buttons — fixed bottom (with Share)

6.5.2 — Hero Section (Sticky)
Design
Product image 72x72dp, radius 8dp. CachedNetworkImage with placeholder. Handle PDF URLs: if image_url ends in .pdf, show placeholder.
Product name Inter Bold 18sp. Brand Inter Regular 13sp grey.
Form factor + supplement type pills below brand: e.g. "Capsule" pill + "Multivitamin" pill (muted grey bg).
Serving info line: "2 capsules per serving" from serving_info (if available).
Verified checkmark (green, if verdict = SAFE and has_banned_substance = false).

Animated Score Ring (100dp):
  NOT_SCORED: show "Not Scored" text, no ring. Semantics: "Product not scored — insufficient data."
  No profile: count-up to score_100_equivalent. Label "Base Quality Score" grey.
  Profile exists: count-up to score_combined_100. Label "Your Match Score" brand color.
  Ring color: green >= 70, yellow 40-69, red < 40.
  Show grade word below ring: Exceptional / Excellent / Good / Fair / Below Avg / Low / Very Poor.
  Tap on score ring: opens Score Education overlay (Section 6.12).
  Semantics(label: "Quality score [X] out of 100, rated [grade]").

Percentile chip (if percentile_top_pct is not null):
  e.g. "Top 12% in Multivitamins" — small teal chip below grade.

Profile Tease Banner (no profile only):
  Brand-light box. Lock icon + "Is this right for YOU?"
  "Add your health goals to unlock your Personal Match Score."
  Tappable: navigates to Profile health context.

Discontinued / Off-Market Badge (if product_status != active):
  Orange pill badge: "Discontinued" or "Off Market" + discontinued_date if present.

6.5.3 — Verdict Banner
Each verdict shows an ICON alongside color to meet color-not-only accessibility:
SAFE	Green #D1FAE5 (dark: #0D2924). Checkmark icon. "Passes all safety checks."
CAUTION	Yellow #FEF3C7 (dark: #3B2D0A). Warning triangle icon. "Review flagged items below."
POOR	Orange #FFF7ED (dark: #3B1A05). Downward arrow icon. "Low quality — review before use."
UNSAFE	Red #FEE2E2 (dark: #3B1010). X-circle icon. "Safety concerns detected."
NOT_SCORED	Grey #F3F4F6 (dark: #242B33). Question mark icon. "Insufficient data to score this product."

6.5.4 — Condition Alert Banner
Instant Condition Flagging via interaction_summary
Read interaction_summary from the detail blob (if cached). Do not re-compute from warnings[].
Intersect interaction_summary.condition_summary.keys with user_profile.conditions.

If intersection is non-empty: show a prominent orange banner ABOVE the accordion cards.
  Icon: warning triangle.
  Title: "Flagged for your health conditions".
  Body: list of flagged condition names + highest_severity for each.
  Example: "Pregnancy — Contraindicated: Contains Vitamin A Palmitate above safe threshold."
  CTA: "View Details" — expands Card 3 (Clinical Evidence) and auto-scrolls to interaction warnings.

If no intersection: banner is hidden.

Code pattern (from Flutter Data Contract v1):
final summary = blob['interaction_summary'];
if (summary != null) {
  final userConditions = userProfile.conditions;
  final flaggedConditions = userConditions.intersection(
    Set<String>.from((summary['condition_summary'] as Map?)?.keys ?? [])
  );
  for (final condition in flaggedConditions) {
    final info = summary['condition_summary'][condition];
    showConditionBanner(condition, info);
  }
  final userDrugClasses = userProfile.drugClasses;
  final flaggedDrugs = userDrugClasses.intersection(
    Set<String>.from((summary['drug_class_summary'] as Map?)?.keys ?? [])
  );
  for (final drugClass in flaggedDrugs) {
    final info = summary['drug_class_summary'][drugClass];
    showMedicationBanner(drugClass, info);
  }
}

6.5.5 — Pros & Considerations Summary (NEW)
Between verdict banner and accordion cards. Two columns side by side.

"What helped this score" (left, green accent):
  Render from score_bonuses[]. Each row: green checkmark + label + "+X pts".
  Example: "Synergy Bonus: Calcium + Vitamin D (+2.0)"
  Example: "Premium Form: Methylcobalamin (+1.5)"
  Example: "Third-Party Tested: USP (+5.0)"

"What hurt this score" (right, red accent):
  Render from score_penalties[]. Each row: red X + label + "-X pts".
  Example: "Harmful Additive: Titanium Dioxide (-2.0)"
  Example: "Proprietary Blend: 65% undisclosed (-3.2)"
  Example: "Dose Safety: Niacin at 180% UL (-2.0)"

Max 3 items per column visible. "+X more" expands inline.
If no bonuses or penalties: hide that column.

6.6 — The 5 Pillar Smart Cards
Tappable accordion rows. Default: all collapsed. Header always visible. Tap to expand/collapse inline via AnimatedSize. Sub-score pill color: green >= 80% of max, yellow 50-79%, red < 50%.
Semantics: each card header announces "[Card name], [score] out of [max], [expanded/collapsed]. Double tap to [expand/collapse]."

Card 1 — Ingredient Quality  (score_ingredient_quality / 25)
Data sources: products_core + detail blob section_breakdown.ingredient_quality + formulation_detail + serving_info
Collapsed header: "Ingredient Quality" + sub-score pill (e.g. "22/25").

Expanded content:

  Serving Info row (if serving_info present):
    "Serving: X [unit]" + "X-Y per day recommended" from serving_info.
    Grey info row at top of card.

  "Active Ingredients" list from ingredients[]:
    Each row: ingredient name + category pill (e.g. "vitamin", "mineral", "botanical").
    If bio_score >= 14: green "Premium Form" badge.
    If bio_score >= 10 and < 14: blue "Good Form" badge.
    If bio_score < 5: grey "Standard Form" badge.
    Show dosage + unit if present (e.g. "400 mg").
    Raw label text shown in small monospace caption below name.
    Tap on ingredient row: opens Ingredient Detail bottom sheet (educational notes from IQM, category, identifiers).

  Delivery System row:
    delivery_tier from formulation_detail.
    Liposomal/Nano-emulsified: green badge "Advanced Delivery".
    Enteric/Delayed-release/Sustained-release: blue badge "Enhanced Delivery".
    Micronized: blue badge "Micronized".
    Standard capsule/softgel/tablet: grey badge "Standard".

  Absorption Enhancer row (if formulation_detail.absorption_enhancer_paired = true):
    Teal pill: "Enhanced Absorption" + enhancer names (e.g. "BioPerine, Ginger Root").

  Standardized Botanicals (if formulation_detail.standardized_botanicals is non-empty):
    Each botanical: blue pill "Standardized to X% [active_compound]" (e.g. "Standardized to 95% Curcuminoids").

  Synergy Profile (if synergy_detail present and synergy_detail.qualified = true):
    Teal card: "Synergy-Optimized Formula".
    Cluster name (e.g. "Calcium + Vitamin D + Magnesium").
    Checkmarks for each ingredient meeting minimum effective dose.
    Evidence tier badge.

  Probiotic Excellence (show only if probiotic_detail present):
    Teal badge "Probiotic Excellence".
    CFU: "X billion CFU per serving" from probiotic_detail.total_billion_count.
    Strains: "X strains" from probiotic_detail.total_strain_count.
    Clinical strains: green checkmark badges for each clinical_strain (e.g. "LGG", "BB-12").
    Survivability: if has_survivability_coating: green pill "Survivability Coating" + reason.
    Prebiotic: if prebiotic_present: green pill "Prebiotic Included" + prebiotic name.

  Omega-3 Dose Adequacy (show only for omega-3 products with omega3_breakdown data):
    If section_breakdown.ingredient_quality.sub.omega3_breakdown.applicable = true:
      Blue info card:
        Dose band label (e.g. "AHA Cardiovascular Dose") + per_day_mid_mg value.
        "EPA: Xmg + DHA: Ymg per serving = Zmg/day combined."
        If prescription_dose = true: orange pill "High-Dose Formula".
      This data is folded into the quality score but displayed here for transparency.

Card 2 — Safety & Purity  (score_safety_purity / 30)
Data sources: products_core boolean columns + detail blob warnings[] + compliance_detail + certification_detail + dietary_sensitivity_detail
Collapsed header: "Safety & Purity" + sub-score pill.
If has_harmful_additives or has_allergen_risks: card header shows small warning dot (red circle 8dp).

"The Good" section — show only TRUE items:
  Green pill: "Vegan Certified" if is_vegan = 1.
  Green pill: "Gluten-Free" if is_gluten_free = 1.
  Green pill: "Dairy-Free" if is_dairy_free = 1.
  Green pill: "Organic" if is_organic = 1.
  Green pill: "NSF GMP Certified" if cert_programs contains "NSF_GMP".
  Green pill: "Batch Traceability" if compliance_detail.batch_traceability = true.
  Green pill: "Heavy Metal Tested" if certification_detail.heavy_metal_tested = true.
  Green pill: "Label Accuracy Verified" if certification_detail.label_accuracy_verified = true.
  Third-party program badges from certification_detail.third_party_programs: USP, NSF, ConsumerLab, Informed Choice — show logo-style pill for each.

Dietary Profile (if dietary_sensitivity_detail present):
  Sugar: "[X]g sugar per serving" with traffic light (green < 1g, yellow 1-5g, red > 5g).
  Sodium: "[X]mg sodium per serving" with traffic light (green < 50mg, yellow 50-200mg, red > 200mg).
  Sweeteners: if is_sweetened: list sweetener names (e.g. "Sweetened with Stevia, Sucralose"). If sugar_free: green pill "Sugar-Free".

Dose Safety Evidence (if section_breakdown.safety_purity.sub.B7_dose_safety_evidence is non-empty):
  Orange warning card: "Dose Safety Alert".
  Each entry: "[Nutrient] at [pct_ul]% of Upper Limit" with orange/red severity.
  150-200% UL: orange "Warning". 200%+: red "Critical".

"Flagged Items" section — show only if flags present:
  Proprietary Blend warning (yellow row) if proprietary_blend_detail.present = true:
    "Opacity Penalty: Contains proprietary blends."
    If B5_blend_evidence available: "[X]% of blend composition undisclosed" using impact_ratio.
    Disclosure tier label: "Partial Disclosure" or "No Disclosure".
  Harmful additives (red rows with X icon) from warnings[] where type = harmful_additive:
    Show: title + mechanism_of_harm + population_warnings.
  Allergen rows (yellow with warning icon) from warnings[] where type = allergen:
    Show: title + supplement_context + prevalence chip.

Card 3 — Clinical Evidence  (score_evidence_research / 20)
Data sources: detail blob evidence_data + warnings[] type=interaction/drug_interaction + rda_ul_data
Collapsed header: "Clinical Evidence" + sub-score pill.
If condition alert fired: card border uses brand color (static highlight, not pulse — respect reduced motion) and auto-expands.

SUB_CLINICAL_DOSE warning (orange card at top, if any ingredient flagged):
  "Sub-Clinical Dose Detected".
  "One or more ingredients are below the minimum effective dose in clinical research."
  List affected ingredient names.

Interaction / Drug Interaction warnings from warnings[]:
  Each row: severity badge (with icon, not color alone) + title + action text.
  Severity badges: Contraindicated (red X-circle), Avoid (red warning), Caution (yellow warning), Monitor (orange eye).
  evidence_level chip: "Established" (dark blue), "Probable" (purple), "Theoretical" (grey).
  Citation link if sources[] is non-empty — opens in-app WebView.

  Dose Threshold Context (if doseThresholdEvaluation is present on the warning):
    Show below the action text in a muted info box:
    "This warning applies because the serving contains [product_dose] [unit],
     which [exceeds/is below] the [threshold_value] [unit]/day limit for [condition]."
    Only show when threshold_met = true.

Nutrient Adequacy (if rda_ul_data present and rda_ul_data.collection_enabled = true):
  "Nutrient Coverage" section showing which vitamins/minerals this product helps meet daily RDA:
  Each row: nutrient name + percentage of RDA as horizontal bar + adequacy status.
  Green bar: 50-200% RDA ("Optimal"). Yellow: 25-50% ("Adequate"). Grey: <25% ("Low"). Red: >UL ("Over Limit").
  If rda_ul_data.has_over_ul = true: show orange warning "X nutrient(s) exceed safe upper limits."

Clinical Matches from evidence_data:
  Match count: "X clinical matches found" header.
  Study type badges: RCT (dark blue), Systematic Review (purple), Meta-Analysis (teal), Observational (grey).
  "View Studies" text button: opens bottom sheet listing study descriptions.

Card 4 — Brand Trust  (score_brand_trust / 5)
Data sources: products_core + manufacturer_detail + warnings[] type=status
MANUFACTURER_VIOLATION check first (from score_penalties or manufacturer_detail):
  If present: card header bg #FEE2E2, border #DC2626, sub-score pill red.
  Expanded: red row "Manufacturer Violation" + violation detail text.

Boolean rows (checkmark icon green / X icon red):
  "Trusted Manufacturer" — is_trusted_manufacturer
  "Third-Party Tested"   — has_third_party_testing
  "Full Disclosure"      — has_full_disclosure
  Region badge from manufacturer_detail.region (if present): e.g. "Made in USA" grey pill.
  Rows from manufacturer_detail if present.

Product status warning (if product_status != active):
  Warning row from warnings[] where type = status.
  Show: discontinued date or off-market label.

Card 5 — Your Personal Match
Data source: LOCAL SQLite user_profile + reference_data + ScoreFitCalculator output. Never from Supabase.
Collapsed header: "Your Personal Match" + adjustment chip ("+X" green / "-X" red / dash if no profile).

State A — No profile (Locked):
  Lock icon + "Unlock Your Match".
  Expanded: "Complete your health profile to see personal goal alignment, condition safety, and dosage fit."
  CTA: "Set Up My Profile" navigates to Profile tab.

State B — Profile exists:
  FitScoreResult.chips rendered from ScoreFitCalculator.
  Positive chip (green checkmark): e.g. "Aligns with Sleep goal".
  Warning chip (yellow warning): e.g. "Approaching Upper Limit for Vitamin A".
  Negative chip (red X): e.g. "Contains Dairy (your allergen)".
  Condition chip (red warning): e.g. "Caution: Hypertension — sympathomimetic ingredient".
  Max 4 chips visible. "+X more" expands inline.
  If chips empty but profile exists: "No personal conflicts detected." (green checkmark).

IMPORTANT: missingFields from FitScoreResult:
  If profile is partial, show: "Complete your profile for a full match score." with missing field names.

6.7 — Sticky Action Buttons
Primary	"Add to Stack" — full-width, brand color, 52dp, radius 12dp. Semantics(label: "Add this product to your supplement stack").
Secondary	"Ask AI Pharmacist" — full-width, outlined, same sizing.
Share	Share icon button (24dp, top-right of hero section, not in sticky bar).
B0 state	"Report This Product" (red filled) + "Scan Another" (outline).

6.8 — Post-Scan: Add to Stack Flow
1.	"Add to Stack" tapped. Animated success checkmark + "Added to Stack" banner.
2.	Single bottom sheet: "Set a Schedule?" — AM / PM / Custom chips.
3.	Same sheet animates to: "Track your supply?" — 30 / 60 / 90 / 120 chips.
4.	"All Set!" success checkmark animation. Sheet auto-dismisses after 1s.
One sheet. Animated transitions. Not multiple sheets.

6.9 — Manual Entry & Not Found
  Manual: bottom sheet, text field, search. Triggers same SQLite lookup + B0 + result flow.
  Not found in SQLite: show "Product Not Found" sheet.
  "Submit Product" form writes to Supabase pending_products table.

6.10 — Payload Reference (Detail Blob)
The local build output detail blob `{dsld_id}.json` maps to the 5 cards as follows. At runtime the app prefers `products_core.detail_blob_sha256`, derives the hashed shared payload path, then fetches/caches it in `product_detail_cache`. If a key is absent or null, hide that UI element — never render empty rows.
// blob_version field — compare to local to decide re-fetch.
{
  "dsld_id": string,
  "blob_version": number,

  // Card 1
  "ingredients": [{ name, standardName, standard_name, bio_score,
                     form, dosage, dosage_unit, notes, is_harmful,
                     is_banned, is_allergen, safety_hits, category,
                     identifiers: {cui?, cas?, pubchem_cid?, unii?} }],
  "section_breakdown": {
    "ingredient_quality": { "score", "max", "sub": {
        "probiotic_breakdown": {},
        "omega3_breakdown": { applicable, dose_band, per_day_mid_mg, epa_mg_per_unit, dha_mg_per_unit, prescription_dose }
    }},
    "safety_purity": { "score", "max", "sub": {
        "B5_blend_evidence": [{ disclosure_tier, impact_ratio, hidden_mass_mg }],
        "B7_penalty": number,
        "B7_dose_safety_evidence": [{ nutrient, amount, ul, pct_ul, penalty }]
    }},
    "evidence_research": { "score", "max", "matched_entries", "ingredient_points": {} },
    "brand_trust": { "score", "max" },
    "violation_penalty": number
  },

  // Card 2
  "inactive_ingredients": [{
    name, category, is_additive, additive_type, is_harmful,
    notes, mechanism_of_harm, population_warnings, common_uses,
    identifiers: {cui?, cas?, pubchem_cid?, unii?}
  }],
  "compliance_detail": { "batch_traceability": bool },
  "certification_detail": {
    "third_party_programs": [string],
    "gmp": bool,
    "purity_verified": bool,
    "heavy_metal_tested": bool,
    "label_accuracy_verified": bool
  },
  "proprietary_blend_detail": { "present": bool },
  "dietary_sensitivity_detail": {
    "sugar": { "amount_g": float, "level": string, "level_display": string },
    "sodium": { "amount_mg": float, "level": string, "level_display": string },
    "sweeteners": { "is_sweetened": bool, "sweetener_list": [string], "sugar_free": bool }
  },

  // Card 1 (formulation)
  "formulation_detail": {
    "delivery_tier": string,
    "delivery_form": string,
    "absorption_enhancer_paired": bool,
    "absorption_enhancers": [string],
    "is_certified_organic": bool,
    "organic_verification": string,
    "standardized_botanicals": [{ "name", "active_compound", "percentage" }],
    "synergy_cluster_qualified": bool,
    "claim_non_gmo_verified": bool
  },
  "serving_info": {
    "basis_count": int,
    "basis_unit": string,
    "min_servings_per_day": int,
    "max_servings_per_day": int
  },

  // Card 1 (probiotic)
  "probiotic_detail": {
    "is_probiotic": bool,
    "total_strain_count": int,
    "total_cfu": float,
    "total_billion_count": float,
    "clinical_strains": [{ "strain_name": string, "cfu": float }],
    "clinical_strain_count": int,
    "prebiotic_present": bool,
    "prebiotic_name": string,
    "has_survivability_coating": bool,
    "survivability_reason": string,
    "guarantee_type": string,
    "has_cfu": bool
  },

  // Card 1 (synergy)
  "synergy_detail": {
    "qualified": bool,
    "clusters": [{
      "cluster_name": string,
      "evidence_tier": string,
      "matched_ingredients": [{ "ingredient", "quantity", "unit", "min_effective_dose", "meets_minimum" }],
      "all_adequate": bool
    }]
  },

  // Card 3
  "evidence_data": {
    "match_count": int,
    "clinical_matches": [{ "claim", "study_count", "evidence_strength", "study_type", "description" }],
    "unsubstantiated_claims": [{ "claim", "reason" }]
  },
  "rda_ul_data": {
    "collection_enabled": bool,
    "adequacy_results": [{ "nutrient", "amount", "rda", "pct_rda", "adequacy_status" }],
    "safety_flags": [{ "nutrient", "amount", "ul", "pct_ul", "flag_type" }],
    "has_over_ul": bool
  },

  // Card 4
  "manufacturer_detail": { "trusted": bool, "third_party": bool, "region": string },

  // Condition + medication flagging
  "interaction_summary": {
    "highest_severity": string,
    "condition_summary": {
      "[condition_id]": {
        "label": string,
        "highest_severity": string,
        "ingredient_count": number,
        "ingredients": string[],
        "rule_ids": string[],
        "actions": string[]
      }
    },
    "drug_class_summary": {
      "[drug_class_id]": {
        "label": string,
        "highest_severity": string,
        "ingredient_count": number,
        "ingredients": string[],
        "rule_ids": string[],
        "actions": string[]
      }
    }
  },

  // Score explainability
  "score_bonuses": [{
    "id": string,     // A2, A3, A4, A5a, A5b, A5c, A5d, A6, probiotic, B4a, B4b, B4c
    "label": string,
    "score": number,
    "detail": any?
  }],
  "score_penalties": [{
    "id": string,     // B0, B1, B2, B3, B5, B6, B7, violation
    "label": string,
    "score": number?,
    "severity": string?,
    "reason": string?,
    "status": string?,
    "presence": bool?,
    "blend_count": int?
  }],

  // Warnings (polymorphic)
  "warnings": [
    // type: banned_substance | recalled_ingredient | high_risk_ingredient |
    //        watchlist_substance | harmful_additive | allergen |
    //        interaction | drug_interaction | dietary | status
  ]
}

6.11 — Share Product (NEW)
Share icon (top-right of hero section, 44x44dp touch target).
Tap generates a share card:
  Product name + brand.
  Score badge with grade.
  Verdict badge.
  "Checked with PharmaGuide" footer + app store link.
Share via native platform share sheet (Share.share from share_plus package).
Include deep link: pharmaguide.app/product/{dsld_id} (see Section 15).

6.12 — Score Education Overlay (NEW)
Triggered by: tapping the score ring on result screen, OR first-ever scan (one-time).

Bottom sheet with 4 visual steps (horizontal PageView with dot indicators):

Step 1 — "How We Score" title.
  "Every supplement gets a transparent quality score. No black boxes, no paid placements."
  Visual: 4 colored segments showing the 4 pillars.

Step 2 — "The 4 Pillars":
  Ingredient Quality (25 pts) — "Are the ingredient forms high quality?"
  Safety & Purity (30 pts) — "Is this product safe and clean?"
  Clinical Evidence (20 pts) — "Does research back this product?"
  Brand Trust (5 pts) — "Is the manufacturer reputable?"

Step 3 — "Your Personal Match (+20 pts)":
  "Add your health profile to get a personalized score based on your age, goals, conditions, and medications."

Step 4 — "Tap any card to see the details."
  CTA: "Got It" (dismisses sheet).

Track in Hive: has_seen_score_explainer. Show on first scan only. Score ring tap always opens it.

Section 7 — AI Pharmacist Tab

7.1 — Proactive Empty State
Design
AI icon (sparkle, brand color 40dp) centered.
Title: "How can I help you today?" Inter Bold 22sp.
Disclaimer (always visible): "Educational info only — not medical advice." 12sp grey italic.
Semantics: announce disclaimer to screen readers.

Three large prompt buttons (stacked, 16dp gap, full-width, 56dp, card style):
  No stack data: static prompts:
    "Guide to supplement timing"
    "Tips for better energy"
    "Understanding interaction risks"

  Stack data exists: dynamic stack-aware prompts (read from local stack provider / user_stacks_local sync state):
    e.g. "Analyze my Magnesium timing"
    e.g. "Is my Omega-3 safe with NSAIDs?"

Tapping a button starts chat with that prompt pre-filled and sent.

7.2 — Active Chat Interface
Disclaimer	Pinned above first message. Always visible.
User bubbles	Right-aligned. Brand color BG. White text (verified contrast). Radius 16dp flat bottom-right.
AI bubbles	Left-aligned. #F3F4F6 BG (dark: #242B33). Dark text. Radius 16dp flat bottom-left.
Typing indicator	Three-dot animation (respect reduced motion: show static "..." if disabled). Show immediately while awaiting response.
Input	Rounded input, grey BG, send icon (brand color, active only when text present). Minimum 44dp height.

7.3 — Quick Prompt Chips
  Horizontal scroll row above keyboard.
  Context-aware from local stack provider. Generic if no stack.
  Tap sends immediately — no confirm step.

7.4 — AI Message Limit
5 messages/day for free users
Track in Supabase user_usage.ai_messages_today.
When limit hit: replace input with banner.
Banner: "You've used your 5 free messages today." CTA: "Explore Pro."
Previous messages remain readable.

7.5 — Offline State
  If offline: replace input area with grey banner: "Offline — AI chat requires internet."
  Previous chat history (from local Hive chat_history box) remains viewable.

7.6 — AI Integration
Gemini 2.5 Flash-Lite — Supabase Edge Function Proxy
Model: gemini-2.5-flash-lite.
NOTE: Google AI free tier limits change frequently. Verify current limits before launch.
Proxy is a Supabase Edge Function. API key server-side only. Never in app binary.
Proxy receives: { messages: [...], system_prompt: string }.
Edge Function must enforce rate limiting, input validation, and explicit request timeouts. Stable request/response behavior ships first; streaming is optional after the core scan/result flow is solid.
Upgrade path: route complex queries to Pro later via model routing layer.

7.7 — System Prompt Builder
String buildSystemPrompt(HealthProfile? profile, List<StackItem> stack) {
  return """
You are an AI Pharmacist for PharmaGuide, a health technology app.
Provide educational information about supplements and medications.
You are NOT a licensed pharmacist. You CANNOT provide medical advice.
Always recommend consulting a healthcare provider for medical decisions.

User health context:
- Goals: ${profile?.goals ?? "not specified"}
- Conditions: ${profile?.conditions ?? "not specified"}
- Allergies: ${profile?.allergies ?? "not specified"}
- Current stack: ${stack.map((s) => s.name).join(", ")}

Keep responses under 150 words. Plain language. Never diagnose.
""";
}

Section 8 — My Stack Tab

8.1 — Stack Summary Card
Design
Same teal gradient as Home Hero.
70dp animated score ring + grade label.
Headline: "[Low/Moderate/High] Interaction Risk".
Subtext: "X products  ·  X interactions found".
"View Alerts" button (white outlined): filters list to show only flagged items.

8.2 — My Stack / Wishlist Tabs
  Two sub-tabs: "My Stack" (active) | "Wishlist".
  Underline tab indicator, brand color. Inactive: grey text.
  Wishlist: same card design — saved products not yet added to stack.

8.3 — Stack Item Card
Height	72dp minimum (expand for accessibility text scaling)
Left	48x48dp product image, radius 8dp. CachedNetworkImage with placeholder. PDF image: placeholder.
Center	Product name Inter SemiBold 14sp. Below: "Xmg · AM/PM" grey 12sp. Form factor pill.
Right	Score badge + risk icon if flagged.
NOT_SCORED	Show "Not Scored" badge instead of score.
Risk icon	Yellow warning icon if CAUTION/POOR. Red warning icon if UNSAFE.
Swipe left	Delete — red BG, trash icon. Snackbar undo (5s timeout).
Tap	Opens edit sheet: dosage, timing, supply count.

8.4 — Empty Stack State
  Empty-state illustration: pillbox (static or lightly animated, but must respect Reduce Motion).
  "Your stack is empty." + "Add supplements to track interactions."
  CTA: "Scan a Product" navigates to Scan tab.

8.5 — Supply Tracking (NEW)
When supply_count is set on a stack item:
  Show remaining day count based on (supply_count - days_since_added).
  When <= 7 days remaining: show orange "Running Low" pill on stack card.
  When <= 3 days remaining: show red "Almost Out" pill.
  Notification: "Your [product name] supply runs out in 3 days" (if notifications enabled).

Section 9 — Profile Tab

9.1 — Privacy Header
Design
Shield/lock icon, brand color, 48dp, centered.
Headline: "Privacy-First Design." Inter Bold 22sp.
Subtext: "Your detailed health data is encrypted on your device. You control what gets synced."
(Accurate: health profile in local SQLite. Auth email is in Supabase — not contradicted by wording.)

9.2 — Auth State
State	Trigger	Design / Content	Dev Notes
Guest	No session	"Sign in to sync data and unlock more scans." + Sign In button.	Opens Auth bottom sheet.
Signed in	Session exists	Avatar (initials), name/email, "Sign Out" text btn.	Confirm sign-out via sheet.

9.3 — My Health Context
Each row opens a chip-selection bottom sheet. CRITICAL: chip values must map exactly to condition_id and drug_class_id values from the pipeline taxonomy (Flutter Data Contract v1, Section 8).

Condition Chips — condition_id mapping
Pregnancy	condition_id: pregnancy
Lactation/Breastfeeding	condition_id: lactation
Trying to Conceive	condition_id: ttc
Hypertension	condition_id: hypertension
Heart Disease	condition_id: heart_disease
Diabetes/Blood Sugar	condition_id: diabetes
High Cholesterol	condition_id: high_cholesterol
Liver Disease	condition_id: liver_disease
Kidney Disease	condition_id: kidney_disease
Thyroid Condition	condition_id: thyroid_disorder
Autoimmune	condition_id: autoimmune
Epilepsy/Seizures	condition_id: seizure_disorder
Bleeding Disorders	condition_id: bleeding_disorders
Upcoming Surgery	condition_id: surgery_scheduled

Medication Chips — drug_class_id mapping
Blood Thinners	drug_class_id: anticoagulants
Antiplatelet Agents	drug_class_id: antiplatelets
NSAIDs	drug_class_id: nsaids
Blood Pressure Meds	drug_class_id: antihypertensives
Diabetes Medications	drug_class_id: hypoglycemics
Thyroid Medications	drug_class_id: thyroid_medications
Sedatives / Sleep Aids	drug_class_id: sedatives
Immunosuppressants	drug_class_id: immunosuppressants
Statins / Cholesterol	drug_class_id: statins

Pregnancy, TTC, and Lactation are THREE separate conditions with distinct clinical risks. Do not merge them. Users may select more than one.
Taxonomy loading rule: parse clinical_risk_taxonomy from reference_data once at app startup via a dedicated TaxonomyService/provider. In debug builds, assert that every UI chip ID exactly matches a taxonomy ID before rendering Profile or interaction-dependent UI.

9.4 — Health Goals
Goals map to user_goals_to_clusters.json in reference_data. Standard chips: Energy, Sleep, Immunity, Weight, Heart Health, Athletic Performance, Stress Relief.

9.5 — Settings & Notifications
Notifications Section:
  Master toggle: "Supplement Reminders" — uses flutter_local_notifications.
  Permission flow: first toggle tap -> bottom sheet explaining why ("Get reminders for your daily supplements and supply alerts") + "Enable" / "Not Now". Then OS permission dialog.
  Sub-toggles (visible only when master is on):
    "Daily Reminder" — at user-selected time. Default: 8:00 AM.
    "Supply Alerts" — when supply_count is running low (7 days, 3 days).
  Content examples:
    Daily: "Good morning! Time for your morning supplements (3 products)."
    Supply: "Your Vitamin D supply runs out in 3 days. Time to restock?"

Other Settings:
  Theme	Sheet: Light / Dark / System.
  Help & Support	In-app WebView or mailto.
  Privacy Policy	WebView.
  App Version	Static. "PharmaGuide v1.0.0". Non-tappable, muted.
Store all health context in local SQLite user_profile table. Never send to Supabase in MVP.

Section 10 — Data Layer & Scoring

10.1 — Local SQLite Tables
pharmaguide_core.db — ships with app by default. First-launch download is fallback only if app size becomes unacceptable.
products_core     — ~180k products. Primary scan/search data. Instant offline.
products_fts      — Full-text search index (FTS5 with porter stemmer).
reference_data    — rda_optimal_uls (~199KB), interaction_rules (~95KB, 45 rules),
                    clinical_risk_taxonomy (~8KB, 14 conditions + 9 drug classes),
                    user_goals_clusters (~11KB).
                    Total ~313KB. Parse ALL at app startup. Hold in memory. Do not re-parse per view.
export_manifest   — db_version, pipeline_version, generated_at, min_app_version.
                    Local SQLite export_manifest does NOT store the artifact checksum.
                    Checksum lives in top-level export_manifest.json from Supabase and is used for safe swap verification.

user_data.db — local read/write DB created by the app and never replaced during OTA updates.
product_detail_cache — dsld_id PK, detail_json TEXT, cached_at, source, detail_version.
user_profile          — goals, conditions, drug_classes, allergies, age, sex.
user_favorites        — dsld_id, added_at.
user_scan_history     — dsld_id, scanned_at.
user_stacks_local     — dsld_id, dosage, timing, supply_count, added_at.

10.2 — SQLite Queries
Barcode Lookup
-- Primary UPC lookup
SELECT * FROM products_core
WHERE upc_sku = ?
ORDER BY
  CASE product_status WHEN 'active' THEN 0 ELSE 1 END,
  score_quality_80 DESC,
  dsld_id
LIMIT 1;

-- If COUNT(*) > 1 for UPC: apply above ordering but show chooser UI if top 2 scores are close.

-- FTS fallback (product name search)
SELECT p.* FROM products_core p
JOIN products_fts f ON p.rowid = f.rowid
WHERE products_fts MATCH ?;

Filter Queries
-- High-scored vegan products
SELECT * FROM products_core
WHERE is_vegan = 1 AND score_quality_80 > 56  -- 56/80 = 70/100
ORDER BY score_quality_80 DESC;

-- Gluten-free multivitamins
SELECT * FROM products_core
WHERE is_gluten_free = 1 AND supplement_type = 'multivitamin';

-- Products with allergen risks
SELECT * FROM products_core WHERE has_allergen_risks = 1;

-- Similar products in same category, higher score
SELECT * FROM products_core
WHERE supplement_type = ? AND score_quality_80 > ? AND dsld_id != ?
ORDER BY score_quality_80 DESC
LIMIT 5;

10.3 — Detail Blob Loading Flow
1.	Show product header instantly from products_core (SQLite).
2.	Check product_detail_cache for dsld_id.
3.	If cached: parse detail_json, check blob_version vs cached detail_version. If version mismatch, re-fetch.
4.	If not cached + online: read `detail_blob_sha256`, derive the hashed detail payload path, fetch from Supabase, then save to product_detail_cache -> render. Fall back to active `detail_index.json` only if the row-level hash is missing.
5.	If not cached + offline: show header only. "Detail unavailable offline" banner.
Show shimmer skeleton for accordion cards while detail loads. Never block the hero section.

Cache policy:
  product_detail_cache uses release-version-aware invalidation. When db_version changes, entries tied to the old release are stale unless their blob_version/hash still matches the active detail_index.
  Use LRU eviction with a fixed size budget. Default target: 200MB max for image cache, separate bounded budget for detail JSON cache.
  Cache lookup must be O(1) by dsld_id. Never scan the whole cache table during product open.

Skeleton detail: 5 shimmer rectangles (card-shaped, 56dp height each) stacked vertically with 8dp gaps.

10.4 — DB Version Update Flow
1.	App launches. Read export_manifest from local SQLite.
2.	If online: fetch remote export_manifest row + export_manifest.json metadata.
3.	If min_app_version > current app version: block the update path and force app-store upgrade before parsing the new release.
4.	If newer version available: download the new DB to a staging file in background. Never block the user.
5.	Verify downloaded file checksum against remote export_manifest.json before swap.
6.	Open the staged DB and perform a minimal integrity/readability check before promotion.
7.	Atomically swap staged DB into place only after checksum + open/parse validation pass:
    a. Close the active pharmaguide_core.db connection.
    b. Rename the current DB to pharmaguide_core.db.bak.
    c. Rename the staged validated DB into the live pharmaguide_core.db path.
    d. Re-open the DB connection and run a smoke query.
    e. Delete the .bak file only after the reopen succeeds.
8.	If any step fails: keep current DB, log to Crashlytics/Sentry, and surface only a subtle retryable update state.
9.	Show subtle "Update available" dot on Profile tab icon if pending.

10.5 — ScoreFitCalculator (on-device personalization)
Replaces ScorePersonalizer from prior spec versions. Formally aligned to pipeline FitScoreResult.
Location: lib/services/score_fit_calculator.dart

Inputs:
  - double score_quality_80 (from products_core)
  - Map<String, dynamic> breakdown (from detail blob)
  - HealthProfile? localProfile (from SQLite user_profile)
  - reference_data (already parsed in memory at startup)

Output: FitScoreResult {
  double scoreFit20         // 0-20
  double scoreCombined100   // (score_quality_80 + scoreFit20) * 100/100
  double maxPossible        // depends on which profile fields are filled
  double dosageAppropriate  // E1: 0-7 (from rda_optimal_uls reference)
  double goalMatch          // E2a: 0-2
  double ageAppropriate     // E2b: 0-3
  double medicalCompat      // E2c: 0-8 (from interaction_rules reference)
  List<String> missingFields // ["age", "conditions"] — show profile completion CTA
  String displayText        // "85/96 (88.5%) - Complete profile for full scoring"
  List<ScoreChip> chips     // UI chips for Card 5
}
score_fit_20 and score_combined_100 are NEVER stored in the DB or pipeline output. Always computed fresh from current profile state.

10.6 — Implementation Notes (from Flutter Data Contract v1)
Mixed naming in ingredient JSON — use @JsonKey
// The detail blob uses BOTH camelCase and snake_case on the same ingredient.
// This is intentional — they come from different pipeline stages.
// DO NOT normalize. Use explicit @JsonKey annotations:
@JsonKey(name: 'standardName')
final String standardName;      // label-parsed (camelCase)

@JsonKey(name: 'standard_name')
final String standardNameIqm;   // IQM-resolved (snake_case)

Warnings are polymorphic — use sealed class
sealed class Warning {
  String get type;
  String get severity;
  String get title;
  String get detail;
  String get source;
}

class BannedSubstanceWarning extends Warning { String? date; String? clinicalRisk; }
class HarmfulAdditiveWarning extends Warning  { String? mechanismOfHarm; List<String>? populationWarnings; }
class AllergenWarning extends Warning          { String? supplementContext; String? prevalence; }
class InteractionWarning extends Warning       { String? action; String? evidenceLevel; List<String>? sources; Map<String, dynamic>? doseThresholdEvaluation; }
class DrugInteractionWarning extends Warning   { String? action; String? evidenceLevel; List<String>? sources; Map<String, dynamic>? doseThresholdEvaluation; }
class DietaryWarning extends Warning           { }
class StatusWarning extends Warning            { }

score_quality_80 can be NULL
  Products with verdict = NOT_SCORED have score_quality_80 = NULL, grade = NULL.
  Every score display path needs a null guard.
  Show "Not Scored" or equivalent. NEVER show 0.

diabetes_friendly / hypertension_friendly default false
  When dietary sensitivity data is absent, these default to 0 (false) — cautious/safe default.
  false does NOT mean "confirmed not friendly" — it means "insufficient data."
  UI should distinguish between "not friendly" (explicit data) and "unknown" (data absent).
  Check whether dietary_sensitivity_detail is populated in detail blob before showing a hard "not friendly" label.

10.7 — Product Enums (from pipeline)

supplement_type — 7 values:
  single_nutrient	One active ingredient (e.g. Vitamin D3)
  targeted	2-5 actives from same category (e.g. Joint Support)
  multivitamin	6+ actives spanning 3+ categories
  herbal_blend	60%+ botanical ingredients
  probiotic	Contains probiotic cultures
  prebiotic	Contains prebiotic fiber
  specialty	Engineered formula (e.g. nootropic stack)

Display as pill badge on product cards and result screen. Use for search category filters.

form_factor — 11 values:
  gummy, chewable, tablet, capsule, softgel, liquid, powder, drop, lozenge, spray, patch

Display as pill badge. Use for search form filters. Show form-appropriate icons where applicable.

Section 11 — Error States & Edge Cases

Scanner Error States
State	Trigger	Design / Content	Dev Notes
Slow detail load	Detail fetch > 3s	Shimmer skeleton on accordion cards. Hero shows from SQLite immediately.	shimmer package.
Fetch timeout	No response > 8s	Dismiss shimmer. Toast: "Unable to fetch product details." Show header only. Retry button.	Retry fetches blob again.
Damaged barcode	Partial scan	Camera continues. No feedback until clean read.	mobile_scanner handles.
Not in SQLite	No UPC match	Show "Product Not Found" sheet and allow submission to pending_products. No remote product search in v1.	—
Supabase fetch fails	Network error	Toast: "Unable to fetch product details." Show header from SQLite. Score from products_core still displays. Retry button.	—
NOT_SCORED	verdict = NOT_SCORED	Show "Not Scored" badge + question mark icon. No ring animation. Accordion cards hidden with "Insufficient data" message.	Never show 0.
PDF image	image_url ends .pdf	Show placeholder illustration (pill icon on light grey bg). Do not attempt to render PDF as image.	—
UPC collision	COUNT(*) > 1	Use deterministic ordering. If top results are very different products, show a simple chooser sheet.	—
Image load fail	CachedNetworkImage error	Show branded placeholder (pill icon). Never show broken image icon.	—

Auth Error States
State	Trigger	Design / Content	Dev Notes
Sign-in failed	OAuth error	Toast: "Sign-in failed. Please try again."	—
Session expired	Supabase 401	Silently refresh token. If fails: sign out + show sign-in sheet.	Handle in auth listener.
Email exists	Duplicate	Toast: "An account with this email already exists. Try signing in."	—

General Rules
  NEVER show raw error codes or stack traces to users.
  Minor errors: Toast (auto-dismiss 4s). Actionable errors: Bottom Sheet with retry.
  Error tracking: Firebase Crashlytics (firebase_crashlytics package). Catches Dart exceptions + native crashes automatically. Set user ID via Crashlytics.instance.setUserIdentifier() after auth. Free, no volume limits, shares dashboard with Firebase Analytics (Section 14). No Supabase error_logs table needed.
  Network errors: always check connectivity first. If offline, show offline banner instead of generic error.

Section 12 — Build Checklist

Implementation Notes Before Starting

Why drift over raw sqflite:
  drift generates typed Dart classes from SQL schemas. This catches contract drift (wrong column name,
  wrong type) at COMPILE TIME instead of runtime. Given this is medical safety data, the extra type
  safety is worth the 1-day setup cost. drift also gives you reactive queries (Stream<List<Product>>)
  which pairs perfectly with Riverpod's AsyncValue pattern.

Sample detail blob for development:
  Request a real exported detail blob JSON (e.g. Thorne Basic Nutrients dsld_id=182215) from the
  data team before starting Phase 2. Having a real blob file lets you build and test all 5 accordion
  cards against actual data shapes. Do NOT build card UI against made-up test data — the field names,
  nesting, and null patterns will differ.

MVP scope boundaries:
  IN SCOPE: Scan, 5-pillar result cards, stack management, AI chat, profile with condition/medication
  chips, condition alert banner, wishlist (add/remove only), share product, score education overlay,
  Pros & Considerations summary, search with filters, supply tracking, notifications.
  POST-MVP (do not build now): Full Analysis deep-dive report, wishlist compatibility checks
  (interaction analysis between wishlist items and current stack), genetic insights, trend analysis,
  "What If" scenario engine, premium paywall/subscription, product comparison view, ingredient glossary,
  "Better Alternative" recommendations.

Phase 1 — Foundation (Week 1-2)
  Flutter project: Inter font, theme.dart (ALL colors for BOTH light and dark modes, styles, shadows — single source of truth).
  flutter_native_splash setup with brand color + logo.
  App icon generation (adaptive icon for Android, standard for iOS).
  SQLite setup: drift (required). pharmaguide_core.db bundled with app for day 1.
  user_data.db created on first launch and never overwritten by DB updates.
  App-side SQLite tables: product_detail_cache, user_profile, user_scan_history, user_stacks_local, user_favorites.
  Hive setup: guest_scan_count, chat_history, recent_searches, has_seen_score_explainer boxes.
  Supabase client: Auth providers (Google, Apple, Email, Anon).
  Riverpod 2.0+ with @riverpod generator. All providers established.
  Local forms: use flutter_hooks + Form/validators (or one equivalent explicit pattern) for Profile and Stack edit flows.
  Parse ALL reference_data JSON at app startup. Hold in memory via singleton provider.
  TaxonomyService validates clinical_risk_taxonomy and chip mappings at startup.
  ScoreFitCalculator written and unit-tested before UI work.
  Parser smoke tests built from real exported fixtures: SAFE, BLOCKED/B0, NOT_SCORED, PDF image, interaction_summary.
  DB update manager written: staged download, checksum verification, rollback, hard min_app_version gate.
  Floating tab bar built (labels on all icons). All 5 tabs scaffold with state preservation.
  Reusable widget library: PrimaryButton, OutlineButton, AppCard, ScoreRing (Flutter-native animation with static fallback), ScoreBadge (WCAG colors), ShimmerCard, ProductImage (handles PDF + error), VerdictBanner (with icons).
  Accessibility foundation: Semantics wrappers, Dynamic Type support verified, Reduce Motion checks.
  Analytics setup (Section 14) + Crashlytics/Sentry setup.
  Deep link routing setup (Section 15).

Phase 2 — Core Scan Loop (Week 2-4)
Budget 2 full weeks is optimistic. De-risk by prioritizing scan loop, B0 gate, and top-of-screen product rendering first.
  Scan tab: camera, permission handling, animated scanner bracket (3 states, with static fallback).
  Barcode -> SQLite lookup. Handle UPC collisions. Handle NOT_SCORED.
  B0 Gate: if verdict = BLOCKED/UNSAFE, render Critical Warning screen (Section 6.4).
  Debounced/limited FTS search working (300ms debounce, LIMIT 50).
  ScoreFitCalculator.calculate() called after SQLite fetch + detail hydration.
  Hero section: animated score ring (650ms). Sticky. Handles NOT_SCORED, PDF image_url, percentile chip.
  Score Education overlay (Section 6.12). First-scan trigger + score ring tap.
  Verdict banner: maps verdict to colors + icons (Section 6.5.3).
  Condition Alert Banner: interaction_summary intersection with user conditions (Section 6.5.4).
  Pros & Considerations summary (Section 6.5.5).
  Detail hydration path: detail blob fetch, product_detail_cache write/read, version-aware invalidation.
  Card 1 and B0-critical safety path must be rock solid before polishing the deeper accordion cards.
  Share product (Section 6.11).
  Add to Stack flow: single sheet, animated transitions.
  Scan limit enforcement: Hive (guest), Supabase (free user). Both enforced.

Phase 3 — Stack & Home (Week 4-5)
  Stack tab: summary card, smart item cards, swipe-to-delete, edit sheet, supply tracking.
  Home tab: header, search bar, hero card both states, carousel (CachedNetworkImage + PDF placeholder), AI insight.
  Search screen: autocomplete, recent searches, category/form filters, virtualized results (Section 5.6), strict LIMIT 50 query cap.
  Offline detection (connectivity_plus). Banners per tab. SQLite always available offline.
  DB version check on launch. Background update if newer pipeline export available.
  Pull-to-refresh on home and stack.

Phase 4 — AI Chat & Profile (Week 5-6)
  Gemini proxy Edge Function deployed (Supabase).
  AI chat: proactive empty state (static + dynamic stack-aware prompts).
  Active chat interface, typing indicator (with reduced motion fallback), quick chips.
  System prompt builder reads SQLite user_profile + Riverpod stack provider.
  AI message limit (5/day) via Supabase user_usage.
  Profile tab: privacy header, condition/medication/goal chips (exact condition_id mapping).
  Auth section: guest CTA vs signed-in display.
  Notification setup: permission flow, daily reminders, supply alerts (Section 9.5).

Phase 5 — Polish & Edge Cases (Week 6-7)
  All error states: Section 11. No raw errors ever shown to users. Retry buttons on actionable errors.
  Shimmer skeletons on all loading states (detail cards, carousel, stack list, search results).
  Haptic feedback audit: all key interactions per Section 2.
  Performance audit: no jank on tab switch, sheet open, score animation. Verify with Flutter DevTools.
  DB swap failure drill: interrupted download, checksum mismatch, corrupt file, forced rollback.
  Dark mode: full token set from Section 2. Test all screens in both modes.
  Accessibility audit: VoiceOver (iOS) and TalkBack (Android) full walkthrough. Dynamic Type at 200%. Reduce Motion enabled.
  Analytics verification: all events firing correctly (Section 14).
  Deep link testing: app link and universal link verification.
  TestFlight / Play Console internal track submission.

Section 13 — Accessibility Requirements

13.1 — Screen Reader Support
All interactive elements MUST have Semantics() labels.
Semantics hierarchy must follow visual hierarchy (score ring > grade > verdict > cards).
Score ring: Semantics(label: "Quality score [X] out of 100, rated [grade]").
Verdict banner: Semantics(label: "[verdict] — [description text]").
Accordion cards: Semantics(label: "[Card name], score [X] out of [max], [expanded/collapsed]"). Use onTap for toggle.
Score badges: Semantics(label: "Score [X], rated [grade]").
Warning severity badges: Semantics(label: "[severity level] warning: [title]").
Chip selections in profile: Semantics(label: "[chip name], [selected/not selected]").

13.2 — Color Independence
Score badges MUST include text label alongside color (e.g. "Good" not just green).
Verdict banner MUST include icon alongside color (checkmark/warning/X).
Severity badges MUST include icon alongside color.
Warning dots on card headers MUST have tooltips or labels.
Never use color as the sole indicator of state.

13.3 — Dynamic Type
All text scales with system font size. Test at 200%.
Minimum body text: 14sp (never smaller for readable content).
Fixed-height containers must expand to accommodate scaled text (use MinimumHeight, not fixed Height).
Stack item cards: use minHeight: 72 not height: 72.
Tab bar labels: scale up to a cap (max 1.3x) to prevent bar overflow.

13.4 — Motion Sensitivity
Check MediaQuery.disableAnimations (or MediaQuery.of(context).disableAnimations).
When true: all animations show static final state, score ring shows final score immediately, stagger is disabled, bottom sheets appear instantly (no slide), accordion opens without animation.
Card 3 border highlight: use static colored border, not pulsing animation.

13.5 — Touch Targets
Minimum 44x44dp for ALL interactive elements.
Use hitSlop / padding to expand tap area when visual element is smaller (icons, close buttons).
Minimum 8dp gap between adjacent touch targets.
Bottom sheet drag handle: 48dp tall touch zone (even though visual is 4dp).

Section 14 — Analytics Events

Track via Firebase Analytics (or Mixpanel). Log locally when offline, flush on reconnect.

Core Events:
app_opened	{user_state: guest/free/premium, has_profile: bool}
scan_completed	{user_state: guest/free/premium, dsld_id, verdict, score_100, source: camera/manual, had_profile: bool}
scan_blocked	{user_state: guest/free/premium, dsld_id, blocking_reason, verdict}
product_viewed	{user_state: guest/free/premium, dsld_id, had_cached_detail: bool, detail_load_ms: int}
card_expanded	{user_state: guest/free/premium, dsld_id, card_name: string, card_number: 1-5}
stack_added	{user_state: guest/free/premium, dsld_id, timing, supply_count}
stack_removed	{user_state: guest/free/premium, dsld_id, days_in_stack: int}
profile_updated	{user_state: guest/free/premium, fields_filled: [string], missing_fields: [string], condition_count: int}
ai_message_sent	{user_state: guest/free/premium, had_stack_context: bool, prompt_type: custom/suggested}
limit_hit	{type: scan/ai, user_state: guest/free}
upgrade_shown	{trigger: scan_limit/ai_limit/profile_tease, user_state}
search_performed	{user_state: guest/free/premium, query, result_count, selected_position: int?, filter_used: string?}
share_tapped	{user_state: guest/free/premium, dsld_id, score_100, verdict}
score_explainer_viewed	{user_state: guest/free/premium, trigger: first_scan/ring_tap}
condition_alert_shown	{user_state: guest/free/premium, dsld_id, conditions_flagged: [string], highest_severity}

Conversion Funnels to Track:
  Scan -> View Result -> Add to Stack (primary)
  Scan -> View Result -> Ask AI (secondary)
  Profile Tease -> Complete Profile (activation)
  Guest -> Sign In (conversion)

Section 15 — Deep Linking & Sharing

15.1 — URL Scheme
App Links (Android) and Universal Links (iOS) for pharmaguide.app domain.

Routes:
  pharmaguide.app/product/{dsld_id}	-> Product result screen (lookup from SQLite by dsld_id, render full result)
  pharmaguide.app/scan	-> Opens scan tab
  pharmaguide.app/stack	-> Opens stack tab

Fallback: if app is not installed, deep link opens app store listing.

15.2 — Share Card
Generated when user taps share icon on result screen.
Contains: product name, brand, score badge, grade, verdict, "Checked with PharmaGuide" footer.
Shared as: text + deep link (pharmaguide.app/product/{dsld_id}).
Future: generate image share card for richer social previews.

15.3 — Implementation
Use app_links package for Android, universal links for iOS.
Register routes in GoRouter (or auto_route).
On deep link received:
  Validate the route shape first. Malformed routes should redirect to Home with a generic "Unable to open link" message.
  Validate dsld_id format before querying SQLite. Invalid IDs should not attempt a DB lookup.
  If dsld_id exists in local SQLite: render.
  If not: show "Product not found" with option to search.

Section 16 — Performance Requirements

16.1 — Targets
Scan-to-result: < 200ms (SQLite lookup is instant, target total UI render time).
Search results: < 100ms for FTS query. Virtualized list for rendering.
Score ring animation: 650ms total. No frame drops.
Tab switch: < 16ms per frame (60fps). No jank. Use AutomaticKeepAliveClientMixin.
Detail blob fetch: show shimmer immediately, timeout at 8s.
App startup: reference_data parse < 500ms. Splash to home < 2s.

16.2 — Image Caching
Use cached_network_image with automatic disk caching.
Cache eviction: LRU, max 200MB disk cache.
Placeholder: branded pill icon on light grey circle (44x44dp).
Error widget: same placeholder. Never show broken image icon or red error.

16.3 — List Virtualization
Search results: ListView.builder with itemExtent: 72 for fixed-height optimization.
Stack list: ListView.builder (items are dynamic height due to text scaling — use estimated extent).
Recent scans carousel: ListView.builder with cacheExtent: 280 (2 items ahead).
Never use ListView with children: [...] for lists that could exceed 20 items.

16.4 — Offline Queue
When user is offline and performs an action that requires Supabase (add to stack for signed-in user):
  Queue the action locally in Hive pending_actions box.
  On reconnect: flush queued actions to Supabase in order.
  Show subtle "Syncing..." indicator when flushing.

Hard Rules — Do Not Violate
1. theme.dart is the ONLY place colors, text styles, and shadows are defined. BOTH light and dark mode tokens.
2. Server-side scan limits are non-negotiable. Supabase RLS enforces for signed-in users.
3. No Edge Function for scoring. ScoreFitCalculator is Dart, local, instant.
4. The Gemini proxy Edge Function IS required. API key never in app binary.
5. score_quality_80 can be NULL. Every display path must null-guard. Never show 0.
6. Condition chip values MUST match pipeline condition_id/drug_class_id exactly. Any mismatch breaks interaction flagging.
7. Parse reference_data JSON ONCE at startup. Never re-parse on every product view.
8. Products with NOT_SCORED verdict: show "Not Scored" with question mark icon. Never a score ring.
9. image_url may be a PDF link. Always check before rendering as image.
10. Health profile (user_profile SQLite) never syncs to Supabase in MVP.
11. All colors MUST pass WCAG AA contrast (4.5:1 for normal text, 3:1 for large text/icons). Use corrected palette from Section 2.
12. Never rely on color alone to convey meaning. Always pair with icon, text label, or pattern.
13. All interactive elements: minimum 44x44dp touch target.
14. Respect Reduce Motion: provide static fallbacks for all animations.
15. Use Lucide icons. Never use emojis as structural UI elements.
Pipeline seed data requirement: products_core must have at least 100 products with fully populated breakdown JSON before Phase 2 scan testing can begin. Coordinate with data team.
