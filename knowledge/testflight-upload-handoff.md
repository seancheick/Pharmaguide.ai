# TestFlight Upload Handoff

**Build:** `1.0.0+2`
**Build flags:** `USE_V2_PRODUCT_DETAIL=true`, `SENTRY_ENVIRONMENT=testflight`
**Archive location:** `build/ios/archive/Runner.xcarchive`
**Date:** 2026-05-16

---

## Why this handoff exists

Flutter CLI's `flutter build ipa` cannot complete the export step on
this Mac because the local keychain lacks an Apple Distribution
certificate, and team `SVBYWES848` doesn't have App Store Connect
provisioning permission for `com.pharmaguide.app` auto-issuable from
the CLI.

Xcode Organizer can fetch + create the cert and profile on the fly
through your Apple ID. CLI cannot.

**Do not retry CLI export.** This is an Apple account/keychain state,
not a code state.

---

## What's in this archive

All commits up to `2f28911 chore(version): bump to 1.0.0+2 for TestFlight rebuild` on `design/v2-mobile-polish`. Key surfaces:

| Surface | State |
|---|---|
| Splash | v2 production route + accent underline animation (draw-in + slow breath) |
| Onboarding | v2 production route, 4-step editorial flow |
| Auth Invitation | v2 production route at `/auth`, Apple/Google/MagicLink/Skip CTAs wired to `PGAuthService` |
| Home | v2 with empty-state size parity + centered footer |
| Profile (Settings) | v2 with "Hello there" guest greeting, no avatar circle, Edit Profile wired |
| Stack | v2 with row tap → `/product/<dsldId>` |
| Product Detail | v2 ConnectedScreen on production `/product/:dsldId` route (flag-gated, set to ON in this build) — all 18 sections, j-batch polish (S4 compact note, S7 "Additive concern", S11 evidence helper, S14 CFU transparency, S1 hero tightened, S1 trust chips grouped) |
| Camera permission | v2 prompt + denied screens |
| Native iOS LaunchScreen | Cream `#FAF9F6` (no white flash) |
| Medication entry | "Selected but not found" bug fixed + schedule chip selector |

Sentry: `environment: testflight` (separated from `development` debug noise).
Bundle version: `1.0.0+2` (bumped from +1 to avoid App Store Connect dup-rejection).

---

## Upload path — Xcode Organizer

### 1. Open the archive
```bash
open "/Users/seancheick/PharmaGuide ai/build/ios/archive/Runner.xcarchive"
```
This opens **Xcode Organizer** in the Archives tab. The fresh `1.0.0 (2)` Pharmaguide archive will be at the top.

### 2. Click Distribute App
Select the archive → click the blue **Distribute App** button (top-right).

### 3. Pick the right distribution type
- ✅ **App Store Connect** (this is what you want for TestFlight)
- ⛔ NOT "Ad Hoc", NOT "Development", NOT "Enterprise"

### 4. Choose Upload
- ✅ **Upload** (sends to App Store Connect for TestFlight processing)
- ⛔ NOT "Export" (which is what failed in CLI — same signing path)

### 5. Sign in with the Apple ID that owns team SVBYWES848
Xcode prompts for the Apple ID associated with the developer team.
**This is the critical step the CLI can't do.** Xcode reaches the
developer portal, fetches your cert + provisioning profile (or
creates them if absent), signs the IPA, then uploads.

### 6. Confirm options
Xcode shows the export options screen. Defaults are usually fine:
- ✅ Upload your app's symbols (helps Sentry/Apple crash reports)
- ✅ Manage Version and Build Number — **leave OFF** (we already set
  `1.0.0+2` explicitly)
- Distribution certificate: should auto-resolve to "Apple
  Distribution: Cheick Baradji (...)" once Xcode pulls it
- Provisioning profile: auto-resolve to a profile matching
  `com.pharmaguide.app`

### 7. Click Upload
The upload bar runs ~30-90 seconds depending on connection.
Xcode shows "Upload Successful" when complete.

