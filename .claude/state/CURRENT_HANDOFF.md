# Current handoff — iOS 26 simulator and score-label correction

Date: 2026-10-25
Branch: `codex/ios26-simulator-tier-labels`
Baseline: `1e85f885`

Goal: restore the supported Apple-silicon iOS 26+ simulator path, verify the signed-out authentication entry point, and correct product-detail score labels/layout observed during the live run. No pipeline, catalog, clinical, release, or publication work belongs to this lane.

Owner Check:
- Simulator compatibility: `ios/Podfile` using the ML Kit plugin's shipped `apple_silicon_simulator.rb` helper.
- Development launch contract: `Makefile::run-ios` and `run-v2-ios`; all runtime configuration still comes from the existing `DART_DEFINES` owner.
- Score layout: `lib/core/components/pg_score_line.dart::PGScoreLine`.
- Tier display vocabulary: `lib/core/scoring/score_tier.dart::ScoreTierMeta.label`; catalog aliases continue to parse through `_catalogTierFromLabel`.
- Will NOT create: a second auth configuration path, score, tier calculation, safety verdict, or pipeline field.

Implemented:
- Opted the Podfile into the ML Kit package's Apple-silicon simulator patch so arm64 iOS 26 simulators build.
- Upgraded the local Flutter stable toolchain from 3.44.6 to 3.47.8 for Xcode 27 compatibility; accepted Flutter's lock/analyzer migrations.
- Made simulator device selection explicit with `make run-ios IOS_DEVICE=<name-or-UDID>` and stopped Make from echoing injected configuration values.
- Kept prominent product-detail score and tier on one line; compact recent-scan cards retain their deliberate stacked treatment.
- Applied Sean's display ladder: Elite / Excellent / Very good / Good / Fair / Poor, while retaining legacy catalog aliases such as Exceptional, Needs improvement, and Weak.

Verification:
- `make verify-supabase`: HTTP 200.
- `pod install`: 25 dependencies / 53 pods; ML Kit reports Apple-silicon simulator support enabled for five frameworks.
- Live `make run-ios IOS_DEVICE=DB137D33-E2D6-4D15-92E4-F65E2A737A9B`: Xcode build succeeded on iOS 26.5; Supabase initialized; clean signed-out onboarding rendered.
- Live auth probe through the real `/dev/v2/auth` route: Google authorization reached the genuine `accounts.google.com` credential form. No credentials were entered.
- Focused score, product-detail, simulator-contract, and auth suite: 108 tests passed with golden tests excluded. The golden-only run showed a 0.03% pixel drift after the Flutter 3.47 toolchain update; no golden was rewritten.
- `make analyze`: no issues.
- `git diff --check`: clean.
- Adversarial PR review found prominent-score scaling could defeat larger accessibility text; replaced it with a full-size responsive wrap and added a constrained 2x-text regression test.

Open validation:
- Exact-head CI after push. The user must enter their own Google/Apple/email credentials to verify account-specific completion; credential entry was intentionally not automated.
