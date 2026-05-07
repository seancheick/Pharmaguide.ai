# PharmaGuide Design System

Source of truth for visual + interaction rules. Most of this also lives as
code comments in `lib/core/theme/` and `lib/core/widgets/`; this doc
gathers the rules in one place and explains the *why* so the next dev (or
future-you) doesn't re-litigate them.

**Direction:** soft clinical premium — Apple Health meets a medical
journal. Layered M3 surface roles, warm neutrals, restrained motion,
legible type. iOS-leaning chrome on top of a fully-themed Material 3 base.

---

## Tokens

All tokens live in `lib/core/theme/`. **Do not hardcode hex, durations,
radii, or spacing in feature code** — if you need a value not in the
token set, add it here.

| Token group | File | Examples |
|---|---|---|
| Spacing (8dp grid + 4dp half-steps) | [app_theme.dart](../lib/core/theme/app_theme.dart) | `space2`, `space4`, …, `space64` |
| Radius | [app_theme.dart](../lib/core/theme/app_theme.dart) | `radiusSmall` (8) → `radiusFull` (999, pill) |
| Color (brand, surface, text, severity, score, evidence) | [app_theme.dart](../lib/core/theme/app_theme.dart) | `brandTeal`, `severityCaution`, `evidenceStrong`, `insufficientData` |
| Motion durations + curves | [app_motion.dart](../lib/core/theme/app_motion.dart) | `fast` (150), `medium` (240), `slow` (320), `emphasized` (420), `gentleRelease`, `spring` |
| Elevation (shadow sets) | [app_motion.dart](../lib/core/theme/app_motion.dart) | `AppElevation.none` / `low` / `medium` / `high` |

**Severity vs score colors are intentionally distinct.** `severityCaution`
(amber) is medical risk; `scoreFair` (also amber-ish, slightly different
hue) is a quality rating. Do not interchange — they communicate different
concepts to the user.

**`insufficientData` is indigo, not gray.** Gray reads as "disabled" or
"missing"; indigo reads as "honest unknown." Used wherever the answer is
"we don't have enough data to score this."

---

## Surface system — 4 tiers, with cardinality rules

Every visible standalone surface on a screen maps to exactly one of these
four tiers. Cardinality is part of the contract — more than one accent
surface on a screen creates competing emphasis.

| Tier | Variant | Cardinality | When |
|---|---|---|---|
| **hero** | bespoke gradient (e.g. [home_scan_cta.dart](../lib/features/home/widgets/home_scan_cta.dart)) | **1 per screen** | The dominant primary action. |
| **standard** | `PGCard(plain)` / `PGCard(elevated)` | many | Default for any standalone content card. |
| **accent** | `PGCard(highlighted)` | **0–1 per screen** | Single soft brand-tinted callout. |
| **recessed** | `PGCard(recessed)` | many | Quieter content (empty states, supporting panels). |

**Intra-card layout primitives** (a `Container + BoxDecoration` *inside*
an already-tiered PGCard — section dividers, tinted info chips, metric
strips) are NOT a fifth tier. They're layout building blocks of the
parent card.

**If you find yourself wanting two `highlighted` cards on one screen:**
demote one to `plain` and rely on size/position for emphasis instead.

---

## Typography

Defined in [app_theme.dart](../lib/core/theme/app_theme.dart) `_textTheme()`.
Scale: **Display → Headline → Title → Body → Label**, three sizes each.

- **Minimum interactive label:** 12px
- **Minimum body:** 13px
- **Below 13px:** metadata only, never interactive
- **Numeric alignment:** wrap with `AppTheme.numeric(style)` for tabular figures (dosages, scores, durations)

**Font:** SF system on iOS (`fontFamily: null` lets the OS supply
.SF Pro Text/Display with built-in optical sizing — basically free
"feels native"). Inter on Android. Both metrically close, layouts don't
break across platforms.

---

## Custom widgets — when to use what

Located in `lib/core/widgets/`. Always prefer these over raw
`Container + BoxDecoration`.

