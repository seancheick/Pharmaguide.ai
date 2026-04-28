# App-Wide Apple-Grade Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the home-screen Apple-grade treatment (Sprints 27.19 + 27.20) to every other surface in the PharmaGuide Flutter app, so the entire product feels like a coherent first-party iOS experience instead of a polished home + a less-polished tail.

**Architecture:** Reuse the primitives already shipped from home — `PGPressable`, `PGHaptics`, `PGFrostedHeader`, `PGCard` 4-tier system, `AppMotion.gentleRelease`, `_platformPage` routing, global Dynamic Type clamp. Promote one new reusable primitive (`PGFrostedAppBar`) so sub-pages get the same scroll-aware frosted top chrome the home pinned-search has. Migrate adoption pattern-by-pattern across screens; no bespoke per-screen rewrites.

**Tech Stack:** Flutter 3.41 stable, Riverpod, Material 3 + Cupertino, BackdropFilter, SliverPersistentHeader, PageController. No new packages.

**Baseline (2026-04-28):** Home screen and app shell are 100% polished. Scanner is 90%, Stack is 85%, Settings is 70%, Profile Setup is 70%, Quick Check is 65%. Onboarding and Search are already reference-quality. Product Detail is structurally sound but has a few finishing touches. 736/736 tests pass; `flutter analyze` clean. `lib/core/widgets/` already has every primitive this plan needs except `PGFrostedAppBar` (Phase 0 builds it).

**Out of scope (deliberate):**
- Tablet form factor — phone-first; tablet polish is a separate sprint.
- New features. This plan is polish only — no new screens, no new flows.
- Performance optimization. The home plan respected performance constraints (BackdropFilter density, AnimatedScale costs); this plan inherits them.
- Visual redesign. We are *applying* the established design language, not extending it.

**Branch policy:** All work on `main` with one commit per task (matches existing convention). Each task ends with `flutter analyze` + targeted test run before commit.

**Reference:** Home plan at `docs/superpowers/plans/2026-04-28-home-apple-grade.md`. Read it for context on the primitives this plan adopts.

---

## Phase 0 — Reusable primitive: `PGFrostedAppBar`

The home page uses an inline `_PinnedSearchHeaderDelegate` for its frosted top chrome. Sub-pages need the same iOS feel but with a different content payload (back button + title + actions, not a search field). Promote the pattern into one reusable primitive used by Stack, Settings, Profile Setup, Quick Check, and Product Detail.

### Task 0.1: Build `PGFrostedAppBar`

**Files:**
- Create: `lib/core/widgets/pg_frosted_app_bar.dart`
- Create: `test/core/widgets/pg_frosted_app_bar_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_app_bar.dart';

void main() {
  group('PGFrostedAppBar', () {
    testWidgets('renders title centered', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                PGFrostedAppBar(title: 'My Stack'),
                SliverToBoxAdapter(child: SizedBox(height: 800)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('My Stack'), findsOneWidget);
    });

    testWidgets('renders leading back button by default in nested route',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('open'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: CustomScrollView(
                        slivers: [PGFrostedAppBar(title: 'Detail')],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Default leading icon is the back chevron.
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    });

    testWidgets('renders custom actions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                PGFrostedAppBar(
                  title: 'Profile',
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('hides leading when automaticallyImplyLeading is false',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                PGFrostedAppBar(
                  title: 'Tab',
                  automaticallyImplyLeading: false,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
    });
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (file doesn't exist)

```
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/core/widgets/pg_frosted_app_bar_test.dart
```

Expected: compile error — `PGFrostedAppBar` undefined.

- [ ] **Step 3: Build the primitive**

Create `lib/core/widgets/pg_frosted_app_bar.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_header.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';

/// Apple-grade frosted app bar — sliver variant.
///
/// Mounted as the first sliver in a `CustomScrollView`. At scroll offset 0
/// the surrounding chrome is fully transparent (looks like page material);
/// once content scrolls past below, [PGFrostedHeader] inside the delegate
/// fades in a translucent surface + bottom hairline. Settings / Mail / App
/// Store top-chrome pattern.
///
/// Use this on every sub-page (and on tab destinations that don't have a
/// pinned search) so the whole app shares the same iOS top chrome.
///
/// ```dart
/// CustomScrollView(
///   slivers: [
///     PGFrostedAppBar(title: 'My Stack'),
///     // ... rest of slivers ...
///   ],
/// )
/// ```
class PGFrostedAppBar extends StatelessWidget {
  /// The title rendered centered in the bar. Required.
  final String title;