### 8. Wait for App Store Connect processing
After upload, App Store Connect runs its own processing for
~5-15 minutes (binary inspection, ITMS validation). You'll see the
build appear in:
- **App Store Connect → My Apps → Pharmaguide → TestFlight → Builds**

When it shows "Ready to Submit" or "Ready to Test", the build is
TestFlight-distributable.

### 9. Add testers
- TestFlight tab → Internal Testing → click your test group
- Add the new build (`1.0.0 build 2`) to the group
- Testers get an email + push notification with the install link

---

## If Step 5 fails with "team does not have permission"

The Apple Developer Program enrollment for team `SVBYWES848` either:
- **Doesn't exist yet** — need $99/year enrollment at https://developer.apple.com/programs/enroll
- **Is still pending approval** — Apple takes 24-48h for new memberships
- **Doesn't own `com.pharmaguide.app` as a registered Bundle ID** — register at https://developer.apple.com/account → Identifiers → "+"

Diagnostic: visit https://developer.apple.com/account and confirm:
1. Team `SVBYWES848` is listed under **Membership** with status "Active"
2. **Identifiers** tab includes `com.pharmaguide.app` (Explicit App ID)
3. **Certificates** tab has at least one "Apple Distribution" cert

If any of those is missing, that's the blocker — code is fine.

---

## Common gotchas that aren't blockers

- **App icon placeholder warning** during build — cosmetic. App Store
  Connect won't reject, but tester icons will show the Flutter
  default. Cosmetic fix only.
- **iOS 13.0 deployment target** — fine. App Store Connect accepts.
- **`development` Impeller validation message** in debug builds —
  irrelevant; release builds don't emit it.

---

## Testers' acceptance criteria

See `knowledge/product-detail-v2-testflight-checklist.md` for the
9-point pass/fail list. Key surfaces to exercise:

1. Cold-boot splash → onboarding → auth → home flow (visual)
2. Product Detail v2 on real-blob products (S6 ingredients, S11
   evidence citations, S14 probiotic CFU, S15 manufacturer violations
   if encountered, S18 legacy allergen banner if encountered)
3. Stack row tap → product detail
4. Edit profile → multi-step editor (legacy screen, still functional)
5. Medication entry: search → select (no "not found" appearing on
   selected state) + schedule chip selection
6. Blocked product flow (any FDA-banned dsldId — try Thorne
   Vinpocetine `16012` or Memoractiv `16072`)
7. Sticky CTA: Add to Stack / Remove from Stack regression check
8. Long-name product (`178767` Spring Valley Adults And Children
   3+ Gummies Vitamin C 88-char name) — hero typography
9. Discontinued product (`65844` Thorne MediPro) — S4 compact note
   tier "Product discontinued · Aug 8, 2017" with tap-to-explanation

---

## What's NOT in this TestFlight build

- Scanner v2 (Phase 11.8) — still legacy ScannerScreen, blocked on
  PD v2 TestFlight pass
- Profile setup v2 (Phase 11.10) — still legacy multi-step screen
- Search v2 (Phase 11.10) — still legacy
- Quick Check v2 (Phase 11.10) — still legacy
- Medication entry v2 (Phase 11.10) — legacy with the j.9 bug fixes
  applied

The v2 work for these surfaces requires designed widgets first
(Phase 11.10 designs that scope).

---

## Rollback plan

If a tester reports a v2 regression that's blocking:

1. Immediate: build `1.0.0+3` without the toggle:
   ```bash
   make build-ipa SENTRY_ENVIRONMENT=testflight
   ```
   (no `--dart-define=USE_V2_PRODUCT_DETAIL=true`)

2. Upload through Xcode Organizer same way. Testers get a new
   build with v2 Product Detail OFF (legacy `/product/:dsldId`
   route restored).

3. v2 widget files remain on disk, dev route stays at
   `/dev/v2/product/:dsldId` for QA continuation.

No git revert needed.