| Widget | Use for | Skip (use Material) |
|---|---|---|
| `PGCard` (4 variants) | Any standalone content card | Inline tinted strips inside another card |
| `PGPressable` | Apple-style scale-on-press wrapper | Already-Material widgets where InkWell ripple is wanted |
| `PGFrostedNavBar` | Bottom nav (the only one) | — |
| `PGFrostedAppBar` | Top app bar | — |
| `PGCircularIconButton` | Floating circular icon-button (top chrome, modal dismiss) | Filled buttons (use `FilledButton` from theme) |
| `PGFilterChip` | Pill-shape filter chip with full-fill animation | Material `FilterChip` (has checkmark + ripple we don't want) |
| `PGSearchField` | Search input with animated focus ring | Material `SearchBar` — see "Open M3 questions" below |
| `PGSeverityBanner` | Medical-tone full-width banner (5 tones) | Material `Banner` (too austere, no severity vocabulary) |
| `PGModal.bottomSheet` | All modal sheets | Direct `showModalBottomSheet` (loses our 560pt cap + drag handle defaults) |
| `PGEvidenceBadge` | Evidence-level signal-bars indicator | Material `Badge` (different concept — a count/dot indicator) |
| `PGScoreRing` | Score ring visualization | — |
| `VerdictBadge` | Pipeline verdict chip | — |
| `PGShimmerBox` | Skeleton loading surfaces | — |

**Press feedback:** Default to `PGPressable(pressedScale: 0.96)`. Hero
CTAs go to 0.94. Top-chrome icon buttons use 0.92. Subtle launchers (e.g.
search-field-as-button) use 0.99.

**Keyboard focus:** PGPressable now renders a 2px tinted ring on
keyboard / screen-reader focus only (added 2026-05-06). iPad-with-keyboard,
web, and accessibility users get a visible focus indicator; touch-only
sessions never see it.

---

## M3 alignment vs intentional departures

### Aligned with M3 (already done)
- Full `ColorScheme` with the entire surface ladder (`surfaceContainerLowest` → `surfaceContainerHighest`)
- Every component theme set: appBar, card, navigation, input, button, chip, sheet, dialog, snackbar, listTile, switch, progress
- M3 emphasized curve (`Cubic(0.2, 0, 0, 1)`) in `AppMotion.emphasizedCurve`
- `PredictiveBackPageTransitionsBuilder` on Android 14+
- `MediaQuery.maybeDisableAnimationsOf` reduce-motion support
- Text scaler clamp 0.9–1.4 globally (with local overrides where layouts demand)
- Modern alpha API (`withValues(alpha:)`, not deprecated `withOpacity`)

### Intentionally NOT M3 (don't change without discussion)

| Departure | Why |
|---|---|
| Cupertino page transitions on iOS | Native swipe-back gesture; Material slide feels foreign on iPhone |
| `PGFrostedNavBar` instead of M3 `NavigationBar` | Frosted-glass identity is the most distinctive thing on screen |
| `PGPressable` scale-on-press instead of `InkWell` ripple on iOS | Press-scale is the iOS tactile signature; ripple feels Android |
| Severity colors from a fixed palette, not derived from `ColorScheme` | Medical accuracy: severity hex values must be stable across themes |
| No Material You / Dynamic Color | Trust comes from consistent brand identity, not user wallpaper |
| `PGFilterChip` instead of Material `FilterChip` | No checkmark clutter; full-fill animation reads cleaner |

### Open M3 questions (worth experimenting, not decided)

- **`SearchAnchor`** for the home search field instead of "tap → navigate to /search". Could give free in-place suggestions UX.
- **`SegmentedButton`** for any "pick exactly one of N" UI currently using a row of `PGFilterChip`. Communicates single-select more clearly.
- **`MenuAnchor`** for context/dropdown menus.
- **`CarouselView`** (Flutter 3.16+) for product carousels.

---

## Drift signals — what to watch for in code review

1. **`Container + BoxDecoration` for a standalone surface.** Should be a `PGCard` variant.
2. **`InkWell` on iOS.** `PGPressable` is the iOS-native pattern.
3. **Hardcoded hex outside `core/theme/` and `core/constants/`.** The splash gradient is the only documented exception (3 brand variants in [animated_splash_screen.dart](../lib/features/splash/animated_splash_screen.dart)).
4. **`withOpacity(...)`.** Deprecated; use `withValues(alpha: ...)`.
5. **Magic durations** (`Duration(milliseconds: ...)`). Use `AppMotion.fast/medium/slow/emphasized`.
6. **Magic spacing** (`SizedBox(height: 17)`). Use `AppTheme.space*` tokens.
7. **Two `PGCard(highlighted)` on one screen.** Demote one to `plain`.
8. **Using `Severity.caution` (red) when the data is "we don't have enough info."** Use `insufficientData` indigo.

---

## When in doubt — decision cheatsheet

- *Need a tappable surface?* → `PGPressable(child: PGCard(...))`
- *Need a card?* → `PGCard` (pick a variant; respect cardinality)
- *Need a banner?* → `PGSeverityBanner` (pick a tone; reuse, don't ad-hoc)
- *Need a bottom sheet?* → `PGModal.bottomSheet(...)`
- *Need a chip?* → `PGFilterChip` if it's a filter; theme-default `Chip` for static labels
- *Need a button?* → `FilledButton` / `OutlinedButton` / `TextButton` from theme (already styled)
- *Need an input?* → `TextFormField` from theme (already styled), or `PGSearchField` for search
- *Need a colour?* → `Theme.of(context).colorScheme.*` first; `AppTheme.severity*` / `AppTheme.score*` / `AppTheme.evidence*` for medical semantics
- *Need a duration or curve?* → `AppMotion.*`
- *Need to space something?* → `AppTheme.space*`

If none of the above fit, *that's the signal something new belongs in
the design system* — add it to `core/theme/` or `core/widgets/`, then
update this doc.
