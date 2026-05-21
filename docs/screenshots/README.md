# Marketing Screenshots

End-to-end workflow for producing the 4 mobile UI shots used on the
PharmaGuide.ai website / store listings. Output is the **real Flutter
app** rendered in the iOS simulator, not a mock — so what you see is
what users get.

## TL;DR

```bash
# One-time
git lfs pull                 # materialize assets/db/pharmaguide_core.db
xcode-select --install        # if you don't have command-line tools

# Each capture session
make screenshots              # produces docs/screenshots/raw/0X-*.png
open https://shots.so          # drag PNGs in → download framed PNGs
```

Output: 4 PNGs at 1179×2556 (iPhone 15 Pro native). Drop into
[shots.so](https://shots.so) for device frames.

## The 4 shots

| # | File | Route | What it shows | Why it's the moneyshot |
|---|---|---|---|---|
| 1 | `01-scan.png` | `/scan` | Live camera scanner with reticle | The primary action — instantly readable |
| 2 | `02-my-stack.png` | `/stack` | Mixed-state stack (1 caution, others safe) | Proves the product is *doing work* |
| 3 | `03-product-fitscore.png` | `/product/<vitamin-d3>` | High FitScore, evidence chips | "Everything works" shot |
| 4 | `04-interaction-warning.png` | `/product/<sjw>?section=interactions` | Contraindicated warning (St. John's Wort × SSRI) | The differentiator |

## How it works

Two `--dart-define` flags wire the capture path:

| Flag | Purpose | Code |
|---|---|---|
| `SCREENSHOT_MODE=true` | Triggers `ScreenshotSeeder.maybeRun()` on app launch | `lib/features/dev/screenshot_seeder.dart` |
| `SCREENSHOT_ROUTE=/path` | Overrides `GoRouter.initialLocation` | `lib/app.dart` |

Both are **kDebugMode-gated** — release builds ignore them entirely.
The seeder is also **idempotent**: re-running the script never
duplicates stack entries (it checks `dsldId` and `rxcui` before insert).

### The seeded stack

| Item | Resolution | Why |
|---|---|---|
| Top-scoring Vitamin D3 | `coreDb.searchProducts('vitamin d3')` → sort by `scoreQuality80` | Hero / FitScore shot |
| Top St. John's Wort | `coreDb.searchProducts("st. john's wort")` → sort by score | Interaction shot |
| Top Magnesium Glycinate | `coreDb.searchProducts('magnesium glycinate')` | Filler so My Stack has variety |
| Sertraline (SSRI) | RxCUI `36437` + drug class `antidepressants_ssri_snri` | Other half of the interaction |

The St. John's Wort × SSRI interaction is curated in
`interaction_db.sqlite` (CYP3A4 induction + serotonin syndrome risk),
so the warning surfaces automatically once both items are in the stack.

dsldIds are **resolved at runtime** — the script doesn't hard-code IDs
that could drift across catalog rebuilds. The capture script reads
them from `flutter logs` and substitutes them into the
`/product/<id>` routes for shots 3 and 4.

## Manual flow (without the script)

```bash
# Boot a clean iPhone 15 Pro
xcrun simctl boot "iPhone 15 Pro"
open -a Simulator

# Seed + jump to scan
flutter run \
  --dart-define=SCREENSHOT_MODE=true \
  --dart-define=SCREENSHOT_ROUTE=/scan \
  $(grep -v '^#' .env | xargs -I{} echo --dart-define={}) \
  -d "iPhone 15 Pro"

# In another terminal, when ready:
xcrun simctl io booted screenshot ~/Desktop/01-scan.png
```

## Framing in shots.so

1. Drag a raw PNG into [shots.so](https://shots.so).
2. Choose **iPhone 15 Pro** frame (Natural Titanium recommended — most
   neutral; Black absorbs UI darks; White washes out white surfaces).
3. **Background**: solid `#F5F7FA` for landing-page hero cards, or
   transparent for compositing.
4. **Shadow**: medium. Soft shadows read as "real product"; hard
   shadows read as "stock photo".
5. Export at **2x** for retina web (gives ~2400px wide framed PNG).

## Per-shot styling for the website

Suggested captions (concise; the screenshots already do the heavy
lifting):

- **Scan** — "Point. Tap. Know." or "Scan any supplement"
- **Stack** — "Your stack, watched in real time"
- **Product detail** — "Independent scoring. No paid placements."
- **Interaction warning** — "Catches the conflict before you buy it"

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `error: ... is missing or an LFS pointer` | Core DB not materialized | `git lfs pull` |
| `simulator '...' not found` | Bad device name | `xcrun simctl list devices available` |
| Seeder log empty + dsldIds unresolved | Items already seeded from a prior run | Script falls back to reading `user_data.db` from the sim container automatically |
| Screenshot shows splash/onboarding | `SCREENSHOT_ROUTE` env var not picked up | Confirm dart-define is being passed; check `flutter logs` for the route value |
| Stack screen empty | Seeder failed silently | `flutter logs \| grep screenshot-seeder` — usually a missing product match for one of the search queries |

## Don't ship this code

The seeder is gated by **both** `kDebugMode` and `SCREENSHOT_MODE=true`.
A release build with `--release` cannot trigger it regardless of
dart-defines — `kDebugMode` is a compile-time constant that constant-folds
the seeder body out of the release tree.

If you add new dev-only hooks under `lib/features/dev/`, keep the same
double-gate pattern.