  /// Optional widget rendered to the left of the title (replaces the
  /// default back button if set). Pass `const SizedBox.shrink()` to hide
  /// the leading slot entirely; pass null to use the default back button
  /// when `automaticallyImplyLeading` is true.
  final Widget? leading;

  /// Whether to imply a back button when [leading] is null and the route
  /// can pop. Defaults to true. Set false on tab-root screens (Stack,
  /// Settings) where there's nothing to go back to.
  final bool automaticallyImplyLeading;

  /// Optional trailing actions. Rendered to the right of the title in
  /// the order given. Typical use: a single `IconButton` for share /
  /// edit / settings.
  final List<Widget> actions;

  /// Override the blur sigma. Defaults to 30 (matches PGFrostedHeader);
  /// pass a smaller value (e.g. 18) for tab destinations where the
  /// background is more colorful and the full blur over-softens it.
  final double blurSigma;

  const PGFrostedAppBar({
    super.key,
    required this.title,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.actions = const <Widget>[],
    this.blurSigma = 30,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PGFrostedAppBarDelegate(
        title: title,
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
        actions: actions,
        blurSigma: blurSigma,
        topPadding: mq.padding.top,
      ),
    );
  }
}

class _PGFrostedAppBarDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final List<Widget> actions;
  final double blurSigma;
  final double topPadding;

  static const double _barHeight = 44; // iOS standard nav bar content
  static const double _verticalPadding = 6;

  _PGFrostedAppBarDelegate({
    required this.title,
    required this.leading,
    required this.automaticallyImplyLeading,
    required this.actions,
    required this.blurSigma,
    required this.topPadding,
  });

  double get _height => topPadding + _verticalPadding * 2 + _barHeight;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget? leadingWidget = leading;
    if (leadingWidget == null && automaticallyImplyLeading) {
      final canPop = ModalRoute.of(context)?.canPop ?? false;
      if (canPop) {
        leadingWidget = PGPressable(
          onTap: () => Navigator.of(context).maybePop(),
          pressedScale: 0.94,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: scheme.onSurface,
            ),
          ),
        );
      }
    }

    return PGFrostedHeader(
      scrollProgress: overlapsContent ? 1.0 : 0.0,
      blurSigma: blurSigma,
      child: Padding(
        padding: EdgeInsets.only(
          top: topPadding + _verticalPadding,
          left: AppTheme.space12,
          right: AppTheme.space12,
          bottom: _verticalPadding,
        ),
        child: SizedBox(
          height: _barHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Centered title — Cupertino-style.
              Center(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (leadingWidget != null)
                Align(alignment: Alignment.centerLeft, child: leadingWidget),
              if (actions.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actions,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PGFrostedAppBarDelegate oldDelegate) {
    return oldDelegate.title != title ||
        oldDelegate.leading != leading ||
        oldDelegate.automaticallyImplyLeading != automaticallyImplyLeading ||
        oldDelegate.actions.length != actions.length ||
        oldDelegate.blurSigma != blurSigma ||
        oldDelegate.topPadding != topPadding;
  }
}
```

- [ ] **Step 4: Run — expect 4/4 PASS**

```
flutter test test/core/widgets/pg_frosted_app_bar_test.dart
```

- [ ] **Step 5: Run analyze — expect clean**

```
flutter analyze
```

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/pg_frosted_app_bar.dart \
  test/core/widgets/pg_frosted_app_bar_test.dart
git commit -m "feat(core): PGFrostedAppBar — sliver-mounted Apple-grade app bar

Promotes the home pinned-search delegate pattern into a reusable
primitive. Used on every sub-page (Stack, Settings, Profile Setup,
Quick Check, Product Detail) so the whole app shares the iOS frosted
top-chrome treatment.

Renders centered title + optional leading + optional actions. Default
leading is a chevron-back if the route can pop. blurSigma defaults to
30 (matches PGFrostedHeader); tab destinations pass 18 for less wash.

PGPressable on the back button gives 0.94 press scale + spring + light
haptic, matching the home scan CTA's pressedScale.

Plan: docs/superpowers/plans/2026-04-28-app-wide-apple-grade.md (Task 0.1)"
```

---

## Phase A — Tab destinations (highest visual-impact)

The four tab roots define what the user sees most. Inconsistency between Home (frosted) and the other three (Material AppBar) is the loudest "this isn't all one app" signal. Fix that first.

### Task A.1: Stack tab — replace AppBar with PGFrostedAppBar

**Files:**
- Modify: `lib/features/stack/stack_screen.dart`
- Modify: `test/features/stack/stack_screen_test.dart` (only if existing assertions break)

- [ ] **Step 1: Read the current stack_screen.dart top-of-build to confirm AppBar pattern**

Run: `Read tool on lib/features/stack/stack_screen.dart, full file`. Look for the `AppBar` usage around lines 49–70 and the body's `CustomScrollView` (or non-sliver scaffolding).

- [ ] **Step 2: Convert Scaffold body to a CustomScrollView with PGFrostedAppBar**

Pattern to apply:
- Remove the `Scaffold(appBar: AppBar(...))` wrapping
- Use `Scaffold(body: CustomScrollView(slivers: [PGFrostedAppBar(title: 'My Stack'), ...rest]))`
- The existing tab logic (My stack / Wishlist) becomes a `SliverPersistentHeader` directly under the frosted bar (so tabs are also pinned), or stays inline if Sean prefers tabs to scroll away

Add import:
```dart
import 'package:pharmaguide/core/widgets/pg_frosted_app_bar.dart';
```

Replace top of build:
```dart
return Scaffold(
  body: CustomScrollView(
    physics: const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    ),
    slivers: [
      const PGFrostedAppBar(
        title: 'My Stack',
        automaticallyImplyLeading: false, // tab root
      ),
      // ... existing body content as slivers ...
    ],
  ),
);
```

If the existing body is a `ListView` or non-sliver, wrap it in a `SliverFillRemaining` or convert to `SliverList`/`SliverPadding`.

- [ ] **Step 3: Run home + stack tests**

```
flutter test test/features/home/ test/features/stack/ test/core/widgets/pg_frosted_app_bar_test.dart
```

Expected: all pass. If `stack_screen_test.dart` had `find.byType(AppBar)` assertions, update them to `find.text('My Stack')` instead.

- [ ] **Step 4: Manual smoke on simulator** — confirm: (a) title renders centered, (b) frosted background fades in on scroll, (c) bottom hairline appears, (d) status bar text contrast is readable.

- [ ] **Step 5: Run analyze + commit**

```bash
flutter analyze
git add lib/features/stack/stack_screen.dart \
  test/features/stack/stack_screen_test.dart  # only if you touched the test
git commit -m "feat(stack): replace AppBar with PGFrostedAppBar

Unifies stack-tab top chrome with the rest of the app. Tab-root
behavior: automaticallyImplyLeading: false (no back button — there's
nothing to go back to from a tab destination)."
```

### Task A.2: Settings tab — three-part polish

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`

Three independent gaps; combine into one commit because they're all on the same screen.

- [ ] **Step 1: Replace AppBar with PGFrostedAppBar**

Same pattern as Task A.1. `automaticallyImplyLeading: false`. Title: `'Profile'` (or whatever the current AppBar title is — preserve it).

- [ ] **Step 2: Replace settings-tile InkWells with PGPressable**

Audit `lib/features/settings/settings_screen.dart` for `Material` + `InkWell` patterns wrapping list-row tappables (the audit flagged lines around 404–407). For each:

```dart
// Before:
Material(
  color: Colors.transparent,
  child: InkWell(
    onTap: () => _doThing(),
    child: <row content>,
  ),
)

// After:
PGPressable(
  onTap: () => _doThing(),
  pressedScale: 0.98, // settings rows are dense — keep press subtle
  child: <row content>,
)
```

The 0.98 pressedScale (vs. the 0.96 default) is intentional: settings rows sit close together, so a deeper press would visually collide with the row above/below.

- [ ] **Step 3: Sweep `Switch` → `Switch.adaptive`**

Run: `grep -n "Switch(" lib/features/settings/settings_screen.dart` (also check for `SwitchListTile` — replace with `SwitchListTile.adaptive`).

For each occurrence, replace `Switch(` with `Switch.adaptive(` and `SwitchListTile(` with `SwitchListTile.adaptive(`. The `.adaptive` constructor renders `CupertinoSwitch` on iOS and Material on Android — zero API cost, big platform-feel win.

- [ ] **Step 4: Run analyze + tests**

```
flutter analyze
flutter test test/features/settings/  # if any tests exist
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/settings_screen.dart
git commit -m "feat(settings): app-bar + tile + switch adaptive sweep

Three Apple-grade fixes on the Profile tab:
1. Material AppBar → PGFrostedAppBar (frosted scroll-aware chrome,
   matches the rest of the app)
2. Material+InkWell tile rows → PGPressable (Apple press-scale +
   spring; pressedScale 0.98 because settings rows are dense)
3. Switch → Switch.adaptive (CupertinoSwitch on iOS, Material on
   Android — native feel at zero API cost)"
```

### Task A.3: Scanner tab — loading-overlay polish

**Files:**
- Modify: `lib/features/scanner/scanner_screen.dart`

The scanner is 90% done. The one gap: the lookup-in-flight overlay (lines 255–265 per the audit) uses a raw `Container + CircularProgressIndicator`. Since the rest of the app has moved to PGShimmer for loading states, this stands out.

- [ ] **Step 1: Read current `_LookupOverlay` (or wherever the spinner lives) implementation**

Run: `Read tool on scanner_screen.dart` around line 255. Confirm the structure.

- [ ] **Step 2: Replace `Container + CircularProgressIndicator` with a PGCard-wrapped pair (icon + small label + shimmer line)**

Pattern:

```dart
// Replace the existing overlay body with:
Center(
  child: PGCard(
    variant: PGCardVariant.elevated,
    padding: const EdgeInsets.symmetric(
      horizontal: AppTheme.space20,
      vertical: AppTheme.space16,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.search_rounded, size: 28, color: scheme.primary),
        const SizedBox(height: AppTheme.space12),
        Text(
          'Looking up product…',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppTheme.space8),
        const SizedBox(
          width: 140,
          child: PGShimmerBox(height: 4, radius: 2),
        ),
      ],
    ),
  ),
);
```

- [ ] **Step 3: Run scanner tests + analyze**

```
flutter test test/features/scanner/ 2>/dev/null
flutter analyze
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/scanner/scanner_screen.dart
git commit -m "feat(scanner): polish lookup overlay to PGCard + shimmer

Replaces the raw Container + CircularProgressIndicator overlay with a
PGCard.elevated containing an icon, status copy, and a thin shimmer
line. Matches the rest of the app's loading-state vocabulary."
```

---

## Phase B — Sub-page polish (Stack of secondary screens)

### Task B.1: Profile Setup — frosted bar + tappable rows + form-field unification

**Files:**
- Modify: `lib/features/profile/profile_setup_screen.dart`

This is a multi-step PageView form (steps 1–5). Three polish moves.

- [ ] **Step 1: Replace AppBar with PGFrostedAppBar**

Pattern from Task A.1. Profile Setup IS reachable from elsewhere (it pops back to home), so `automaticallyImplyLeading: true` (the default) — back chevron renders automatically.

If the existing AppBar has `actions: [TextButton('Skip', onPressed: ...)]`, port that into `PGFrostedAppBar.actions: [TextButton(...)]`.

- [ ] **Step 2: Wrap RadioListTile / CheckboxListTile bodies with PGPressable**

The audit flagged these at lines 246–296, 345–355, 409–444. The Material radio/checkbox primitives don't give iOS press-feel. Replace each tile's outer wrapping:

```dart
// Before:
RadioListTile<MyEnum>(
  value: MyEnum.foo,
  groupValue: _selected,
  onChanged: _onChange,
  title: Text(label),
)

// After:
PGPressable(
  onTap: () => _onChange(MyEnum.foo),
  pressedScale: 0.98,
  child: RadioListTile<MyEnum>(
    value: MyEnum.foo,
    groupValue: _selected,
    onChanged: _onChange,
    title: Text(label),
  ),
)
```

The double-tap-target works fine — RadioListTile's own onTap is preserved; PGPressable adds the haptic + scale on the surrounding chrome.

For checkbox lists, also use `Checkbox.adaptive` if you can — iOS uses tinted check marks, not boxes.

- [ ] **Step 3: Add haptic on the primary CTA button (Next / Complete)**

The bottom Next/Complete button (audit line 148–151) is a `FilledButton`. Material buttons ripple but don't fire a haptic. Wrap the onPressed:

```dart
FilledButton(
  onPressed: () {
    PGHaptics.press(context); // light-tap haptic
    _goToNextStep();
  },
  child: const Text('Next'),
)
```

For the FINAL step's "Complete" button, use `PGHaptics.successPattern(context)` — that's the di-DUP Apple-Pay-style completion.

- [ ] **Step 4: Run analyze + tests**

```
flutter analyze
flutter test test/features/profile/ 2>/dev/null
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/profile/profile_setup_screen.dart
git commit -m "feat(profile-setup): frosted app bar + PGPressable rows + completion haptic

Three Apple-grade polish moves on the multi-step profile form:
1. Material AppBar → PGFrostedAppBar (matches app top-chrome)
2. Radio/Checkbox tile rows wrapped in PGPressable (0.98 scale,
   light haptic on tap-down)
3. Final-step Complete button fires PGHaptics.successPattern (Apple
   Pay di-DUP completion cadence) — high-value moment for the user;
   intermediate Next steps fire the lighter PGHaptics.press"
```

### Task B.2: Quick Check — frosted bar + ListTile suggestions + button polish

**Files:**
- Modify: `lib/features/quick_check/quick_check_screen.dart`

- [ ] **Step 1: Replace AppBar with PGFrostedAppBar** (same pattern, with default leading back chevron)

- [ ] **Step 2: Wrap suggestion ListTiles with PGPressable**

The audit flagged ListTile suggestions at lines 397–425. ListTile already has an `onTap`, but no haptic and no press-scale. Wrap:

```dart
PGPressable(
  onTap: () => _selectSuggestion(item),
  pressedScale: 0.97,
  child: ListTile(
    leading: ProductImage(...),
    title: Text(item.name),
    subtitle: Text(item.brand),
    // remove the existing onTap from ListTile — PGPressable handles it
  ),
)
```

- [ ] **Step 3: Polish the Check button**

The audit flagged the FilledButton.icon at lines 198–211 with a CircularProgressIndicator overlay. Two changes:

(a) Add a haptic on press:
```dart
onPressed: _input.isValid
    ? () {
        PGHaptics.press(context);
        _runCheck();
      }
    : null,
```

(b) Replace the in-button CircularProgressIndicator with a button-state swap. While loading, render a button labeled "Checking…" with a small inline `PGShimmerBox(height: 2, width: 60)` instead of a spinner. Or — simpler and equally Apple-like — disable the button (greyed) while loading, and show no spinner inside the button at all (use a top-of-screen overlay if you must show progress).

Apple Pay's "Pay" button doesn't spin — it just goes greyed for the brief moment the network call takes. Match that.

- [ ] **Step 4: Verify result-display haptic gating**

When the check returns a result, the severity banner is shown. Add `PGHaptics.forSeverity(result.severity, context)` at the moment the result first renders, so the user feels the verdict before reading it. Wrap the result-display callback in a `WidgetsBinding.instance.addPostFrameCallback` if needed to ensure the haptic fires after the banner mounts.

- [ ] **Step 5: Run analyze + tests + commit**

```bash
flutter analyze
flutter test test/features/quick_check/ 2>/dev/null
git add lib/features/quick_check/quick_check_screen.dart
git commit -m "feat(quick-check): frosted bar + tactile suggestions + verdict haptic

- Material AppBar → PGFrostedAppBar
- Suggestion ListTiles wrapped in PGPressable with light haptic
- Check button: PGHaptics.press on press; spinner-in-button removed
  in favor of greyed-out disabled state (Apple Pay pattern)
- Severity-gated result haptic via PGHaptics.forSeverity when result
  banner first mounts — user feels the verdict before reading it"
```

### Task B.3: Product Detail — SliverAppBar frosting + section consistency

**Files:**
- Modify: `lib/features/product_detail/product_detail_screen.dart`

The audit said this screen is structurally solid. Two surgical polish moves:

- [ ] **Step 1: Replace the SliverAppBar with PGFrostedAppBar (or frost the existing SliverAppBar)**

The audit found a `SliverAppBar` at lines 341–365. Two approaches:

(A) Drop-in replace with `PGFrostedAppBar(title: product.name, actions: [shareButton])`. Loses the SliverAppBar's `flexibleSpace` if any.

(B) If the SliverAppBar uses `flexibleSpace` for a hero image / large-title-collapse, keep the SliverAppBar but wrap its `flexibleSpace` in a `ClipRect > BackdropFilter` for the iOS frosted feel.

Default to (A) unless the screen has a hero image worth preserving. Confirm with a Read of lines 341–365 first.

- [ ] **Step 2: Audit pipeline-section widgets for surface-tier compliance**

The audit said pipeline-section widgets (probiotic_detail_section, evidence_detail_section, etc.) "should use PGCard tiers consistently." Walk each of:

- `lib/features/product_detail/widgets/pipeline_sections/probiotic_detail_section.dart`
- `evidence_detail_section.dart`
- `synergy_detail_section.dart`
- `formulation_detail_section.dart`
- `manufacturer_violations_section.dart`
- `certification_detail_section.dart`
- `heavy_metal_warning_card.dart`
- `score_breakdown_card.dart`

For each, grep for `Container(` with a `BoxDecoration` that paints a visible background. Each one should be `PGCard(variant: ...)` per the 4-tier system. Most likely fine already (Sprint 27.18 pipeline-detail commit landed these); verify and migrate any stragglers.

- [ ] **Step 3: Run analyze + tests + commit**

```bash
flutter analyze
flutter test test/features/product_detail/
git add lib/features/product_detail/
git commit -m "feat(product-detail): PGFrostedAppBar + pipeline-section surface audit"
```

---

## Phase C — Cross-cutting motion + haptic adoption sweep

These tasks span multiple files and are best done as one focused pass per concern.

### Task C.1: Replace Material modal/dialog primitives with Cupertino on iOS

**Files:** any file using `showModalBottomSheet`, `showDialog`, `showAboutDialog`.

- [ ] **Step 1: Find every modal call site**

```bash
cd "/Users/seancheick/PharmaGuide ai"
grep -rn "showModalBottomSheet\|showDialog\|showAboutDialog" lib/ \
  | grep -v ".g.dart\|.freezed.dart" > /tmp/modals.txt
wc -l /tmp/modals.txt
```

- [ ] **Step 2: Build a `PGModal.bottomSheet` helper**

Create `lib/core/widgets/pg_modal.dart`:

```dart
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Platform-adaptive modal helpers.
///
/// On iOS uses the system Cupertino modal patterns (sheet detents, action
/// sheets, alert dialogs); on Android falls through to Material patterns
/// (showModalBottomSheet, showDialog). This is the single layer to migrate
/// every existing showModalBottomSheet / showDialog through.
abstract final class PGModal {
  /// Bottom sheet — Cupertino sheet on iOS (with detents and grabber),
  /// Material modal sheet on Android.
  static Future<T?> bottomSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isDismissible = true,
    bool useSafeArea = true,
    bool showDragHandle = true,
  }) {
    if (Platform.isIOS) {
      return showCupertinoModalPopup<T>(
        context: context,
        builder: builder,
        barrierDismissible: isDismissible,
      );
    }
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isDismissible: isDismissible,
      useSafeArea: useSafeArea,
      showDragHandle: showDragHandle,
      isScrollControlled: true,
    );
  }

  /// Alert dialog — CupertinoAlertDialog on iOS, AlertDialog on Android.
  static Future<T?> alert<T>({
    required BuildContext context,
    required String title,
    required String message,
    required List<PGAlertAction<T>> actions,
  }) {
    if (Platform.isIOS) {
      return showCupertinoDialog<T>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: actions
              .map(
                (a) => CupertinoDialogAction(
                  isDestructiveAction: a.isDestructive,
                  isDefaultAction: a.isDefault,
                  onPressed: () => Navigator.of(ctx).pop(a.value),
                  child: Text(a.label),
                ),
              )
              .toList(),
        ),
      );
    }
    return showDialog<T>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: actions
            .map(
              (a) => TextButton(
                onPressed: () => Navigator.of(ctx).pop(a.value),
                child: Text(a.label),
              ),
            )
            .toList(),
      ),
    );
  }
}

