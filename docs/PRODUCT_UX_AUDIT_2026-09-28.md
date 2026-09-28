# PharmaGuide product, UX, accessibility and security audit — 2026-09-28

Baseline `main` d71e47f. Branch `worktree-product-ux-audit`. Walked on the iPhone 17 simulator
(402×874 pt, iOS 26.5, debug build) in light, dark and the largest accessibility text size, plus a
code audit of the same paths. HIG citations are from `~/.agents/skills/apple-design/references/hig/`.

**Limits, stated up front.** Signed-in journeys were read from code only: signing in to the real
Supabase project from an automation session is off-limits. No physical device, so no camera scan,
haptics or release-mode profiling (Flutter can't profile on a simulator). No offline or slow-network
run: the simulator shares the Mac's network. The smallest simulator available is 6.1"; there is no
SE-class device. VoiceOver was not driven; semantics findings come from code and are marked.

---

## 1. Executive summary

**Strong already.** The clinical core is honest in the places that matter most. Quick Check says
"No interaction catalogued … Coverage is finite" instead of "safe", and it has a separate
"Coverage incomplete" state. The `mapped_coverage < 0.3` gate has one owner
(`core/scoring/coverage.dart`). Product detail explains why an evidence pillar is "Limited" even
when the ingredient evidence is strong. The severity palette is contrast-tested in both themes
(`test/core/theme/v2_palette_contrast_test.dart`). The camera pre-permission screen, denied state and
manual-entry fallback are textbook. Dark mode holds up. Sentry scrubbing, PKCE auth, Keychain session
storage and Android backup exclusion are all in place. The v2 token set (`lib/core/theme/v2/`) is
real and mostly respected: 295 of 321 corner radii use tokens.

**Biggest weaknesses.**
1. **The UI sometimes claims more certainty or protection than exists.** Examples: "Safe to add" on
   an empty stack, a Face ID switch that locked nothing, and a real brand wearing a made-up score in
   onboarding. Also "Every check ties back to published NIH ODS, PubMed, and FDA guidance", when
   the curated interaction set is 132 rules and ADR-005 is still PROPOSED. Quality-tier descriptions
   also promise "clean safety profile".
2. **Color says "safe" where the meaning is "quality".** Score-pillar bars, the search focus ring
   and the Quick Check tile borrow severity tokens (`safe`, `monitor`, `caution`).
3. **The information architecture spends a primary slot on nothing.** One of five tabs is a "Chat …
   still being prepared" placeholder. A guest can't use the Stack tab at all, and neither screen says
   so until an "Add" tap hits a sign-in wall.
4. **The sign-in wall comes before value, and it's reused out of context.** The in-app gate has no
   close button, and "Skip for now" throws the user to Home and loses their product.
5. **Accessibility is capped.** Text stops scaling at 1.4× (Apple: "Ideally … at least 200
   percent"). Even inside that cap, the search field clipped the query and Home micro-metrics don't
   scale.

**Changed on this branch.** Round 1 below; round 2, after Sean approved the six decisions,
is in §12.

**Round 1 (6 commits, each test-first).**

| Commit | Fix |
|---|---|
| 8535fac | Removed the always-on "Biometric unlock · Face ID" switch; there is no biometric lock in the app |
| e5fdd53 | Quick Check card no longer clips the evidence level (overflowed 23–55 pt on a 402 pt phone) |
| 4d247d1 | `/dev/v2/*` gallery and fixture routes are registered in debug builds only; `pharmaguide://dev/v2/...` reached them in release |
| a849a4f | Search field grows with text size instead of clipping the query |
| f2371be | Home "Recent scans" aligned to the 24 pt gutter (was 48 pt from double padding) |
| 9244034 | Onboarding score preview labelled "Example" instead of a real brand with a made-up score |

---

## 2. Product inventory (Phase 1)

**Architecture.** Flutter · Riverpod (69 top-level providers) · GoRouter · Drift. There are three
databases. The bundled read-only catalog `pharmaguide_core.db` holds 15,310 products. The bundled
read-only interaction DB 1.0.12 holds 132 curated interactions, 31,787 supp.ai research pairs and
145 profile rules. `user_data.db` is read-write with 14 tables. Supabase provides detail blobs,
auth, OTA and stack sync.

**Navigation** (`lib/app.dart`). One `ShellRoute` with five tabs: Home `/`, Scan `/scan`,
Stack `/stack` (`?tab=wishlist|nutrients`), Chat `/chat`, Profile `/profile`. There are 12 full-screen
routes outside the shell: `/splash`, `/onboarding`, `/auth`, `/auth/callback`, `/profile/setup`,
`/profile/wizard`, `/search`, `/medication-entry`, `/contributions`, `/quick-check`,
`/product/:dsldId` and `/compare/:a/:b`. There are also 15 `/dev/v2/*` previews, now debug-only.
Deep links use the `pharmaguide://` custom scheme on iOS and Android. Routes are normalized by
`normalizePharmaGuideDeepLink`.

**Design system.** The tokens live in `lib/core/theme/v2/`. Spacing is 4–96. Radii are card 12,
sheet 20 and pill. Type is Geist, with Newsreader for display and Geist Mono for metadata, weights
400/500 only, on a 40→10 scale. Motion runs on a six-step ladder with three curves. Shadows come in
three tiers. The palette has 5 severity tiers with light and dark ramps. There are 45 `core/components` and 13
`core/widgets`.
`knowledge/design-system.md` still describes the deleted v1 system (`AppTheme`, `PGCard`,
`PGScoreRing`, SF Pro). None of those symbols exist (`rg "class PGCard\b|class AppTheme\b" lib` →
nothing).

**Journeys walked on the simulator**

| Journey | Path observed | Friction |
|---|---|---|
| A. New user | native launch → 1.3 s animated splash → 4 onboarding pages → celebration → sign-in wall → Home | 7 screens before the first useful action; sign-in before any value |
| B. Guest | Skip → Home → manual barcode → product detail → "Add to my stack" → "Safe to add" sheet → sign-in wall → Skip → Home | loses the product; stack and wishlist are sign-in only; 3 scans/day |
| C. Returning | splash plays every launch (`app.dart` initialLocation is always `/splash`) | +1.3 s per launch; Home scroll position lost on every tab switch |
| D. Scan | camera pre-prompt → system prompt → denied state → manual code → success overlay → PD | denied state offers no "Search by name" |
| E. Interaction | Quick Check: ginkgo + warfarin → "Not recommended" card | evidence level clipped (fixed); result lands below the fold without scrolling to it; results list hidden under the keyboard |
| F. Stack | guest: empty stack shows "Some checks need more information" and a "Timing guidance: no findings for products assessed" card with zero products | vacuous cards; "UL" unexplained |
| G. AI chat | tab shows "Clinical-grade chat is still being prepared" | a primary tab with no feature |
| H. Failure paths | camera denied ✓, product not found ✓ (code), blocked product ✓ | offline/slow/expired-session not runnable here |

---

## 3. Premium UX findings

| Pri | Screen/Flow | Problem | User impact | Fix | Status |
|---|---|---|---|---|---|
| **P0** | PD → Add to stack | Empty stack + guest (no meds, no conditions) shows "No stack interactions found … **Safe to add.**" (`safety_check_sheet.dart:254-263`). `PreAddSafetyResult.clear` also covers "candidate not found" (`stack_safety_providers.dart:56`). | "Safe" is asserted with nothing to check against, and none of the profile checks (e.g. the Pregnancy goal picked in onboarding) ran | For an empty stack: "Nothing in your stack to check this against yet." For the confident clear: drop "Safe to add." and keep "No known interactions with what's in your stack" | **Decision needed.** `safety_check_for_add_medication_test.dart:234` pins "empty stack is a confident clear (safe to affirm)" |
| **P0** | Profile | "Biometric unlock · Face ID" permanently on, `onChanged: null`, no `local_auth` | People believe their health data is behind Face ID | Removed | **Fixed** 8535fac |
| **P1** | In-app sign-in gate | Pushed `/auth` has no close button. "Skip for now" runs `context.go(Routes.home)` (`app.dart:697`). The headline "Save your stack before your first scan." also shows after a scan. | The user loses the product they were on; the copy is wrong in context | When pushed: show a close button, make Skip `pop()`, and add a context headline ("Sign in to save this to your stack") | Open (auth nav is fragile; needs its own branch with `app_post_auth_navigation_test`) |
| **P1** | Tab bar | Chat tab is a placeholder (`app.dart:288`) | 20% of primary nav leads nowhere. `tab-bars.md › Best practices`: "Use the appropriate number of tabs required" | Remove the tab until chat ships; keep Search/Quick Check entry points on Home | **Decision needed** (IA / release) |
| **P1** | Onboarding p4 | "Set up safety profile" → celebration → sign-in (`toProfileSetup` dropped, `onboarding_v2_screen.dart:90-126`) | The label promises one thing and does another | Remove the link (Home and Stack already nudge profile setup) or route it to `/profile/setup` | Open |
| **P1** | Onboarding | 4 explainer pages + celebration + sign-in before anything useful. `onboarding.md › Best practices`: "Teach through interactivity"; `managing-accounts.md`: "Delay sign-in for as long as possible" | Time-to-first-scan is 7 screens | Proposed flow in §6 | Proposed |
| **P1** | Quick Check result | Severity and evidence labels sat in one unwrapped row, overflowing 23 pt (probable) to 55 pt (moderate) on 402 pt | The evidence level, which every warning must show, was clipped | Evidence moved to its own line at 12 pt | **Fixed** e5fdd53 |
| **P1** | Quick Check | Picking the second item leaves its results under the keyboard (seen on sim); the result appears below the fold | The user thinks nothing happened | `Scrollable.ensureVisible` on the results and on the verdict card | Open |
| **P1** | Scan reveal | A recognized product with `no_known_catalog_concern` gets a safety-green full-screen tint, a check and a spring "celebration" (`scanner_logic.dart:59`, `pg_verdict_reveal.dart:106-108`). This fires before any stack, medication or profile check. | Someone on warfarin who scans ginkgo sees a green celebration, then an interaction warning on the next screen | Recognition flash in brand teal ("Found"); amber only for catalog concerns; no `safe` tint at scan time | **Decision needed** (signed off 2026-05-15 as "we recognized this") |
| **P1** | Colour semantics | Score pillar bars use `palette.safe` / `palette.monitor` (`pg_score_breakdown_card.dart:115-119`) | A "Dose 20/20" bar in safety-green reads as "dose is safe" | Use the accent or quality-tier colour; the label ("Strong", "Limited") already carries meaning | Open (visual, needs Sean's eye) |
| **P1** | Quality tiers | Tier descriptions make safety claims: Exceptional "no major safety concerns", Excellent "clean safety profile", Very good "no major red flags" (`score_tier.dart:39-52`) | A quality score reads as a safety verdict | Describe quality only ("Well-formulated, good evidence, transparent label") | **Decision needed** (locked copy) |
| **P1** | Placeholders | Profile rows promise features that don't exist: "Export my data · JSON", "Offline mode · Download catalog for travel", "Accessibility", "Rate" (`settings_v2_screen.dart:203-316`). Each opens an explainer. | Broken promises; App Review 2.1 completeness risk | Remove the rows, or make them non-tappable "Coming soon" text | Open |
| P2 | Home | "Recent scans" at 48 pt vs 24 pt page gutter (SliverPadding 24 + inner Padding 24) | Misaligned; the empty card is narrower than its siblings | Sliver keeps top padding only | **Fixed** f2371be |
| P2 | Home | Empty Stack Health card says "0 supplements · 0 medications" three times, mixing "Supplements"/"supplements" | Noise on the first screen | One line plus a CTA ("Add your first supplement") | Open |
| P2 | Home | Quick Check tile titled "Safe to take together?" while the result is "No interaction catalogued" | The question invites a yes/no safety answer the feature deliberately won't give | "Check two together" (matches the screen's own eyebrow) | Open (copy) |
| P2 | Home/Stack | The same "empty stack" state has different copy on Home ("No data yet · 0 supplements") and Stack ("Some checks need more information before this stack can be rated") | Inconsistent; Stack's version wrongly suggests missing data | One empty-state string from `StackHealthSnapshot` | Open |
| P2 | Stack (empty) | "Timing guidance: No important timing findings identified for the products successfully assessed" with 0 products; "UL warnings" unexplained | Vacuous reassurance plus jargon | Hide timing with 0 products; "upper-limit (UL) warnings" | Open |
| P2 | Onboarding p3 | Hint line disappears at 2 goals and the headline jumps about 20 pt | Layout jump | Keep the line's height (swap text, same box) | Open |
| P2 | Onboarding | A third goal tap silently does nothing | No feedback | The dimmed chips already signal it; add "Up to 2" in the hint | Open |
| P2 | Search | Query clipped at 1.4× (fixed 56 pt box, 16 pt text padding) | Can't read what you typed | `minHeight: 56`, 8 pt padding | **Fixed** a849a4f |
| P2 | Search / QC / PD | Three back glyphs: `arrow_back_rounded` (5), `arrow_back_ios_new_rounded` (4), `chevron_left_rounded` (1) | Chrome feels assembled from parts | One `PGBackButton`: iOS chevron, Android arrow | Open |
| P2 | Buttons | Four button families: `PGPillButton` 47, `TextButton` 28, `FilledButton` 20, `OutlinedButton` 3 | Inconsistent weight and shape | Route primary and secondary through `PGPillButton` | Open |
| P2 | Copy | Capitalization mixed on one sheet: "Find Product", "Open Settings", "Suggested Searches" vs "Allow camera access", "Recent scans" | `writing.md`: "Adopt capitalization rules … then apply them consistently" | Sentence case everywhere (the brand already leans that way) | Open |
| P2 | Launch | 1.3 s animated splash on every launch (`animated_splash_v2_screen.dart:71-78`) | `launching.md`: "Launch instantly"; a splash belongs at the start of onboarding | Play it on first run only; returning users go straight to Home | Open |
| P2 | Tabs | `ShellRoute` + `context.go` rebuilds tabs; Home scroll resets on every switch (seen on sim) | `launching.md`: "Restore the previous state" | `StatefulShellRoute.indexedStack` | Open |
| P2 | Camera denied | Offers Settings + manual barcode only | The natural fallback (type the name) is missing | Add "Search by name" | Open |
| P2 | Wishlist (guest) | "free early-access account so your saved products stay on this device" | Contradictory: an account in order to stay on-device | Say why sign-in is needed, or allow a local wishlist | **Decision needed** (guest scope) |
| P2 | Blocked PD | Two near-duplicate PHO paragraphs, plus "not eligible for the US live catalog" (internal jargon) | Wordy at the most serious moment | Show the summary and put the detail behind "Why" | Open (check the blob owner first) |
| P3 | PD evidence | "~11306 participants" | Unformatted number | `NumberFormat.decimalPattern()` | Open |
| P3 | QC pair line | "warfarin · Ginkgo…" with the second name right-aligned and a floating dot | Reads as two columns | One wrapped line: "warfarin + Ginkgo Biloba Extract 120 mg" | Open |
| P3 | Profile header | A returning user briefly sees "New here — let's get you set up." while the scan count loads (`settings_v2_connected.dart:64` treats loading as `?? 0`). `SettingsV2Screen` also defaults to fixture values (`scanCount = 18`), which is how the dev fixture showed "Sean · 18 scans" | Wrong greeting flash; fixture data one missing argument away from production | Hold the header until loaded; make the constructor arguments required | Open |
| P3 | PD sticky CTA | White band under a warm `#FAF9F6` page | Visible seam | Use `v2.bg` for the bar | Open |

---

## 4. Accessibility findings

| Pri | Where | Problem | Evidence | Fix | Status |
|---|---|---|---|---|---|
| **Critical** | App-wide | `textScaler.clamp(0.9, 1.4)` (`app.dart` MaterialApp builder); no screen opts back in. `accessibility.md › Support larger text sizes`: "Ideally … at least 200 percent" | Sim at AX-XXXL: body grows only to about 22 pt | Raise the cap to 2.0 screen by screen, starting with PD, Quick Check and warnings (long-form clinical text), and verify each on device | Open (broad; needs a walk per screen) |
| High | Home micro-metrics | "0 Supplements / 0 Medications" don't scale at 1.4× while "No signals" does | `shots/ax_home.png` | Remove the `FittedBox`/fixed style; wrap the row | Open |
| High | Search | Query clipped at 1.4× | test + sim | Fixed a849a4f | **Fixed** |
| High | Evidence labels | Mandatory `evidence_level` rendered at 10 pt (`pg_interaction_warnings.dart:411`, Quick Check before e5fdd53). `typography.md`: 11 pt minimum on iOS | code | 12 pt (done in Quick Check); PD badge still 10 pt | Partly fixed |
| Medium | Onboarding "Skip", auth "Skip for now" | `GestureDetector` + `Text`: no button role, about 20 pt tall (`onboarding_v2_screen.dart:196`, `auth_invitation_v2_screen.dart:527`) | code | `TextButton` or `Semantics(button: true)` with a 44 pt target | Open |
| Medium | Type scale | `V2Typography.overline` is 10 pt (18 uses) and a few `fontSize: 10` overrides (hero chips `pg_hero_section.dart:610,651`) | code | Floor the metadata style at 11 pt | Open |
| Medium | Score line | "85/100" and "Very good" are separate texts with no merged semantics (`pg_score_line`, hero) | code; **needs VoiceOver check** | `Semantics(label: '85 out of 100, Very good')` | Needs runtime verification |
| Low | Colour | Quality tier Poor `#DC2626` vs contraindicated `#9F2929`: two reds, different meanings | code | Keep the words next to the colour (already done); consider a non-red Poor | Note |
| ✓ | Severity palette | ≥4.5:1 on every surface in both themes, test-enforced | `v2_palette_contrast_test.dart` | — | Keep |
| ✓ | Reduced motion | Splash and celebration honour `disableAnimations` | `animated_splash_v2_screen.dart:94` | — | Keep |

---

## 5. Security and privacy findings (OWASP MASVS v2 / MASWE)

| Sev | Finding | Class | Evidence | Mitigation | Status |
|---|---|---|---|---|---|
| **High** | Fake security control: Face ID switch shown as on, with no biometric lock in the app | confirmed · MASVS-AUTH (misrepresented control) | `settings_v2_screen.dart` pre-8535fac; no `local_auth` in `pubspec.yaml` | Removed | **Fixed** |
| Medium | Debug routes reachable in release via `pharmaguide://dev/v2/...`: the fixture Profile shows a fake signed-in account with no way out | confirmed (sim) · MASVS-PLATFORM-1 | `xcrun simctl openurl … pharmaguide://dev/v2/settings?signedIn=1` | Debug-only registration | **Fixed** 4d247d1 |
| Medium | iOS `user_data.db` (medications, conditions, allergens, health history) lives in Documents with no backup exclusion; Android deliberately sets `allowBackup=false`. The ~90 MB regenerable catalog and interaction DBs are also in Documents | confirmed (code) · MASVS-STORAGE-2 | `database_providers.dart:254-256, 301`; no `NSURLIsExcludedFromBackupKey` anywhere | Mark `user_data.db` excluded from backup (or move it to Application Support + exclude) to match Android. Move the regenerable DBs to Caches/Application Support (Apple Data Storage Guidelines) | Open (**decision**: iCloud restore of a medication list is a feature for some users) |
| Medium | Privacy copy vs behaviour: "Your medication list stays on this device" while medication autocomplete sends typed text to `rxnav.nlm.nih.gov` | confirmed (code) · MASVS-PRIVACY-3 | `rxnorm_api_service.dart:231-240`; `medication_entry_v2_screen.dart:706` | Add "Name search uses the U.S. National Library of Medicine's RxNorm service." Telemetry is already scrubbed | Open (copy) |
| Low | Newsreader is not bundled (`assets/fonts` holds Geist only), so `google_fonts` fetches it at runtime from Google: IP disclosure, and an offline first launch shows a fallback serif | likely · MASVS-PRIVACY-1 | `assets/fonts/`; 15 `V2Typography.display*` call sites; `allowRuntimeFetching` never set | Bundle Newsreader and set `GoogleFonts.config.allowRuntimeFetching = false` | Needs network trace |
| Low | Sentry navigation breadcrumbs keep `from`/`to` (product IDs in paths); `tracesSampleRate = 1.0` | needs runtime verification · MASVS-PRIVACY-1 | `crash_reporting_service.dart:27-50, 104` | Add route keys to the scrub set, or name routes without IDs; lower sampling after beta (already noted in code) | Open |
| Info | No production secrets in tracked files. Firebase `AIza…` keys are public client IDs (confirm key restrictions in GCP). The anon key is public by design. `sb_secret_` hits are test fixtures; the one password literal is a local docker test stack | confirmed | `scratchpad/classify_secrets.py` over `git ls-files` (values masked) | — | — |
| Info | `sqlite3_flutter_libs` upstream is `0.6.0+eol`; SQLite patching now comes via `sqlite3` ≥3 build hooks | confirmed | `flutter pub outdated` | Plan the migration (security patches to bundled SQLite) | Open |
| ✓ | PKCE auth, session in Keychain (`flutter_secure_storage`), `sendDefaultPii=false`, scrubbed events and breadcrumbs, RxNorm telemetry reduced to an endpoint class, Android backup off, honest camera purpose string | confirmed | code | — | Keep |

---

## 6. Onboarding and retention

**Current friction (measured on the simulator).** A new user passes 7 screens and 5 taps before
Home: splash, 4 pages, a celebration, then sign-in and Skip. It takes 8 taps to reach a live
camera. Then the Home screen has an empty
Stack Health card and an empty Recent scans. A guest who scans and taps "Add to my stack" gets
"Safe to add", then a sign-in wall, and Skip lands on Home without the product.

**Recommended flow (proposed, not implemented).**

1. First run: one value screen (the scan promise, with a live example) plus "Start scanning" and a
   quiet "I'll set up my profile first". Move the splash to be that screen's entrance animation.
2. Go straight to Scan with the camera pre-prompt (already excellent), with manual entry and
   Search by name both visible.
3. First result → contextual tip: "Add what you take to check them together". Ask for sign-in only
   when the user saves, and explain why in that context.
4. Ask for goals and conditions after the first result, where "We use these to explain what matters
   after every scan" is demonstrable.

**Expected effect.** Shorter time to first result and fewer drop-offs at the sign-in wall. This is
unmeasured: the app has no activation analytics, so treat it as a hypothesis (see Experiments).

**Legitimate reasons to come back.** Recall and safety alerts for products in the stack (the push
plumbing exists: `safety_push_provider`). Catalog updates that change a saved product's score.
Dose and upper-limit totals when the stack changes. Health History reminders (already built). None
of these need streaks or notification spam.

---

## 7. Design direction (Phase 4 thesis)

- **Character: "a well-kept clinical notebook".** Warm paper (`#FAF9F6`), deep teal ink, calm
  serif moments, monospaced marginalia for provenance. Keep it; it's specific to this product and
  isn't one of the three default generated looks.
- **Type.** Geist for everything read or tapped. Newsreader only for one headline per screen at
  the first-impression moments (already governed). Geist Mono for provenance: evidence level,
  source, date. **Floor metadata at 11–12 pt.** Mono at 10 pt is the thing that currently fails.
- **Surfaces.** Fewer cards. Empty states are one card, not three. Cards group decisions and
  plain text carries explanation. One accent surface per screen (the Scan CTA on Home).
- **Colour.** Severity colours mean clinical risk and nothing else. Quality uses the tier ramp.
  Brand teal handles interaction (focus, selection, links). This is the single most important
  system rule to restore.
- **Spacing.** 24 pt gutter, 16 pt card padding, 12 pt between related rows, 24 pt between
  sections. Section-level widgets never add their own gutter (the Recent-scans bug).
- **Icons.** One back glyph per platform, and one icon per concept (Quick Check is
  `compare_arrows` on Home but a shield on Chat).
- **Signature interaction.** The recognition moment after a scan, which already exists: a short
  settle with a haptic. It should mean "found", in brand teal. Today it shows safety-green for
  "no catalog concern" before any personal check has run. It should stay the only orchestrated
  moment.
- **Motion.** 180–280 ms, interruptible, and none on repeat interactions. The splash plays once per
  install.

---

## 8. Design-system changes made

No tokens changed. Two conventions were applied and should be written into the design doc:
- An evidence-level label shows whole and at ≥12 pt, on its own line when space is short (e5fdd53).
- Input and pill containers use `minHeight`, never a fixed `height`, so text size can grow them
  (a849a4f).
- `knowledge/design-system.md` still documents the deleted v1 system and needs rewriting for v2
  (open).

## 9. Before → after

| Change | Before | Problem | After |
|---|---|---|---|
| Quick Check card | Severity and evidence in one row; "Moderate supporting evidence" pushed 55 pt past the card on 402 pt | Evidence level clipped in release | Evidence on its own line under the severity label, 12 pt |
| Search field | 56 pt fixed, 22 pt for the text line | Query cut in half at 1.4× | Grows with text; unchanged at default size |
| Home Recent scans | Header and empty card at 48 pt | Misaligned, narrower card | 24 pt like every section |
| Profile | "Biometric unlock · Face ID [on]" | Security control that doesn't exist | Row removed; group renamed "Account" |
| Onboarding p1 | "THORNE · Magnesium Glycinate · 86/100" | Real brand, fabricated score (catalog: Bisglycinate 91) | "EXAMPLE · Magnesium Glycinate · 86/100" |
| Deep links | `pharmaguide://dev/v2/settings?signedIn=1` opened a fake profile | Spoofable fixture UI in release | Not registered outside debug |

Screenshots are in the session scratchpad (`shots/`). After screenshots are listed in the handoff.

## 10. Tests performed

| Command | Result |
|---|---|
| `flutter test` on d71e47f (baseline, before fixes) | +3626 −9. The 9 are pre-existing golden pixel diffs plus this branch's two new biometric tests, written mid-run before the fix |
| Each new test before its fix | red: biometric ×2 (found the switch); Quick Check ×2 ("RenderFlex overflowed by 82 / 55 pixels"); search ×2 (22 pt < 27 / 38 pt line); Home ×2 (48 ≠ 24); onboarding ×1 (found "THORNE"); dev routes (symbol missing) |
| `flutter analyze` (whole repo, after) | No issues found |
| `flutter test` (full, after) | **+3637 −7** |
| The 7 failures with the six changed `lib/` files restored to d71e47f | the same 7 golden files fail with identical pixel counts (0.00–0.11%): `nutrient_progress_bar` ×2, `hero_evidence_review_incomplete`, `probiotic_section` ×2, `med_nutrient` ×2. Pre-existing golden drift on this machine, not caused by this branch |
| Simulator re-check after hot restart (iPhone 17) | Home gutter 24 pt ✓ · Profile without the Face ID row ✓ · search query whole at AX-XXXL ✓ · Quick Check evidence line whole ✓ · onboarding "EXAMPLE" ✓ (via the debug-only `/dev/v2/onboarding`, which also shows debug builds keep the gallery) |

Not run: `make verify-bundle` (no release in scope). No release build either, so the
debug-only route gate is proven by the unit test on `withDevPreviewRoutes` and not by a
release binary.

## 11. Remaining recommendations

**Next (low risk, clear).** Scroll Quick Check results into view. Put the keyboard-covered results
list above the keyboard. Add Search by name to the camera-denied screen. One back button.
Sentence-case pass. Fix the micro-metrics scaling. Show the 10 pt PD evidence badge at 12 pt. Format
participant counts. Hide the empty-stack timing card. Rewrite `knowledge/design-system.md` for v2.
Show a placeholder while product-detail sections load (§12.4).
*Done in round 2:* placeholder Profile rows explained, Newsreader bundled.

**Decided by Sean 2026-09-28: all six, implemented in round 2 (§12).**

**Later (design discussion).** Raise the text-scale cap to 2.0 after the fixes in §12.2. Move to
`StatefulShellRoute` for tab state. Merge the two interaction-card implementations (Quick Check
`_InteractionCard` and `PGInteractionWarnings`). Consolidate the button families. Split a
`positive` token from `safe` (certifications, "in your stack" and success toasts still use the
safety green). Glass tab bar rollout (§12.3).

**Experiments (measure before adopting).** One-screen onboarding vs the current four. Deferred
sign-in (first save) vs the current post-onboarding wall. Guest scan cap of 3 vs 10 per day, watching
first-week retention. A return-visit trigger from recall alerts on stacked products.

---

## 12. Round 2 — Sean's decisions implemented (2026-09-28)

Sean approved all six recommendations and added five specific asks and a Liquid Glass
prototype. Each change is its own commit with a test that fails on the old code.

### 12.1 What changed

| Commit | Change |
|---|---|
| e4c0ecd | Newsreader bundled (byte-identical to the file the app was downloading, sha256 `f1832462…`); `V2Typography.useBundledFontsOnly()` turns runtime font fetching off and registers the SIL OFL licences for Geist and Newsreader, which were missing |
| d6066a8 | Pre-add sheet never says "safe". An empty stack gets "Nothing in your stack to check against yet"; a clear check gets "No known interactions with your stack … the list is finite" (info tone, not green). A product missing from the catalog counts as not checked. The Home tile "Safe to take together?" is now "Check two together" |
| f4fafae | Chat tab, `/chat` route and placeholder removed. Unknown paths (old `pharmaguide://chat` links, typos) go Home instead of go_router's bare "Page Not Found" |
| b78a002 | Safety colours for clinical risk only: the scan flash for a recognized product is brand teal "found" with no spring; score pillars use the accent; the Quick Check tile and search focus use the accent |
| 2d8147c | Quality-tier descriptions use quality words only ("clean safety profile" and similar are gone) |
| 3773011 | Guests keep a stack and wishlist on the device (the sync path already handled it: guests skip sync, the first sign-in adopts and pushes the supplement rows, medications never sync). The wishlist stays after sign-out, like the stack |
| f2523ee | The sign-in page has a Close button, and Skip returns to the page that opened it (`leaveAuthInvitation`), going Home only when nothing is underneath. Copy says what an account adds; Skip is a real 44 pt button |
| 594a252 | Onboarding is one screen: "Start scanning" opens the camera, "Set up my profile first" opens the guided wizard, and there is no sign-in step. The splash plays on first run only (`initialAppLocation`). `PGCelebration` deleted |
| 89fffd6 | Placeholder Profile rows explain what works today and point to something real. Medication name search is disclosed: it goes to the U.S. National Library of Medicine (RxNorm), on medication entry, Quick Check and the Privacy dashboard |
| 24aab1b | iOS: `Documents` and `Application Support` excluded from iCloud and computer backups at launch, matching Android. Verified on the simulator: both directories carry `com.apple.metadata:com_apple_backup_excludeItem`, and `user_data.db` plus its `-wal`/`-shm` files live in `Documents`. The Privacy dashboard says so (a new phone starts fresh; a signed-in supplement stack syncs back), and its info sheet now scrolls (the longer list overflowed by 26 px) |
| 94ffeb3 | The Profile "Sign in" row says "Back up and sync your stack" (was "Save stack, profile, and history") |
| 26836ac, c994537 | Debug-only glass tab bar prototype (§12.3) |

All checked on the iPhone 17 simulator from a fresh install:
- first-run onboarding → "Start scanning" → camera pre-prompt, 2 taps from launch;
- "Add to my stack" as a guest shows the empty-stack wording and adds with no sign-in page;
- 4-tab bar;
- teal score pillars;
- the "Check two together" tile;
- the sign-in page's Close returns to Profile;
- the guest profile reads "1 in stack · 1 scan".

### 12.2 Text scaling: should the 1.4× cap go to 2.0×? (Sean asked for an opinion)

**Experiment.** I set the cap to 2.0× (uncommitted), set the simulator to the largest accessibility
size, and walked Home and the product page.

- **Home.** The Scan card's title breaks mid-word ("supplemen / t"). The recent-scan card is a fixed
  height and overflows by **56 px** (`home_v2_screen.dart:1098`), cutting off the product name.
  The metric labels ("1 Supplement") don't scale at all, and the search placeholder truncates.
- **Product page.** The sticky "In your stack · Remove" bar overflows by **31 px**. The dose line
  truncates to "500 caplet(s) · Ta…", so "Take 1 caplet daily" is lost, and the tier reads "Very g…".
- **Scaled cleanly.** Headlines, body text, the For-you card and the tab bar.

**Opinion: yes, go to 2.0×, but not as a one-line change.** Apple's "at least 200 percent" is the
right target for a health app whose users skew older. But flipping the cap today would ship two
overflows and truncate dose instructions, which is worse than a 1.4× cap. The work is bounded:
1. Let these grow instead of fixing their height or truncating: the Scan CTA (stack the icon
   above the title at large sizes), the recent-scan card, the PD sticky bar (wrap into two rows),
   the PD hero meta and score lines, and the metric row (drop the `FittedBox`).
2. Add a large-text smoke test: pump each main screen at `TextScaler.linear(2.0)` and assert no
   overflow, like the Quick Check width test in round 1.
3. Then raise the cap to 2.0 in one commit, with simulator screenshots of each screen at AX5.

That's one focused session. Leave the cap at 1.4× until step 1 lands. The Accessibility sheet now
says the largest sizes are capped for now.

### 12.3 iOS 26 interactive Liquid Glass (Sean's addition)

**Audit.** The current `PGFrostedNavBar` is a full-width, edge-attached Material `NavigationBar`
behind a `BackdropFilter`, with a static M3 pill. It has no floating capsule and no press response.
Buttons come in four families (§3). Flutter 3.44.6 has no Liquid Glass support in the framework
(`rg -i "liquid.?glass|glassEffect"` over the SDK finds nothing). Xcode 27 / iOS SDK 27.0 and an
iOS 26.5 simulator are installed, so the native material is available to Swift code.

**Native reference.** I captured Apple's Files app tab bar on the iOS 26.5 simulator, mid-press
and mid-drag. At rest it's an inset floating capsule with a light pill under the selected tab and
brand colour only on the selected icon and label. On touch it shows a glass lens about 1.34× the
tab's width and 1.36× the bar's height, rising past the capsule. The lens magnifies the tab under
it (which switches to its filled icon), has a faint iridescent rim and a soft shadow, and the whole
capsule swells about 3.5%. The lens tracks the finger across tabs and settles into the pill on
release.

**Prototype** (`/dev/v2/glass-nav`, debug-only, over the real Home screen).
- `PGGlassTabBar` reproduces each of those beats. The magnification is `RawMagnifier`, Flutter's
  correct primitive for a positioned, magnified backdrop. The capsule is a blur with a 1.3×
  saturation lift. Springs follow Apple's response/damping model, and crossing into a tab ticks a
  selection haptic.
- Reduce Motion drops the lens. Increase Contrast, Reduce Transparency and Android get an opaque
  outlined bar. Tabs are labelled, selectable buttons with 44 pt targets.
- **Reduce Transparency needed a bridge.** Flutter's `AccessibilityFeatures` has no flag for it
  (dart:ui carries Reduce Motion, Increase Contrast and Bold Text only), so the first prototype
  ignored it. `AppDelegate.swift` now reports `UIAccessibility.isReduceTransparencyEnabled` and its
  change notification on `pharmaguide/accessibility`, and `lib/core/theme/reduce_transparency.dart`
  owns the value. The shipped `PGFrostedNavBar` and `PGFrostedHeader` honour it too, which was a
  gap in production, not just the prototype. On the simulator, switching it on in Settings turns the
  glass bar and the shipped bar solid without relaunching, and switching it off restores the blur.
- Five widget tests. On the simulator, after tuning against the native capture, the press, drag
  and settle read close to native in side-by-side screenshots.
- **What it can't do:** real refraction of the iOS material, dynamic light/dark adaptation of the
  glass to the content underneath, and the exact native spring feel. Those need the platform.

**Native option.** On iOS 26+, a `UiKitView` hosting a real `UITabBar` (or a SwiftUI
`GlassEffectContainer`) would get the true material and interaction for free. The costs:
- an always-on platform view on every tab screen, which pushes Flutter onto its platform-view
  compositing path (measurable frame cost, and the reason it's rarely done for the main bar);
- two tab-bar implementations to keep in sync (Android and iOS < 26 still need the Flutter bar);
- accessibility bridging across the boundary.

A small spike would settle whether the cost is acceptable. It needs a physical device, because the
simulator can't profile.

**Where it belongs** (liquid-glass.md: glass only on the functional layer, used sparingly):
- **Yes:** the bottom tab bar (first); scanner controls over the camera (torch, manual entry;
  clear glass over live video); the Stack/Nutrients/Wishlist segmented control; compact floating
  toolbar actions (share, wishlist, compare on the product page).
- **No:** content cards, ingredient rows, warnings, evidence panels, interaction cards, the score
  hero, or anything read to make a clinical decision.

**Recommendation.**
1. Ship the Flutter glass tab bar as the shell's bar (replacing `PGFrostedNavBar`) after a device
   check on a physical iPhone. It's self-contained, tested, and falls back cleanly.
2. Run the native `UITabBar` platform-view spike on a device, and adopt it on iOS 26+ only if frame
   times stay clean.
3. Then extend glass to the scanner controls and the segmented control. Nothing else.

### 12.4 New findings from the device walk

- **P2, perceived performance.** On a first open, the product page renders hero, For-you and footer
  as if complete, then "What's inside", the score breakdown and evidence pop in 1–2 s later when the
  detail blob arrives. No placeholder, so the page jumps. Fix: section skeletons while the blob loads.
- **P3.** `camera_permission_v2_screen.dart:83` overflows by 8 px while the manual-entry sheet and
  keyboard are up (transient, hidden behind the sheet).
- **Known, tracked (ADR-006 memory).** A guest's one-product stack shows the Stack Health tier
  "Optimized". The ADR defines it as "no identified concerns under the checks that completed", but a
  green "Optimized" for one vitamin C with no profile reads as praise. Left for the ADR-006 copy item.
- **Remaining safety-green uses:** certifications, "in your stack", success toasts, formulation
  enhancers. A `positive` token split is under Later.

### 12.5 Tests (round 2)

| Command | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` (full, at ec3cdff1) | +3662 −7: only the 7 pre-existing golden pixel diffs |
| `flutter test test/core test/dev test/app_test.dart test/app_deep_link_test.dart` (at 7f4ecece) | +538 −2: only the 2 pre-existing nutrient-bar goldens |
| New or changed regression tests | fonts (fails when Newsreader is missing), safety sheet ×2 + provider ×2, app tabs + unknown path, colours ×4, tier copy, guest stack + wishlist ×4, sign-in page ×4, onboarding ×3 (red on the old screen), splash ×2, settings copy ×6, RxNorm disclosure ×3, glass prototype ×6, Reduce Transparency owner ×5 + nav bar ×2 + header ×1 |