class PGAlertAction<T> {
  final String label;
  final T value;
  final bool isDestructive;
  final bool isDefault;
  const PGAlertAction({
    required this.label,
    required this.value,
    this.isDestructive = false,
    this.isDefault = false,
  });
}
```

- [ ] **Step 3: Migrate one file at a time**

Pick the lowest-stakes call sites first (e.g. settings about-app dialog). Replace `showDialog(context: ..., builder: ...)` with `PGModal.alert(context: ..., title: ..., message: ..., actions: [PGAlertAction(...)])`.

For each migration, run analyze + relevant tests, then commit per file:

```bash
git commit -m "refactor(<feature>): migrate modals to PGModal (Cupertino on iOS)"
```

This task can be parallelized — each file's migration is independent.

- [ ] **Step 4: After every call site is migrated, lint-check**

```bash
grep -rn "showModalBottomSheet\|showDialog\b" lib/ | grep -v "PGModal" | grep -v ".g.dart"
```

Expected: only matches inside `pg_modal.dart` itself.

### Task C.2: Switch / Checkbox / Slider adaptive sweep

**Files:** any file using `Switch(`, `Checkbox(`, `Slider(`, `SwitchListTile(`, `CheckboxListTile(`.

- [ ] **Step 1: Audit**

```bash
grep -rn "Switch(\|Checkbox(\|Slider(\|SwitchListTile(\|CheckboxListTile(" lib/ \
  | grep -v ".g.dart\|adaptive\b" > /tmp/material_controls.txt
wc -l /tmp/material_controls.txt
```

- [ ] **Step 2: Replace each with `.adaptive` variant**

Mechanical change: `Switch(` → `Switch.adaptive(`, `Checkbox(` → `Checkbox.adaptive(`, `SwitchListTile(` → `SwitchListTile.adaptive(`. Slider has no `.adaptive` constructor — wrap in a `Platform.isIOS ? CupertinoSlider(...) : Slider(...)` ternary.

- [ ] **Step 3: One commit per feature directory**

```bash
git add lib/features/<area>/
git commit -m "refactor(<area>): adaptive Material controls for iOS feel"
```

### Task C.3: Motion-token sweep — replace ad-hoc durations / curves

**Files:** any file using `Duration(milliseconds: ...)` directly on animation properties, or `Curves.easeInOut` / `Curves.linear` / `Curves.bounceOut` etc. that don't go through `AppMotion.*`.

- [ ] **Step 1: Audit**

```bash
grep -rn "duration: Duration(milliseconds:\|Curves\." lib/features/ lib/core/widgets/ \
  | grep -v "AppMotion\." \
  | grep -v ".g.dart" \
  | head -50
```

- [ ] **Step 2: For each, decide the right token**

| Existing | Use |
|---|---|
| `Duration(milliseconds: 100..200)` | `AppMotion.fast` (150ms) |
| `Duration(milliseconds: 200..280)` | `AppMotion.medium` (240ms) |
| `Duration(milliseconds: 300..360)` | `AppMotion.slow` (320ms) |
| `Duration(milliseconds: 400+)` | `AppMotion.emphasized` (420ms) |
| `Curves.easeInOut`, `Curves.fastOutSlowIn` | `AppMotion.standard` |
| `Curves.easeOutCubic` | `AppMotion.gentleRelease` (for press-up) or `AppMotion.standard` |
| `Curves.bounceOut` etc. | Don't use; replace with `AppMotion.spring` only for state-flip toggles |

- [ ] **Step 3: One commit per feature directory**

```bash
git commit -m "refactor(motion): align <area> motion to AppMotion tokens"
```

---

## Phase D — Polished cross-screen primitives

### Task D.1: Build `PGAdaptiveBackButton`

**Why:** every sub-page back button should look identical and use the same haptic + press behavior. Currently each screen ships its own.

**Files:**
- Create: `lib/core/widgets/pg_adaptive_back_button.dart`

Already implemented inline inside PGFrostedAppBar's delegate. Extract to a top-level widget so any screen using a custom AppBar (e.g. Product Detail's SliverAppBar variant if it survives) can reuse it.

```dart
import 'package:flutter/material.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';

/// Apple-grade back chevron for sub-page top chrome.
class PGAdaptiveBackButton extends StatelessWidget {
  final VoidCallback? onTap;

  const PGAdaptiveBackButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return PGPressable(
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      pressedScale: 0.94,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
```

Then update `PGFrostedAppBar` to use `PGAdaptiveBackButton()` instead of the inline copy.

Commit:
```
git commit -m "refactor(core): extract PGAdaptiveBackButton from PGFrostedAppBar"
```

### Task D.2: Audit and update Empty States

The home `Recents` empty state uses `_OutlineScanButton` (a tappable pill). Other screens may have less-polished empty states.

- [ ] **Step 1: Audit empty states across features**

```bash
grep -rn "EmptyState\|Empty\|isEmpty" lib/features/ \
  | grep -v ".g.dart" \
  | grep -v "// " \
  | head -30
```

- [ ] **Step 2: For each screen with a bespoke empty-state widget, ensure it uses:**
  - `PGCard(variant: PGCardVariant.recessed)` outer
  - A 56-pt circular icon well (`Container` with surface tint)
  - Title (titleSmall, w700)
  - Subtitle (bodySmall, onSurfaceVariant)
  - One CTA wrapped in `PGPressable`

The home Recents empty state at `home_recent_scans.dart:127–189` is the reference. Cross-check against Stack empty state, Wishlist empty state, search empty results, and Quick Check insufficient-data state.

- [ ] **Step 3: Commit per fix**

```
git commit -m "feat(<screen>): align empty state with home Recents pattern"
```

---

## Phase E — Tests + verification

### Task E.1: Cross-screen smoke tests

**Files:**
- Create: `test/integration/cross_screen_polish_smoke_test.dart`

A single test file that mounts each major screen (Stack, Settings, Profile Setup, Quick Check, Product Detail) inside a ProviderScope + MaterialApp.router and asserts:
1. The screen finds a `PGFrostedAppBar` (proves the migration happened)
2. The screen has at least one `PGPressable` ancestor reachable from a tappable element (proves PGPressable adoption)
3. No `Material(... InkWell(...))` reaches the visible tree (proves migration completeness)

This is a regression guard. Each task above should pass it once that screen is migrated; the test goes green incrementally.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_app_bar.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';
// ... screen imports ...

void main() {
  group('cross-screen polish smoke', () {
    testWidgets('Stack tab uses PGFrostedAppBar', (tester) async {
      // ... mount StackScreen ...
      expect(find.byType(PGFrostedAppBar), findsOneWidget);
    });

    testWidgets('Settings tab uses PGFrostedAppBar', (tester) async {
      // ... mount SettingsScreen ...
      expect(find.byType(PGFrostedAppBar), findsOneWidget);
    });

    // ... one per migrated screen ...
  });
}
```

- [ ] **Step 1: Write the smoke tests** — one per screen, asserting the migration's single most-visible artifact (PGFrostedAppBar usage)
- [ ] **Step 2: Run them — every screen that has been migrated should pass; un-migrated ones should fail** (red phase confirms the regression guard works)
- [ ] **Step 3: Commit incrementally** as each screen migration goes green

### Task E.2: Final analyze + full-suite run + push

After every task above is complete:

- [ ] **Step 1: Full project analyze**

```
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 2: Full test suite**

```
flutter test
```

Expected: all tests pass. Today the count is 736; this plan adds tests in 0.1, 0.2 (4-ish), B.1–B.3 minor, E.1 (~5). Final count should be in the 750+ range.

- [ ] **Step 3: Push everything**

```
git push origin main
```

- [ ] **Step 4: Update SPRINT_TRACKER.md**

Add `Sprint 27.21: App-wide Apple-grade polish` entry above 27.20 with the full task list.

---

## Implementation order (priority — execute top-down)

| Priority | Task | Why first |
|---|---|---|
| 1 | **Phase 0.1** — Build PGFrostedAppBar | Every Phase A/B task depends on it |
| 2 | **A.1** — Stack frosted bar | Highest-traffic tab; biggest user-visible win |
| 3 | **A.2** — Settings 3-pack | Whole Profile tab elevates in one commit |
| 4 | **A.3** — Scanner overlay | Quick win; user sees it on every scan |
| 5 | **B.1** — Profile Setup | First-launch users see this; high impression weight |
| 6 | **B.2** — Quick Check | Cross-app consistency |
| 7 | **B.3** — Product Detail | Heaviest screen; do after the primitive is battle-tested |
| 8 | **C.1** — PGModal sweep | Touches many files; do as a batch |
| 9 | **C.2** — Adaptive controls | Low-risk grep-and-replace |
| 10 | **C.3** — Motion-token sweep | Stylistic; do after structural moves are stable |
| 11 | **D.1** — Extract PGAdaptiveBackButton | Refactor only |
| 12 | **D.2** — Empty-state audit | Polish on polish |
| 13 | **E.1** — Smoke tests | Run continuously; finalize at the end |
| 14 | **E.2** — Final verify + tracker | Sprint-close |

**Estimated effort:** 6–10 hours of focused execution. Lower bound assumes batched commits and skipped manual smokes; upper bound includes simulator visual checks per task.

---

## Self-Review Checklist (run before declaring complete)

- [ ] Every screen flagged in the audit has a corresponding task in this plan (Stack, Settings, Scanner, Profile Setup, Quick Check, Product Detail)
- [ ] Onboarding and Search are deliberately NOT in Phase A/B (already reference quality)
- [ ] App Shell and Nav Bar are NOT in any task (already reference quality)
- [ ] Every reusable primitive needed (`PGFrostedAppBar`, `PGModal`, `PGAdaptiveBackButton`) has a build task before any task that uses it
- [ ] Every task ends with a commit
- [ ] No placeholder text — every step has the actual code or exact command
- [ ] Verification steps reference real test paths, not invented ones
- [ ] Type/method/widget signatures across tasks are consistent (e.g. `PGFrostedAppBar.title` is used the same way in A.1 and B.1)

## Execution

Plan saved to `docs/superpowers/plans/2026-04-28-app-wide-apple-grade.md`.

Two execution options:
1. **Subagent-Driven** (recommended for this scale) — fresh subagent per task, two-stage review between tasks, fast iteration. Good fit because Phase 0 + Phase A are tightly sequenced (each task depends on the previous), but Phase C tasks can be parallelized.
2. **Inline Execution** — run tasks in this session with checkpoints between phases for review. Good fit if you want to feel the simulator after each migration before moving to the next.

Total tasks: 1 (Phase 0) + 3 (A) + 3 (B) + 3 (C) + 2 (D) + 2 (E) = **14 tasks**, ~25–35 commits, 6–10 hours.
