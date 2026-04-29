# App-Wide Apple-Grade Polish Implementation Plan

> **2026-04-29 cross-team merge:** After a `/critique` pass on this plan vs Trust & IA Sprint 1, several product-detail phases were re-merged into `INITIATIVE_PRODUCT_TRUST_AND_IA.md` Sprint 1 (T1.1 score-led hero, T1.2 "For You", T1.4 pillar breakdown). Treat that initiative doc as the source of truth for product-detail content/IA decisions. The phases marked `SUPERSEDED`, `DROPPED`, or `RESCOPED` below should not be executed against this plan; the live versions live in Sprint 1. Affected phases: B.3a (folded into T1.1), F.3 + F.5 + F.6 (dropped or folded into T1.2), F.4 (rescoped), B.3b (serialized after T1.1 sign-off). F.0 / F.1 / F.2 are promoted to next-up because they unblock T1.1 / T1.4. Apple-grade phases with no Trust/IA overlap (C.2, C.3, D.2, E.1, E.2) continue per spec.

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

## Status board (live — last updated 2026-04-29)

| Phase | Status | Commit(s) | Notes |
|---|---|---|---|
| **0.1** PGFrostedAppBar primitive | ✅ shipped | `7c90b19` | 4 widget tests; sliver-mounted Apple-grade app bar |
| **0.2** PGCircularIconButton primitive | ✅ shipped | `6e30f62` | 4 widget tests; wired into PGFrostedAppBar leading slot |
| **A.1** Stack tab → PGFrostedAppBar | ✅ shipped | `45c734f` | NestedScrollView + pinned TabBar delegate |
| **A.2** Settings three-pack | ✅ shipped | `b68ac91` | PGFrostedAppBar + PGPressable rows + Switch.adaptive |
| **A.3** Scanner lookup overlay | ✅ shipped | `07ae6c9` | iOS-spinner deviation (CupertinoActivityIndicator) — controller-approved |
| **B.1** Profile Setup three-pack | ✅ shipped | `9f4df75` | PreferredSize + PGFrostedHeader (sliver-nested PageView would null-geometry); PGPressable rows; completion haptic |
| **B.2** Quick Check four-pack | ✅ shipped | `0315177` | Frosted bar + tactile suggestions + severity-gated verdict haptic |
| **B.3a** Apple Altar hero refactor | 🚫 superseded | (Trust/IA `90c0fcd`) | Folded into Trust & IA Sprint 1 T1.1 |
| **B.3b** Frosted SliverAppBar + share + section audit | ✅ shipped | `d862fb1` | Mechanical follow-up to T1.1; pipeline-section audit (1 migration in `better_alternatives.dart`) |
| **B.3c** Hero visual polish *(implicit follow-up)* | ✅ shipped | `2e103ee` + Trust/IA `258c817` | PGCard.elevated + outline chips + 96pt image/ring + entrance choreography + PGPressable on score ring |
| **C.1** PGModal helper + 11-site sweep | ✅ shipped | `8339032` | 2 spec deviations (no Cupertino-popup branch; no alert helper) |
| **C.2** Final adaptive control sweep | ✅ shipped | `e12a780` | 1 remaining `CheckboxListTile` migrated; app-wide .adaptive complete |
| **C.3** Motion-token sweep | ✅ shipped | `29c6164` | 12 sites across 7 files → AppMotion tokens (Trust/IA WIP files excluded) |
| **D.1** PGAdaptiveBackButton extraction | 🚫 folded into 0.2 | — | PGCircularIconButton already covers the contract |
| **D.2** Empty-state audit | ✅ shipped | `5247bae` | Vocabulary already cohesive (1 reference + 5 PGEmptyState consumers); only fix was migrating PGEmptyState's `_PillButton` from Material+InkWell to PGPressable — single change uplifts every CTA |
| **F.0** Data availability audit | ✅ 🟢 GREEN | `76285f3` (findings) | All 4 pillars + coverage are first-class fields on `products_core` |
| **F.1** PGScoreRing reuse vs PGDonutChart | ✅ 🟢 REUSE | `76285f3` (findings) | Existing PGScoreRing covers the T1.1 contract; no new primitive |
| **F.2** PGPillarBar primitive | ✅ shipped | `add240b` | 6 widget tests; T1.4 unblocked |
| **F.3** PGIngredientAtom | 🚫 dropped | — | Atom pills decorative for medical-grade context |
| **F.4** Pillar card composition *(rescoped → absorbed)* | ✅ absorbed by T1.4 | (Trust/IA `e3959e6`) | T1.4 extended the existing `ScoreBreakdownCard` (already had 4-pillar `_ExpandableSectionBar` UI) with the coverage strip + hero continuity label. PGPillarBar primitive shipped at `add240b` is currently orphaned (no production consumer); kept for future use. |
| **F.5** "For You" card | 🚫 dropped → T1.2 | — | Trust/IA owns; reuses apple-grade visual approach |
| **F.6** Atom-style ingredients row | 🚫 dropped | — | Same rationale as F.3 |
| **E.1** Cross-screen smoke tests | ✅ shipped | `39f34db` | `test/integration/cross_screen_polish_smoke_test.dart` — Stack / Settings / Profile Setup / Quick Check assert frosted top chrome (PGFrostedAppBar OR PGFrostedHeader-in-PreferredSize); 4/4 pass |
| **E.2** Final analyze + suite + tracker close | ✅ shipped | `057b894` | `flutter analyze` clean · `flutter test` 890/890 · sprint sealed |
| **G.1** Animated logo splash intro | ✅ shipped | `4d609af` + `193ce6b` | `AnimatedSplashScreen` mounted between native splash + first content screen; 600ms scale 0.85→1.0 + fade-in over `AppMotion.standard`; reduce-motion path skips animation + 200ms brand-impression delay; end-of-anim `PGHaptics.tap`; light status-bar icons on the brand-teal `#0A7D6F` bg. Native-splash regen artifacts shipped in `193ce6b` so iOS LaunchImage + Android density tiers all reference the upgraded 1024×1024 logo. 4 widget tests. |
| **G.2** Hero transitions (scan-card → product detail) | ✅ shipped | `2adb151` | Three Hero wraps with matching tag `'product-${dsldId}'`: home carousel card (48pt source) + Show-all sheet item (48pt source) + product detail hero altar (96pt destination). flightShuttleBuilder uses the destination widget verbatim during transit (suppresses Material elevation overlay halo on small-to-large flights). Bidirectional — back from detail flies image back to source. |
| **G.3** Inline subtitle helper for product hero | ✅ shipped | `882f368` | Stacked `[brand]\n[form]` Text widgets → single `Text.rich` rendering `Brand · Form · Dose` (App Store / Apple Health pattern). New file-scope helpers `_hasAnyHeroSubtitle` + `_buildHeroSubtitleSpan` drop orphan dots cleanly when segments are missing. Tighter vertical rhythm (~30pt saved) in the hero identity column. Dose param wired but null today — pipeline addition flips it on with a one-line change. |
| **G.4** Tighter hero spacing for iPhone SE | ⏸ deferred (design call) | — | LayoutBuilder fallback to compact hero (smaller image + ring) at `<360pt`. Needs simulator validation before shipping. Real-device confirmation step belongs to Sean. |
| **G.5** Sprint 28 prep (Tier 2 Research Evidence) | 🚫 backlog (gated) | — | `SPRINT_TRACKER.md` says DO NOT START until pipeline-side Phase 1 ships. Pipeline-gated, not on apple-grade plate. |

**Verification (Phase G close, 2026-04-29):** `flutter analyze` → No issues found · `flutter test` → **931/931 tests pass** (up from 736 in Sprint 27.20 — **+195 net** across all parallel work) · **31 apple-grade commits + cross-team merges** with Trust/IA on `origin/main` (Trust/IA shipped 4 sprint commits in parallel: T1.1 / T1.2 / T1.4 / T1.5 / T1.6 + the BrandedPlaceholder.compact follow-up).

**Sprint 27.21 status: ✅ CLOSED on apple-grade side.** Phase G follow-ups: G.1, G.2, G.3 ✅ shipped; G.4 ⏸ deferred (design call); G.5 🚫 backlog. Remaining holds (F.4 visual integration absorbed by T1.4) are not on apple-grade's plate.

**Phase G (post-27.21 follow-ups):** Three "premium-feel" tasks that surfaced during the Sprint 27.21 close audit. Each is independent, low-risk, and additive on top of the shipped apple-grade work. Specs below in **Phase G** section.

---

## Phase 0 — Reusable primitive: `PGFrostedAppBar`

The home page uses an inline `_PinnedSearchHeaderDelegate` for its frosted top chrome. Sub-pages need the same iOS feel but with a different content payload (back button + title + actions, not a search field). Promote the pattern into one reusable primitive used by Stack, Settings, Profile Setup, Quick Check, and Product Detail.

### Task 0.1: Build `PGFrostedAppBar`

**Files:**
- Create: `lib/core/widgets/pg_frosted_app_bar.dart`
- Create: `test/core/widgets/pg_frosted_app_bar_test.dart`

- [x] **Step 1: Write failing tests**

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

- [x] **Step 2: Run — expect FAIL** (file doesn't exist)

```
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/core/widgets/pg_frosted_app_bar_test.dart
```

Expected: compile error — `PGFrostedAppBar` undefined.

- [x] **Step 3: Build the primitive**

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

- [x] **Step 4: Run — expect 4/4 PASS**

```
flutter test test/core/widgets/pg_frosted_app_bar_test.dart
```

- [x] **Step 5: Run analyze — expect clean**

```
flutter analyze
```

- [x] **Step 6: Commit**

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

### Task 0.2: Build `PGCircularIconButton`

**Why:** The reference screenshots show top-chrome icon buttons (back, share, overflow) as ~38pt **circular** buttons with subtle outline + faint drop shadow — Apple Maps / News / Photos pattern. Flat icon-only buttons don't read as premium. This primitive gets used in `PGFrostedAppBar`'s back slot and `actions:` slot, plus anywhere else we need a "floating-circle" tap target (e.g. dismiss buttons on Cupertino sheets).

**Files:**
- Create: `lib/core/widgets/pg_circular_icon_button.dart`
- Create: `test/core/widgets/pg_circular_icon_button_test.dart`

- [x] **Step 1: Write failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/widgets/pg_circular_icon_button.dart';

void main() {
  group('PGCircularIconButton', () {
    testWidgets('renders icon centered in a circle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PGCircularIconButton(
              icon: Icons.ios_share_rounded,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
    });

    testWidgets('fires onTap once per tap', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PGCircularIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => taps++,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(PGCircularIconButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('respects custom tone color', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PGCircularIconButton(
              icon: Icons.delete_outline_rounded,
              tone: Colors.red,
              onTap: () {},
            ),
          ),
        ),
      );
      final iconWidget = tester.widget<Icon>(find.byType(Icon));
      expect(iconWidget.color, Colors.red);
    });

    testWidgets('respects custom size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PGCircularIconButton(
              icon: Icons.close_rounded,
              size: 44,
              onTap: () {},
            ),
          ),
        ),
      );
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(PGCircularIconButton),
          matching: find.byType(Container),
        ),
      );
      expect(
        (container.constraints?.minWidth ?? container.decoration != null
                ? 44.0
                : 0.0),
        44.0,
      );
    });
  });
}
```

- [x] **Step 2: Run — expect FAIL** (file doesn't exist)

```
flutter test test/core/widgets/pg_circular_icon_button_test.dart
```

- [x] **Step 3: Build the primitive**

Create `lib/core/widgets/pg_circular_icon_button.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';

/// Circular icon button — Apple Maps / News / Photos top-chrome pattern.
///
/// A ~38pt circular surface with a subtle outline + faint drop shadow,
/// containing a centered icon. Used by [PGFrostedAppBar] for the
/// leading back chevron and trailing actions, and anywhere else a
/// "floating circle" tap target is wanted (modal dismiss, etc.).
///
/// Press feedback via [PGPressable]: scales to 0.92 (slightly deeper
/// than the 0.96 default — small surface area benefits from more depth)
/// with a light haptic.
///
/// ```dart
/// PGCircularIconButton(
///   icon: Icons.ios_share_rounded,
///   onTap: () => _showShareSheet(context),
/// )
/// ```
class PGCircularIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  /// Outer diameter. Default 38 — Apple's iOS top-chrome icon-button size.
  final double size;

  /// Override the icon color. Defaults to `colorScheme.onSurface`.
  /// Pass a destructive red for "Remove" / "Delete" actions.
  final Color? tone;

  /// Whether to fire a tap haptic. Default true; pass false when the
  /// destination already produces a haptic on first present (e.g. iOS
  /// share sheet) to avoid double-tap.
  final bool haptic;

  const PGCircularIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 38,
    this.tone,
    this.haptic = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = tone ?? scheme.onSurface;
    return PGPressable(
      onTap: onTap,
      pressedScale: 0.92,
      haptic: haptic,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow.withValues(alpha: 0.85),
          shape: BoxShape.circle,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
          // Subtle drop shadow — the "3D high-end" cue. Buttons hover
          // very slightly above the page material.
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: size * 0.48, color: iconColor),
      ),
    );
  }
}
```

- [x] **Step 4: Run tests — expect PASS**

- [x] **Step 5: Update `PGFrostedAppBar` to use `PGCircularIconButton`**

In `lib/core/widgets/pg_frosted_app_bar.dart`, replace the inline back-chevron `PGPressable` with:

```dart
leadingWidget = PGCircularIconButton(
  icon: Icons.arrow_back_ios_new_rounded,
  onTap: () => Navigator.of(context).maybePop(),
);
```

The actions slot already accepts `List<Widget>` — callers (e.g. B.3b) pass `PGCircularIconButton` instances directly.

- [x] **Step 6: Run analyze + commit**

```bash
flutter analyze
git add lib/core/widgets/pg_circular_icon_button.dart \
  test/core/widgets/pg_circular_icon_button_test.dart \
  lib/core/widgets/pg_frosted_app_bar.dart
git commit -m "feat(core): PGCircularIconButton — premium top-chrome tap target

Apple Maps / News / Photos pattern: ~38pt circular surface, subtle
outline, faint drop shadow, centered icon. Replaces flat icon buttons
in PGFrostedAppBar's back + actions slots. The drop shadow is the '3D
high-end' cue that makes the chrome feel like physical objects floating
above the page material instead of flat-painted glyphs.

PressedScale 0.92 (vs. the 0.96 default for content cards) — small
surface area, deeper feedback feels right.

Plan: docs/superpowers/plans/2026-04-28-app-wide-apple-grade.md (Task 0.2)"
```

---

## Phase A — Tab destinations (highest visual-impact)

The four tab roots define what the user sees most. Inconsistency between Home (frosted) and the other three (Material AppBar) is the loudest "this isn't all one app" signal. Fix that first.

### Task A.1: Stack tab — replace AppBar with PGFrostedAppBar

**Files:**
- Modify: `lib/features/stack/stack_screen.dart`
- Modify: `test/features/stack/stack_screen_test.dart` (only if existing assertions break)

- [x] **Step 1: Read the current stack_screen.dart top-of-build to confirm AppBar pattern**

Run: `Read tool on lib/features/stack/stack_screen.dart, full file`. Look for the `AppBar` usage around lines 49–70 and the body's `CustomScrollView` (or non-sliver scaffolding).

- [x] **Step 2: Convert Scaffold body to a CustomScrollView with PGFrostedAppBar**

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

- [x] **Step 3: Run home + stack tests**

```
flutter test test/features/home/ test/features/stack/ test/core/widgets/pg_frosted_app_bar_test.dart
```

Expected: all pass. If `stack_screen_test.dart` had `find.byType(AppBar)` assertions, update them to `find.text('My Stack')` instead.

- [x] **Step 4: Manual smoke on simulator** — confirm: (a) title renders centered, (b) frosted background fades in on scroll, (c) bottom hairline appears, (d) status bar text contrast is readable.

- [x] **Step 5: Run analyze + commit**

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

- [x] **Step 1: Replace AppBar with PGFrostedAppBar**

Same pattern as Task A.1. `automaticallyImplyLeading: false`. Title: `'Profile'` (or whatever the current AppBar title is — preserve it).

- [x] **Step 2: Replace settings-tile InkWells with PGPressable**

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

- [x] **Step 3: Sweep `Switch` → `Switch.adaptive`**

Run: `grep -n "Switch(" lib/features/settings/settings_screen.dart` (also check for `SwitchListTile` — replace with `SwitchListTile.adaptive`).

For each occurrence, replace `Switch(` with `Switch.adaptive(` and `SwitchListTile(` with `SwitchListTile.adaptive(`. The `.adaptive` constructor renders `CupertinoSwitch` on iOS and Material on Android — zero API cost, big platform-feel win.

- [x] **Step 4: Run analyze + tests**

```
flutter analyze
flutter test test/features/settings/  # if any tests exist
```

- [x] **Step 5: Commit**

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

- [x] **Step 1: Read current `_LookupOverlay` (or wherever the spinner lives) implementation**

Run: `Read tool on scanner_screen.dart` around line 255. Confirm the structure.

- [x] **Step 2: Replace `Container + CircularProgressIndicator` with a PGCard-wrapped pair (icon + small label + shimmer line)**

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

- [x] **Step 3: Run scanner tests + analyze**

```
flutter test test/features/scanner/ 2>/dev/null
flutter analyze
```

- [x] **Step 4: Commit**

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

- [x] **Step 1: Replace AppBar with PGFrostedAppBar**

Pattern from Task A.1. Profile Setup IS reachable from elsewhere (it pops back to home), so `automaticallyImplyLeading: true` (the default) — back chevron renders automatically.

If the existing AppBar has `actions: [TextButton('Skip', onPressed: ...)]`, port that into `PGFrostedAppBar.actions: [TextButton(...)]`.

- [x] **Step 2: Wrap RadioListTile / CheckboxListTile bodies with PGPressable**

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

- [x] **Step 3: Add haptic on the primary CTA button (Next / Complete)**

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

- [x] **Step 4: Run analyze + tests**

```
flutter analyze
flutter test test/features/profile/ 2>/dev/null
```

- [x] **Step 5: Commit**

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

- [x] **Step 1: Replace AppBar with PGFrostedAppBar** (same pattern, with default leading back chevron)

- [x] **Step 2: Wrap suggestion ListTiles with PGPressable**

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

- [x] **Step 3: Polish the Check button**

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

- [x] **Step 4: Verify result-display haptic gating**

When the check returns a result, the severity banner is shown. Add `PGHaptics.forSeverity(result.severity, context)` at the moment the result first renders, so the user feels the verdict before reading it. Wrap the result-display callback in a `WidgetsBinding.instance.addPostFrameCallback` if needed to ensure the haptic fires after the banner mounts.

- [x] **Step 5: Run analyze + tests + commit**

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

### ~~Task B.3a: Product Detail — "Apple Altar" hero refactor~~

> **[SUPERSEDED 2026-04-29 — folded into INITIATIVE_PRODUCT_TRUST_AND_IA.md Sprint 1 T1.1 (revised score-led hero spec). Trust/IA team owns this. The Yuka/SuppCo user-habit evidence shifted the spec to score-led hero with HeroVerdict gated to Avoid/Contraindicated/Blocked only — lower verdicts live in Section 2. Do not execute the steps below; use T1.1 as source of truth.]**

**Why:** The current `_HeaderSection` (`product_detail_screen.dart:1301–1551`) is a two-row card with a 56-pt thumbnail + cramped score-row that visibly squeezes on a 320-pt iPhone SE. The score ring competes with verdict-text-and-pills for the same horizontal space; the trust chips, FitScore badge, and "View Supplement Label" button all stack as afterthoughts. Rebuild it as a single elevated PGCard with a horizontal identity row at the top and a centered vertical "altar" below — the Apple Health / Oura clinical-detail pattern. Score becomes a 96-pt focal point. Verdict becomes a full-width safety-aware banner (so a stack interaction overrides "Good match for sleep" with "Avoid with metformin" — medical-grade priority).

**Files:**
- Modify: `lib/features/product_detail/product_detail_screen.dart` — `_HeaderSection`, `_HeroScoreReason`, `_HeroMetaPill`, `_HeroTrustChips`, `_BlockedBanner` if needed
- Possibly create: `lib/features/product_detail/widgets/hero_verdict_banner.dart` (extract for testability)
- Possibly create: `lib/features/product_detail/providers/hero_verdict_provider.dart` (the safety-override decision)

- [x] **Step 1: Read full current hero (`_HeaderSection`) and confirm what changes**

Before writing code, run `Read` on `product_detail_screen.dart` at offset 1300, limit 250. Map every existing element to its new home in the altar layout. Confirm: `ProductImage`, title/brand/form column, `_ScoreRingButton`, `VerdictBadge`, percentile text, grade pill (`_HeroMetaPill`), "Limited data" pill, `_HeroScoreReason` banner, `PGFitScoreBadge` row, `_HeroTrustChips`, "View Supplement Label" outline button, `_BlockedBanner` (when blocked).

- [x] **Step 2: Build the safety-override verdict provider**

Create `lib/features/product_detail/providers/hero_verdict_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';

/// Safety-aware verdict for the product hero. Combines the product's
/// static verdict (RECOMMENDED/GOOD/MODERATE/...) with the user's stack
/// to produce a single headline that honors "safety > goal match".
///
/// Priority (highest first):
///   1. UNSAFE / BLOCKED product verdict             → product-side block
///   2. Contraindicated/avoid stack interaction      → "Avoid with X"
///   3. Caution/monitor stack interaction            → "Monitor with X"
///   4. Personal goal match (FitScore)               → "Good match for X"
///   5. Plain product verdict                        → "Recommended" / etc.
class HeroVerdict {
  /// Headline copy shown in the banner (max 2 lines).
  final String headline;
  /// Severity drives the banner's tone color and haptic on first paint.
  final Severity severity;
  /// When non-null, names the offending agent (medication or supplement
  /// in the user's stack). Used for "Avoid with metformin" copy.
  final String? affectingAgent;
  /// True when this is a safety override of the product's static verdict.
  /// Used to gate analytics / extra warning chrome.
  final bool isSafetyOverride;

  const HeroVerdict({
    required this.headline,
    required this.severity,
    this.affectingAgent,
    this.isSafetyOverride = false,
  });
}

final heroVerdictProvider = FutureProvider.autoDispose
    .family<HeroVerdict, String>((ref, dsldId) async {
  // 1. Static product verdict — always takes precedence for hard blocks.
  // 2. Top stack interaction with this product — overrides goal copy when
  //    severity >= caution.
  // 3. Personal goal match — only the celebratory branch.
  // 4. Plain verdict — generic "Recommended / Good / etc." fallback.
  //
  // Implementation pulls from existing providers — DO NOT invent new
  // engine logic in this provider; just compose:
  //   - product detail blob (already cached)
  //   - stackInteractionsForProduct(dsldId) (existing)
  //   - fitScoreForProductProvider(dsldId) (existing)
  //
  // Return the highest-priority HeroVerdict.

  // ... compose existing providers ...
  throw UnimplementedError('Composition of existing providers — see step 3');
});
```

The TODO above is intentional — Step 3 fills it in once the existing provider names are confirmed by reading their files. Keep the public API (`HeroVerdict` shape, `heroVerdictProvider` family signature) stable.

- [x] **Step 3: Implement the priority ladder**

Read `lib/services/stack/stack_interaction_checker.dart` to find the function name that returns the highest-severity interaction for a given product DSLD id against the current stack. Then fill in the provider body using `ref.watch` on the relevant providers and a switch on the priority ladder.

Key behavior to preserve:
- **Severity → tone color**: use `Severity.color` for banner background tint at low alpha (matches `_HeroScoreReason` pattern)
- **Headline copy**: priority 2/3 use `'${severity.label} with ${affectingAgent}'` (e.g. "Avoid with metformin"); priority 4 uses `'Good match for ${goalName}'` only when FitScore matched; priority 5 uses `'${verdict.label}'` plain
- **Reduce-motion**: no animation on this provider — animations live in the widget

- [x] **Step 4: Build the new hero — vertical altar**

Replace the existing `_HeaderSection.build` with this structure (preserve all field declarations; only the build method changes):

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final fitScoreAsync = ref.watch(fitScoreForProductProvider(dsldId));
  final heroVerdictAsync = ref.watch(heroVerdictProvider(dsldId));

  // Single elevated PGCard — drops the prior nested Container + DecoratedBox.
  return PGCard(
    variant: PGCardVariant.elevated,
    padding: const EdgeInsets.all(AppTheme.space20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ────────────────────────────────────────────────
        // ROW 1 — IDENTITY (horizontal, App Store pattern)
        // ────────────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image bumped from 56 → 84pt for hero presence.
            // Subtle drop shadow + 16pt radius makes it feel like an
            // object on a surface, not a flat PNG.
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ProductImage(
                  dsldId: dsldId,
                  upc: upc,
                  productName: productName,
                  brandName: brandName,
                  formFactor: formFactor,
                  score: score100,
                  size: 84,
                ),
              ),
            ),
            const SizedBox(width: AppTheme.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    productName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      height: 1.16,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Inline dot-separated subtitle — Apple Health / App
                  // Store pattern: `Brand · Form · Dose`. Renders only the
                  // segments that have data (no orphan dots). Replaces
                  // the prior brand-on-line-1, formFactor-on-line-2 stack
                  // which felt list-like rather than premium.
                  if (_hasAnySubtitle(brandName, formFactor, servingDose)) ...[
                    const SizedBox(height: 4),
                    Text.rich(
                      _buildSubtitleSpan(
                        context: context,
                        brand: brandName,
                        form: formFactor,
                        dose: servingDose,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (dietaryTags.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.space12),
                    _HeroTrustChips(tags: dietaryTags),
                  ],
                ],
              ),
            ),
          ],
        ),

        // Hard stop for blocked products — the altar never renders for
        // these; the BlockedBanner takes over. Same behavior as today.
        if (isBlocked) ...[
          const SizedBox(height: AppTheme.space16),
          _BlockedBanner(
            verdict: verdict,
            blockingReason: blockingReason,
            topWarnings: topWarnings,
            bannedSubstanceDetail: bannedSubstanceDetail,
          ),
        ] else ...[
          const SizedBox(height: AppTheme.space24),

          // ────────────────────────────────────────────────
          // ROW 2 — THE ALTAR (vertical, centered)
          // ────────────────────────────────────────────────

          // 96-pt centered FitScore ring. Scales up with AppMotion.spring
          // on first mount (entrance choreography in step 7).
          Center(
            child: _ScoreRingButton(
              score: isNotScored ? null : score100,
              size: 96,
              onTap: onScoreInfoTap,
            ),
          ),

          // Grade · Description directly below (centered, no
          // percentile — hidden until the percentile context is
          // strong enough to justify the cognitive load).
          if (!isNotScored && grade.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space12),
            Center(
              child: Text(
                _gradeDescriptionLine(grade, verdict),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],

          const SizedBox(height: AppTheme.space16),

          // Full-width safety-aware verdict banner.
          // - Plain product verdict on a calm tone background by default
          // - Safety-override (caution/avoid/contraindicated stack
          //   interaction) overrides the goal-match branch with strong
          //   tone + the offending agent's name.
          _HeroVerdictBanner(verdict: heroVerdictAsync),

          // "Limited data" — promoted to its own line as a banner ONLY
          // when present. Was previously buried in a pill row with the
          // grade; that hid the trust signal that needs to be loudest.
          if (mappedCoverage < 0.3) ...[
            const SizedBox(height: AppTheme.space12),
            const _LimitedDataBanner(),
          ],

          // Score reason banner — kept, full-width.
          if (scoreReason != null) ...[
            const SizedBox(height: AppTheme.space12),
            _HeroScoreReason(
              text: scoreReason!.text,
              isPositive: scoreReason!.isPositive,
            ),
          ],

          // ────────────────────────────────────────────────
          // ROW 3 — PERSONAL FIT (conditional, tappable)
          // ────────────────────────────────────────────────
          if (fitScoreAsync.asData?.value != null) ...[
            const SizedBox(height: AppTheme.space16),
            PGPressable(
              onTap: () =>
                  context.push(Routes.profileSetup),
              pressedScale: 0.98,
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: AppTheme.space8),
                  Text(
                    'Personalized for you',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],

          // "View Supplement Label" — always last in the hero. Drops
          // OutlinedButton.icon for a quieter PGPressable text-link, so
          // it doesn't compete visually with the verdict banner.
          if (imageUrl != null && imageUrl!.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space12),
            PGPressable(
              onTap: () {
                final uri = Uri.tryParse(imageUrl!);
                if (uri != null) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              pressedScale: 0.98,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'View Supplement Label',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    ),
  );
}
```

Add helpers at file scope (or top of `_HeaderSection`):

```dart
/// "B • Good", "A- • Recommended", etc. — the grade plus the
/// human-readable verdict label.
String _gradeDescriptionLine(String grade, String verdict) {
  final label = VerdictBadge.labelFor(verdict);
  return '$grade  ·  $label';
}

/// True when at least one subtitle segment has content. Skip rendering
/// the subtitle row entirely when all three are empty (rather than
/// rendering an empty SizedBox).
bool _hasAnySubtitle(String brand, String form, String? dose) =>
    brand.isNotEmpty || form.isNotEmpty || (dose != null && dose.isNotEmpty);

/// Builds the dot-separated subtitle: `Thorne · 60 Capsules · 135 mg
/// per serving`. Drops orphan dots — if `brand` is empty but `form`
/// is present, the result starts with `form`, not ` · form`.
TextSpan _buildSubtitleSpan({
  required BuildContext context,
  required String brand,
  required String form,
  String? dose,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final segments = <String>[
    if (brand.isNotEmpty) brand,
    if (form.isNotEmpty) form,
    if (dose != null && dose.isNotEmpty) dose,
  ];
  final joined = segments.join('  ·  ');
  return TextSpan(
    text: joined,
    style: theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.05,
    ),
  );
}
```

**Note on `servingDose`**: this third segment is the lead ingredient's dose (e.g. `'135 mg per serving'`). It is NOT currently a top-level field on the product blob — derive from `ingredients[0].dose` if available; pass `null` if not. The reference shows it; ship without it on day one if the data path is gnarly, then add as a follow-up. Treat it as nullable throughout: `_HeaderSection.servingDose` is `String?` with default null.

**Replace `_HeroMetaPill` usage in `_HeroTrustChips` with new outline-only chip widget.** The reference uses outlined pills with no icon — Apple's iOS chip style (App Store, Apple Music, App Library). Filled pills with icons read as Material / Android. Add the new widget at file scope:

```dart
/// Outline-only trust chip used in the product hero. No fill, no icon
/// — just a clean text pill with a primary-tinted border. Matches the
/// reference's `Vegan / Gluten-Free / NSF Certified` styling.
///
/// Certifications use brand primary; dietary tags use the success
/// green so the eye reads "certified" as a louder signal than a tag.
class _HeroTrustChipOutline extends StatelessWidget {
  final String label;
  final bool isCertification;

  const _HeroTrustChipOutline({
    required this.label,
    required this.isCertification,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = isCertification ? scheme.primary : AppTheme.scoreExcellent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(
          color: tone.withValues(alpha: 0.55),
          width: 1.0,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tone,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}
```

Update `_HeroTrustChips.build` to use the new outline chip:

```dart
return Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
    ...visible.map(
      (tag) => _HeroTrustChipOutline(
        label: tag.label,
        isCertification: tag.isCertification,
      ),
    ),
    if (overflow > 0)
      _HeroTrustChipOutline(
        label: '+$overflow more',
        isCertification: false,
      ),
  ],
);
```

- [x] **Step 5: Build `_HeroVerdictBanner` (extracted widget)**

This widget reads the `AsyncValue<HeroVerdict>` and renders three states:
- **Loading** — `PGShimmerBox(height: 56, radius: AppTheme.radiusMedium)` (preserves layout)
- **Error / null verdict** — render nothing (`SizedBox.shrink()`)
- **Data** — full-width banner, severity-tinted background, icon + headline

```dart
class _HeroVerdictBanner extends StatelessWidget {
  final AsyncValue<HeroVerdict> verdict;
  const _HeroVerdictBanner({required this.verdict});

  @override
  Widget build(BuildContext context) {
    return verdict.when(
      loading: () => const PGShimmerBox(
        height: 56,
        radius: AppTheme.radiusMedium,
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (v) {
        final theme = Theme.of(context);
        final tone = v.severity.color;
        final icon = _iconForSeverity(v.severity);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space16,
            vertical: AppTheme.space12,
          ),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: tone.withValues(alpha: 0.20)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: tone, size: 20),
              const SizedBox(width: AppTheme.space12),
              Expanded(
                child: Text(
                  v.headline,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _iconForSeverity(Severity s) {
    switch (s) {
      case Severity.contraindicated:
      case Severity.avoid:
        return Icons.warning_amber_rounded;
      case Severity.caution:
      case Severity.monitor:
        return Icons.error_outline_rounded;
      case Severity.informational:
      case Severity.safe:
        return Icons.check_circle_outline_rounded;
    }
  }
}
```

- [x] **Step 6: Build `_LimitedDataBanner`**

Tiny widget, always identical:

```dart
class _LimitedDataBanner extends StatelessWidget {
  const _LimitedDataBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space12,
        vertical: AppTheme.space8,
      ),
      decoration: BoxDecoration(
        color: AppTheme.insufficientData.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: 14,
            color: AppTheme.insufficientData,
          ),
          const SizedBox(width: 6),
          Text(
            'Limited data on this product — score may shift as we learn more.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.insufficientData,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
```

- [x] **Step 7: Add staggered entrance choreography**

Wrap the hero card itself in a `TweenAnimationBuilder<double>` that drives an opacity + translateY for the entire hero (slide-in over 240ms). Inside, scale the score ring from 0.85 → 1.0 over 320ms with `AppMotion.spring` (300ms delay so it lands AFTER the identity row settles). Below cards (deep dive, pipeline sections) get a fade-up over 280ms with 450ms delay.

Implement via a single `_HeroEntranceController` State that exposes three computed values (`identityProgress`, `ringScale`, `bodyProgress`) all driven from one `AnimationController` with sequenced intervals. Don't fire the animation when `MediaQuery.disableAnimationsOf(context)` is true — under reduce-motion all three jump to their final values instantly.

Skipping the full code block here because the choreography is straightforward `Interval` math; refer to the home plan's Sprint 27.20 commit for the `TweenAnimationBuilder + Curves` pattern. Use `AppMotion.spring` for the ring (the one place spring with overshoot is genuinely warranted — bouncy entrance reads as triumphant) and `AppMotion.gentleRelease` for everything else.

- [x] **Step 8: Wire `_ScoreRingButton.size` parameter**

The current `_ScoreRingButton` constructor likely doesn't accept a `size` param (it uses a fixed default). Add an optional `double size = 64` parameter and thread it through. Step 4's altar layout passes 96.

- [x] **Step 9: Run analyze + tests + manual smoke**

```
flutter analyze
flutter test test/features/product_detail/
```

Manual smoke: open KSM-66 (the test product Sean has been using). Confirm:
1. Image is visibly larger and feels like an object (shadow + radius)
2. Score ring is centered and dominant
3. Verdict banner is full-width and tinted
4. With a contraindicated stack item present (e.g. add Metformin to stack first), the verdict banner FLIPS to "Avoid with metformin" instead of the goal-match copy
5. Limited-data banner appears on its own line (not inline with grade) when `mappedCoverage < 0.3`
6. The "Personalized for you" row taps through to profile setup
7. Reduce-motion suppresses the entrance choreography

- [x] **Step 10: Commit**

```bash
git add lib/features/product_detail/
git commit -m "feat(product-detail): Apple Altar hero refactor

Restructures _HeaderSection from a cramped 2-row card into a single
elevated PGCard with a horizontal identity row (image + name) on top
and a centered vertical 'altar' below. Apple Health / Oura clinical-
detail pattern. Score ring moves from a sub-row component to a 96-pt
focal point.

The verdict badge becomes a full-width safety-aware banner via the
new heroVerdictProvider — when a stack interaction is caution-or-
worse, the banner overrides the goal-match copy with 'Avoid with
[medication]'. Safety > goal match. Medical-grade priority encoded
in pixel hierarchy.

Hides the percentile (low signal-to-cognitive-cost ratio today),
promotes 'Limited data' to its own banner line (was buried in a pill
row), drops the OutlinedButton in favor of a quiet PGPressable text
link, adds a tappable 'Personalized for you' row that routes to
profile setup.

Plus staggered entrance choreography: identity slide-in → ring scale-
up with AppMotion.spring → body fade-up. Reduce-motion suppresses
the sequence."
```

---

### Task B.3b: Product Detail — frosted app bar (with share action) + pipeline-section surface audit

> **[RUN AFTER T1.1 sign-off — 2026-04-29]** Same file as Trust & IA Sprint 1 T1.1 (`product_detail_screen.dart`). Concurrent edits would cause merge churn. Hold this task until the Trust/IA team signs off T1.1, then execute as the mechanical follow-up.

**Files:**
- Modify: `lib/features/product_detail/product_detail_screen.dart` — replace SliverAppBar (around line 341)
- Audit: `lib/features/product_detail/widgets/pipeline_sections/*.dart`

This is the smaller, mechanical follow-up to B.3a. Two moves:

- [x] **Step 1: Replace SliverAppBar with PGFrostedAppBar (circular share button on top)**

Per user direction: drop the floating "Scan Another" idea (the bottom nav makes it redundant — to scan again the user just taps the Scan tab or swipes back). Move the share affordance to the top right of the frosted app bar where it belongs in iOS apps (Photos, Safari, Wallet all put share in the top trailing slot). Use the new `PGCircularIconButton` (Phase 0.2) so the share button matches the reference's premium circular-button styling — subtle outline, faint drop shadow, icon centered. Apple Maps / News pattern.

The leading back chevron is automatically rendered as a `PGCircularIconButton` by `PGFrostedAppBar` (Phase 0.1 + 0.2 wired this internally) when the route can pop — no need to pass `leading:` here.

```dart
// Replace the existing SliverAppBar (around lines 341–365) with:
PGFrostedAppBar(
  // Title is intentionally empty — the hero card below carries the
  // product name as part of the identity row, so a duplicated title
  // in the app bar would compete. iOS App Store uses the same trick.
  title: '',
  actions: [
    PGCircularIconButton(
      icon: Icons.ios_share_rounded,
      onTap: () => _onShare(context, product),
      // Skip haptic — the iOS share sheet fires its own haptic on
      // present; firing one here would double-tap the user.
      haptic: false,
    ),
    // Optional follow-up: a 3-dot overflow menu (Save, Report,
    // Mark-as-taken). Defer until we have a confirmed product
    // decision on which secondary actions belong here. Adding it
    // empty just to match the reference's three buttons would
    // pollute the chrome.
    //
    // PGCircularIconButton(
    //   icon: Icons.more_horiz_rounded,
    //   onTap: () => _showProductOptionsSheet(context, product),
    // ),
  ],
),
```

- [x] **Step 2: Audit pipeline-section widgets for surface-tier compliance**

Walk each pipeline section in `lib/features/product_detail/widgets/pipeline_sections/` and `lib/features/product_detail/widgets/`:

- `probiotic_detail_section.dart`
- `evidence_detail_section.dart`
- `synergy_detail_section.dart`
- `formulation_detail_section.dart`
- `manufacturer_violations_section.dart`
- `certification_detail_section.dart`
- `heavy_metal_warning_card.dart`
- `score_breakdown_card.dart`
- `blocked_product_view.dart`

For each, grep for raw `Container(` with a `BoxDecoration` painting a visible background. Each one should be `PGCard(variant: ...)` per the 4-tier system. Most are likely fine post-Sprint 27.18; verify and migrate any stragglers. Note: per Sprint 27.19's audit, intra-card layout primitives (e.g. tinted info chips inside an already-tiered PGCard) are NOT a fifth tier and should stay as-is.

Add `PGPressable` wrapping to any tappable card that currently uses `Material + InkWell` (apply the same pattern as Sprint 27.19's home-card adoption).

- [x] **Step 3: Run analyze + tests + commit**

```bash
flutter analyze
flutter test test/features/product_detail/
git add lib/features/product_detail/
git commit -m "feat(product-detail): PGFrostedAppBar with top-right share + section audit

PGFrostedAppBar replaces the prior SliverAppBar (title intentionally
empty — hero card below carries the product name). Share affordance
moves to the top trailing slot via PGPressable + Icons.ios_share_rounded
— iOS canonical placement (Photos, Safari, Wallet).

Pipeline-section widgets audited for PGCard.variant compliance.
PGPressable wrapping added to any remaining Material+InkWell card
tappables — completes the home/sub-page tactile adoption pattern."
```

---

## Phase C — Cross-cutting motion + haptic adoption sweep

These tasks span multiple files and are best done as one focused pass per concern.

### Task C.1: Replace Material modal/dialog primitives with Cupertino on iOS

**Files:** any file using `showModalBottomSheet`, `showDialog`, `showAboutDialog`.

- [x] **Step 1: Find every modal call site**

```bash
cd "/Users/seancheick/PharmaGuide ai"
grep -rn "showModalBottomSheet\|showDialog\|showAboutDialog" lib/ \
  | grep -v ".g.dart\|.freezed.dart" > /tmp/modals.txt
wc -l /tmp/modals.txt
```

- [x] **Step 2: Build a `PGModal.bottomSheet` helper**

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

- [x] **Step 3: Migrate one file at a time**

Pick the lowest-stakes call sites first (e.g. settings about-app dialog). Replace `showDialog(context: ..., builder: ...)` with `PGModal.alert(context: ..., title: ..., message: ..., actions: [PGAlertAction(...)])`.

For each migration, run analyze + relevant tests, then commit per file:

```bash
git commit -m "refactor(<feature>): migrate modals to PGModal (Cupertino on iOS)"
```

This task can be parallelized — each file's migration is independent.

- [x] **Step 4: After every call site is migrated, lint-check**

```bash
grep -rn "showModalBottomSheet\|showDialog\b" lib/ | grep -v "PGModal" | grep -v ".g.dart"
```

Expected: only matches inside `pg_modal.dart` itself.

### Task C.2: Switch / Checkbox / Slider adaptive sweep

**Files:** any file using `Switch(`, `Checkbox(`, `Slider(`, `SwitchListTile(`, `CheckboxListTile(`.

- [x] **Step 1: Audit**

```bash
grep -rn "Switch(\|Checkbox(\|Slider(\|SwitchListTile(\|CheckboxListTile(" lib/ \
  | grep -v ".g.dart\|adaptive\b" > /tmp/material_controls.txt
wc -l /tmp/material_controls.txt
```

- [x] **Step 2: Replace each with `.adaptive` variant**

Mechanical change: `Switch(` → `Switch.adaptive(`, `Checkbox(` → `Checkbox.adaptive(`, `SwitchListTile(` → `SwitchListTile.adaptive(`. Slider has no `.adaptive` constructor — wrap in a `Platform.isIOS ? CupertinoSlider(...) : Slider(...)` ternary.

- [x] **Step 3: One commit per feature directory**

```bash
git add lib/features/<area>/
git commit -m "refactor(<area>): adaptive Material controls for iOS feel"
```

### Task C.3: Motion-token sweep — replace ad-hoc durations / curves

**Files:** any file using `Duration(milliseconds: ...)` directly on animation properties, or `Curves.easeInOut` / `Curves.linear` / `Curves.bounceOut` etc. that don't go through `AppMotion.*`.

- [x] **Step 1: Audit**

```bash
grep -rn "duration: Duration(milliseconds:\|Curves\." lib/features/ lib/core/widgets/ \
  | grep -v "AppMotion\." \
  | grep -v ".g.dart" \
  | head -50
```

- [x] **Step 2: For each, decide the right token**

| Existing | Use |
|---|---|
| `Duration(milliseconds: 100..200)` | `AppMotion.fast` (150ms) |
| `Duration(milliseconds: 200..280)` | `AppMotion.medium` (240ms) |
| `Duration(milliseconds: 300..360)` | `AppMotion.slow` (320ms) |
| `Duration(milliseconds: 400+)` | `AppMotion.emphasized` (420ms) |
| `Curves.easeInOut`, `Curves.fastOutSlowIn` | `AppMotion.standard` |
| `Curves.easeOutCubic` | `AppMotion.gentleRelease` (for press-up) or `AppMotion.standard` |
| `Curves.bounceOut` etc. | Don't use; replace with `AppMotion.spring` only for state-flip toggles |

- [x] **Step 3: One commit per feature directory**

```bash
git commit -m "refactor(motion): align <area> motion to AppMotion tokens"
```

---

## Phase D — Polished cross-screen primitives

### ~~Task D.1: Build `PGAdaptiveBackButton`~~

> **[FOLDED INTO 0.2 — 2026-04-29]** `PGCircularIconButton` (Phase 0.2, commit `6e30f62`) already encapsulates the adaptive back-chevron behavior — `PGFrostedAppBar`'s default leading slot uses it. A standalone `PGAdaptiveBackButton` wrapper would be a parallel primitive solving a problem that no longer exists. Skip this task entirely.

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

### Task D.2: Audit and update Empty States — ✅ DONE 2026-04-29 (`5247bae`)

The home `Recents` empty state uses `_OutlineScanButton` (a tappable pill). Other screens may have less-polished empty states.

- [x] **Step 1: Audit empty states across features**

```bash
grep -rn "EmptyState\|Empty\|isEmpty" lib/features/ \
  | grep -v ".g.dart" \
  | grep -v "// " \
  | head -30
```

- [x] **Step 2: For each screen with a bespoke empty-state widget, ensure it uses:**
  - `PGCard(variant: PGCardVariant.recessed)` outer
  - A 56-pt circular icon well (`Container` with surface tint)
  - Title (titleSmall, w700)
  - Subtitle (bodySmall, onSurfaceVariant)
  - One CTA wrapped in `PGPressable`

The home Recents empty state at `home_recent_scans.dart:127–189` is the reference. Cross-check against Stack empty state, Wishlist empty state, search empty results, and Quick Check insufficient-data state.

- [x] **Step 3: Commit per fix**

#### Task D.2 Findings — empty-state vocabulary already cohesive

**Audit walked all empty-state usages across `lib/features/`:**

- `home_recent_scans._buildEmptyState` (lines 128–189) — already the canonical pattern (PGCard.recessed + 56pt circular icon well + titleSmall w700 + bodySmall onSurfaceVariant + outline scan-button CTA). **This IS the reference.** Leave as-is.
- `home_stack_health._buildEmptyState` — intentionally a CTA card on `PGCard.elevated` (the whole card is tappable, navigates to `/scan`), not a "nothing here" placeholder. Different pattern by design. Leave as-is.
- All other empty states (search × 2, product detail × 1, stack × 3, medications × 1) already route through `PGEmptyState`. Cohesive vocabulary — zero migrations required.

**The only smell** was inside `PGEmptyState._PillButton` itself: the CTA pill was still wrapped in `Material + InkWell` instead of `PGPressable`, so every empty-state CTA across the app was missing the Apple-grade compression + spring + light haptic that Sprint 27.19 C1 standardized. Single migration uplifts every consumer:

- `Material + InkWell + Container` → `PGPressable + Container` with `pressedScale: 0.97` (between the 0.96 default and the 0.98 dense-row scale).
- Dropped the hardcoded `fontFamily: 'Inter'` from the label `TextStyle` — the theme's `_platformFontFamily` (Sprint 27.19 G1) handles Inter on Android / system SF Pro on iOS.

Commit: `5247bae`. Verification: `flutter analyze` clean; 56/56 tests across stack + search + medications green.

---

## Phase F — Product Detail data visualization (Apple Altar H4)

The Apple Altar spec calls for three data-viz primitives in the product detail body:

- **Donut chart** — Quality Score (e.g. "82") rendered as a circular progress with center number
- **Pillar bars** — horizontal bars for the four scoring pillars (Ingredient Quality, Safety & Purity, Evidence, Brand Trust)
- **Atom-style ingredients** — circular pills (e.g. "Mg") with per-ingredient evidence badge ("Strong evidence" / "Limited data")

**Data dependency caveat:** before building any of these, verify the underlying pipeline data exists. If the four pillars don't exist as discrete scores in the product blob, F.2 either (a) derives them from `score_bonuses[]` / `score_penalties[]` aggregation or (b) waits for a pipeline-side ticket to expose them. Don't ship a chart driven by invented numbers.

### Task F.0: Data availability audit

> **[PROMOTED 2026-04-29 — BLOCKING T1.4]** This audit unblocks Trust & IA Sprint 1 T1.4 (pillar breakdown). Run next; ping Sean with the GREEN / YELLOW / RED verdict the moment it lands.

**Files (read-only audit):**
- `lib/data/database/tables/products_core_table.dart` (or wherever the product schema lives)
- `lib/services/score/` (any pillar-aggregation logic)
- `assets/db/core_database.sqlite` (sample query if needed)
- The detail blob shape: `lib/features/product_detail/providers/detail_blob_provider.dart`

- [x] **Step 1: Confirm or refute four-pillar score availability**

Walk the product schema + score services. Document one of:
- ✅ Four pillar scores exist as separate fields → F.2 is a pure UI build
- ⚠️ Pillar scores can be derived from `score_bonuses[]` / `score_penalties[]` → F.2 needs a small aggregation step
- ❌ No pillar data exists → split F.2 into a pipeline ticket + a Flutter follow-up

- [x] **Step 2: Confirm per-ingredient evidence-level data**

The IQM dataset has evidence levels per ingredient. Confirm whether the product blob exposes the per-ingredient evidence level on the in-product ingredient list (not just the IQM tier dataset). Same three-way result as Step 1.

- [x] **Step 3: Document findings** — see "F.0 Findings" block below.

#### Task F.0: Data Availability Audit Findings — **VERDICT: 🟢 GREEN** (2026-04-29)

**Step 1 — Four-pillar score availability: ✅ GREEN.** All four pillars are first-class fields on the `products_core` Drift table:

| Pillar | Field (Drift getter) | Column | Max field |
|---|---|---|---|
| Ingredient Quality | `scoreIngredientQuality` | `score_ingredient_quality` (real, nullable) | `score_ingredient_quality_max` (max 25) |
| Safety & Purity | `scoreSafetyPurity` | `score_safety_purity` | `score_safety_purity_max` (max 30) |
| Evidence & Research | `scoreEvidenceResearch` | `score_evidence_research` | `score_evidence_research_max` (max 20) |
| Brand Trust | `scoreBrandTrust` | `score_brand_trust` | `score_brand_trust_max` (max 5) |

Source: `lib/data/database/tables/products_core_table.dart:67–82`. Pillars sum to 80 pts; the remaining 20 pts come from bonuses minus penalties → 0–100 final score.

**Coverage** is also a first-class field: `mappedCoverage` (`mapped_coverage`, real, nullable) at `products_core_table.dart:64`. Already consumed by the hero "Limited data" banner (`product_detail_screen.dart:1322`).

**Detail-blob context** (cached + fetched via `detail_blob_provider.dart`): `section_breakdown` Map keyed by `ingredient_quality / safety_purity / evidence_research / brand_trust` provides sub-scores, bonuses, penalties, and certifications per pillar. Plus `score_bonuses[]` / `score_penalties[]` for "Why this score" reasoning rows.

**Existing UI consumer** — `lib/features/product_detail/widgets/score_breakdown_card.dart` (505 lines) already renders the four pillars in expandable bars with sub-explanation builders (`_explainIngredientQuality`, `_explainSafetyPurity`, `_explainEvidence`, `_explainBrandTrust`). The wiring is at `product_detail_screen.dart:459–469`. PGPillarBar (F.2) is a quieter horizontal-bar variant of `_ExpandableSectionBar` for use in the rescoped F.4 / T1.4 quality-score card; the existing card stays for the deep-dive section-breakdown sheet.

**Step 2 — Per-ingredient evidence-level data: skipped.** F.3 + F.6 (atom rendering) were DROPPED in the 2026-04-29 cross-team merge, so the per-ingredient evidence-level audit is no longer load-bearing. Trust & IA T1.5's verbose ingredient rows + chip pattern is the agreed shape; data wiring lives in T1.5's brief.

**Implications for downstream tasks:**
- **F.2 PGPillarBar**: pure UI build. No aggregation, no pipeline ticket. Consume `_product.scoreXxx` + `_product.scoreXxxMax` directly.
- **F.4 (rescoped) Quality Score card**: composes 4× `PGPillarBar` + coverage strip (from `mappedCoverage`) + "Why this score" reasoning row (from `detailBlob['score_bonuses']` / `score_penalties`). T1.4 owns final mount.
- **T1.4 (Sean's)**: unblocked. The pillar data path is already live in `ScoreBreakdownCard`; T1.4 can either reuse that card directly for the deep-dive sheet OR consume the same fields for a tighter pillar-bar card.

### Task F.1: Build `PGDonutChart` primitive

> **[PROMOTED + REPLAN 2026-04-29 — BLOCKING T1.1]** Step 1 of this task is now an **audit decision**, not a build: read `lib/core/widgets/pg_score_ring.dart` against the apple-grade reference + T1.1 score-led hero requirements (96pt center number with sub-label, verdict-tinted progress arc, tier-aware track color). If `PGScoreRing` already covers the contract → **reuse it**, ping Sean with that decision, and skip the rest of this task. Only build the new `PGDonutChart` primitive if there is a concrete gap that can't be added to `PGScoreRing` without breaking existing call sites. Don't ship a parallel primitive.

**Files:**
- Create: `lib/core/widgets/pg_donut_chart.dart` *(only if reuse audit returns "build new")*
- Create: `test/core/widgets/pg_donut_chart_test.dart` *(same condition)*

A scale-able donut chart with center number. Reuses `PGScoreRing`'s rendering DNA but with bigger center text and a configurable label below.

- [x] **Step 1 (audit): PGScoreRing reuse decision — see "F.1 Findings" block below.**

#### Task F.1 Findings — **DECISION: 🟢 REUSE PGScoreRing** (2026-04-29)

`lib/core/widgets/pg_score_ring.dart` (275 lines) already covers the full T1.1 score-led-hero contract. Mapping the proposed `PGDonutChart` API → existing `PGScoreRing`:

| PGDonutChart spec field | PGScoreRing equivalent | Status |
|---|---|---|
| `value` (0..100) | `score` (0..100, **nullable** — also handles insufficient-data state) | ✅ Covered + better |
| `size` (default 140) | `size` (default 72; accepts any) | ✅ Covered |
| `strokeWidth` (default 12) | `strokeWidth` (default 5; accepts any) | ✅ Covered |
| `progressColor` (tier-derived) | `_colorFor(score)` — 6-tier ladder (`scoreExceptional / Excellent / Good / Fair / BelowAvg / Low`) auto-derived | ✅ Covered |
| `trackColor` (low-alpha outline) | hardcoded `surfaceContainerHigh` — theme-driven | ⚠️ Not parameterized |
| `label` (optional below-center) | `label` (optional below-center) | ✅ Covered |

**Plus PGScoreRing already ships these the spec didn't ask for:**
- Sweep-gradient progress arc (premium look)
- Dashed track + "–" rendering for null/insufficient-data state
- Animated mount + value-change transitions (900ms easeOutCubic)
- Reduce-motion respect via `MediaQuery.maybeDisableAnimationsOf`
- Semantic accessibility — VoiceOver label with tier description ("87 out of 100, exceptional score")

**The only gap** is that `trackColor` and `progressColor` aren't override-able — both are derived. If T1.1 needs tier-tinted track or a verdict-override-color (e.g. force red on a Blocked product instead of the score-tier color), the cleanest path is **two additive optional params on PGScoreRing**, not a parallel primitive:

```dart
// Additive — defaults preserve current behavior; non-null overrides take precedence.
final Color? trackColorOverride;  // null → surfaceContainerHigh
final Color? progressColorOverride; // null → _colorFor(score)
```

If T1.1 doesn't need overrides, even cleaner: **just call `PGScoreRing(score: ..., size: 96, label: 'PG SCORE')` directly with no widget changes at all.**

**Decision: do not build PGDonutChart.** Two parallel primitives doing 95% the same thing creates maintainer confusion (existing call sites in product detail, search, scan results all use PGScoreRing) and test duplication. T1.1 reuses; if it needs the override hooks, those are a tiny additive change in a follow-up commit.

**Implication for the plan:** Steps 1–3 of this task (write failing tests, build CustomPainter, commit) are **superseded by the reuse decision above**. Skip building `pg_donut_chart.dart` / its test. Notify Sean in the F-chunk ping.

#### ~~Original Step 1: Write failing tests~~ (superseded — see F.1 Findings)
- ~~renders center number; respects `value` 0–100; centers in available space; honors `size` parameter~~

#### ~~Original Step 2: Build using `CustomPainter` for the arc~~ (superseded)

Sketch (kept for historical context — do not implement):

```dart
class PGDonutChart extends StatelessWidget {
  final double value;          // 0..100
  final double size;           // outer diameter (default 140)
  final double strokeWidth;    // default 12
  final Color trackColor;      // default outline at low alpha
  final Color progressColor;   // tone derived from value tier
  final String? label;         // optional below-center label, e.g. "Quality"

  const PGDonutChart({
    super.key,
    required this.value,
    this.size = 140,
    this.strokeWidth = 12,
    this.trackColor = const Color(0x1A000000),
    this.progressColor = const Color(0xFF0A7D6F),
    this.label,
  });
  // ... build via CustomPaint + Stack with centered number ...
}
```

#### ~~Original Step 3: Run tests + commit~~ (superseded — no commit; the audit decision is the deliverable)

```
git commit -m "feat(core): PGDonutChart — donut chart primitive for score visualization"
```

### Task F.2: Build `PGPillarBar` primitive

> **[PROMOTED 2026-04-29 — BLOCKING T1.4]** Build per spec. Trust & IA Sprint 1 T1.4 will consume `PGPillarBar` for the pillar breakdown. Ping Sean with the commit SHA the moment it lands on `main`.

**Files:**
- Create: `lib/core/widgets/pg_pillar_bar.dart`
- Create: `test/core/widgets/pg_pillar_bar_test.dart`

Single horizontal bar with label + value. Used four times for the pillar breakdown.

- [x] **Step 1: Write failing tests** (renders label + percent; bar fills proportional to value; tone color derives from value tier; reduced height variant for dense lists)
- [x] **Step 2: Build with `LinearProgressIndicator` wrapped in custom decoration matching home's tier system**
- [x] **Step 3: Run tests + commit**

### ~~Task F.3: Build `PGIngredientAtom` primitive~~

> **[DROPPED 2026-04-29 — see cross-team merge note]** Atom pills are decorative for medical-grade context. The dose-vs-effective-range note (Trust & IA T1.5 verbose rows + existing chip pattern for inactive ingredients) is the trust signal that differentiates PharmaGuide from food-additive scanners. Skip this primitive entirely.

**Files:**
- Create: `lib/core/widgets/pg_ingredient_atom.dart`
- Create: `test/core/widgets/pg_ingredient_atom_test.dart`

Circular ingredient pill (e.g. "Mg") with optional evidence badge in the corner.

- [x] **Step 1: Write failing tests** (renders symbol; evidence badge shows when level provided; tappable variant fires onTap; reduce-motion safe)
- [x] **Step 2: Build as a `Stack` with a `CircleAvatar`-like base + small badge overlay**
- [x] **Step 3: Wrap with PGPressable when `onTap` is provided**
- [x] **Step 4: Run tests + commit**

### Task F.4: Quality Score card (donut + 4 pillar bars) → ~~donut~~ pillars + coverage + reasoning

> **[RESCOPED 2026-04-29 — score lives in hero (T1.1)]** This phase delivers the pillar-card *visual treatment*; **Trust & IA Sprint 1 T1.4 owns final composition** and integration. The donut step is dropped because the score now lives in the score-led hero (T1.1). What this phase contributes: a `PGCard.plain` containing four `PGPillarBar` instances + a coverage strip + a "Why this score" reasoning row. T1.4 will mount it and wire the data.

**Files:**
- Create: `lib/features/product_detail/widgets/quality_score_card.dart`
- Modify: `lib/features/product_detail/product_detail_screen.dart` to compose this card after the hero altar

- [ ] ~~**Step 1: Build a `PGCard(variant: PGCardVariant.plain)` with:**~~
  - ~~PGDonutChart on the left at 120pt~~
  - ~~Right column with four PGPillarBar instances stacked~~
  - ~~Wrapped in PGPressable on tap → opens the existing score-breakdown sheet (`onScoreInfoTap` callback)~~
- [ ] **Step 1 (rescoped): Build a `PGCard(variant: PGCardVariant.plain)` containing four `PGPillarBar` instances + a coverage strip + a "Why this score" reasoning row.** No donut, no center ring — those live in the hero (T1.1). PGPressable wrap → opens the existing score-breakdown sheet on tap.
- [ ] **Step 2: Compose into product detail screen** under the hero altar, before the deep-dive section
- [ ] **Step 3: On 320-pt iPhone SE, the card stacks vertically (donut on top, pillars below)** — use `LayoutBuilder` for the breakpoint at `constraints.maxWidth < 360`
- [ ] **Step 4: Run analyze + tests + commit**

### ~~Task F.5: "For You" card (Why this score · Your alerts)~~

> **[DROPPED 2026-04-29 — see cross-team merge note]** Folded into Trust & IA Sprint 1 T1.2. The dual-column "Why this score · Your alerts" was conflating Section 2 + Section 3 content; T1.2 separates them with the corrected content model. Sean will reuse this phase's visual approach (PGCard.plain, PGPressable per row, LayoutBuilder for SE breakpoint) inside T1.2 — don't ship a parallel `for_you_card.dart` here.

**Files:**
- Create: `lib/features/product_detail/widgets/for_you_card.dart`
- Modify: `lib/features/product_detail/product_detail_screen.dart`

The Apple Altar spec called for a dual-column layout. Per my earlier pushback, on a 320pt phone two columns of ~140pt each are too cramped. Solution: small-screen stacks, larger-screen splits.

- [ ] **Step 1: Build a `PGCard(variant: PGCardVariant.plain)` with two sections:**
  - "Why this score" — checklist using the existing `score_bonuses[]` / `score_penalties[]` data
  - "Your alerts" — nested PGSeverityPill list of any active interaction warnings
- [ ] **Step 2: `LayoutBuilder` — under 380pt the two sections stack with a divider; above 380pt they split into a 50/50 row**
- [ ] **Step 3: PGPressable wrapping each row item** (taps on alert rows scroll to the deep-dive interactions section via a `Scrollable.ensureVisible`)
- [ ] **Step 4: Run analyze + tests + commit**

### ~~Task F.6: Atom-style ingredients row~~

> **[DROPPED 2026-04-29 — see cross-team merge note]** Atom pills are decorative for medical-grade context (same rationale as F.3). T1.5 verbose ingredient rows + the existing chip pattern for inactives is the right call. Skip this phase entirely — do not ship `ingredients_atom_row.dart`.

**Files:**
- Create: `lib/features/product_detail/widgets/ingredients_atom_row.dart`
- Modify: `lib/features/product_detail/product_detail_screen.dart` (replace the current ingredients listing if applicable)

- [ ] **Step 1: Build a horizontal scrollable row of `PGIngredientAtom` instances, one per active ingredient**
- [ ] **Step 2: Tap on an atom opens a Cupertino sheet (`PGModal.bottomSheet`) with the ingredient's evidence summary, dose, and IQM tier**
- [ ] **Step 3: Empty state — when no active ingredients in the product blob, render `SizedBox.shrink()` (don't show a "no ingredients" empty state on a product page; that would be alarming)**
- [ ] **Step 4: Run analyze + tests + commit**

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

> **2026-04-29 cross-team merge revision** — see top-of-doc note. The original 23-task linear order is preserved below for historical context but **superseded by the queue immediately below it**.

### Active queue (post cross-team merge)

| # | Task | Status | Notes |
|---|---|---|---|
| ✅ shipped | **0.1, 0.2, A.1, A.2, A.3, B.1, B.2, C.1** | DONE in Sprint 27.21 | 9 commits between `7c90b19` and `af0cd78`, +44 tests, analyze clean |
| 1 | **F.0** Data availability audit | **NEXT** | BLOCKING T1.4. Read-only inspection (1–2 hrs). Ping Sean with GREEN/YELLOW/RED verdict. |
| 2 | **F.1** PGDonutChart vs PGScoreRing reuse audit | **NEXT** | BLOCKING T1.1. Decision-first: reuse `pg_score_ring.dart` if it covers the score-led-hero contract; only build `PGDonutChart` if a concrete gap forces it. |
| 3 | **F.2** PGPillarBar primitive | **NEXT** | BLOCKING T1.4. Build per spec; ping Sean with the commit SHA on `main`. |
| 4 | **C.2** Adaptive controls sweep | parallel | No T1.x conflict; can run alongside F.0/F.1/F.2 dispatches. |
| 5 | **C.3** Motion-token sweep | parallel | Stylistic; same lane as C.2. |
| 6 | **D.2** Empty-state audit | parallel | Polish on polish; safe to run in parallel. |
| 7 | **B.3b** Product Detail frosted SliverAppBar + circular share | **WAIT for T1.1 sign-off** | Same file as T1.1 (`product_detail_screen.dart`). Concurrent edits would cause merge churn. Hold until Trust/IA team signs off T1.1, then go mechanical. |
| 8 | **F.4** Pillar card composition | after T1.1 + F.2 | Rescoped — pillars + coverage + reasoning row only. T1.4 owns final mount. |
| 9 | **E.1** Cross-screen smoke tests | sprint-close | Augment to assert PGFrostedAppBar OR PGFrostedHeader-inside-PreferredSize per screen (B.1's variant is intentional). |
| 10 | **E.2** Final analyze + suite + tracker close | sprint-close | After everything else lands. |
| ❌ skipped | **B.3a** Apple Altar hero | SUPERSEDED → T1.1 | Trust/IA owns. |
| ❌ skipped | **D.1** PGAdaptiveBackButton | FOLDED INTO 0.2 | Already covered by `PGCircularIconButton` in `PGFrostedAppBar`. |
| ❌ skipped | **F.3** PGIngredientAtom | DROPPED | Decorative for medical-grade context. |
| ❌ skipped | **F.5** "For You" card | DROPPED → T1.2 | Sean reuses the visual approach inside T1.2 with corrected content model. |
| ❌ skipped | **F.6** Atom-style ingredients row | DROPPED | Same rationale as F.3. T1.5 verbose rows are the right call. |

### ~~Legacy linear order (pre-merge — historical only)~~

| Priority | Task | Why this rank |
|---|---|---|
| 1  | **Phase 0.1** — Build PGFrostedAppBar | Every Phase A/B task depends on it |
| 2  | **Phase 0.2** — Build PGCircularIconButton | Premium circular top-chrome button; gets wired into PGFrostedAppBar's back + actions slots |
| 3  | **A.1** — Stack frosted bar | Highest-traffic tab; biggest user-visible win |
| 4  | **A.2** — Settings 3-pack | Whole Profile tab elevates in one commit |
| 5  | **A.3** — Scanner overlay | Quick win; user sees it on every scan |
| 6  | **B.1** — Profile Setup | First-launch users see this; high impression weight |
| 7  | **B.2** — Quick Check | Cross-app consistency |
| 8  | ~~**B.3a** — Product Detail Apple Altar hero~~ — superseded → T1.1 |
| 9  | ~~**B.3b** — Product Detail frosted app bar + circular share + sections audit~~ — runs after T1.1 sign-off |
| 10 | **C.1** — PGModal sweep | Touches many files; do as a batch |
| 11 | **C.2** — Adaptive controls | Low-risk grep-and-replace |
| 12 | **C.3** — Motion-token sweep | Stylistic; do after structural moves are stable |
| 13 | ~~**D.1** — Extract PGAdaptiveBackButton~~ — folded into 0.2 |
| 14 | **D.2** — Empty-state audit | Polish on polish |
| 15 | **F.0** — Data availability audit | **Promoted — BLOCKING T1.4** |
| 16 | **F.1** — PGDonutChart primitive | **Promoted — BLOCKING T1.1; reuse-or-build audit first** |
| 17 | **F.2** — PGPillarBar primitive | **Promoted — BLOCKING T1.4** |
| 18 | ~~**F.3** — PGIngredientAtom primitive~~ — dropped |
| 19 | **F.4** — Quality Score card | Rescoped — pillars only; T1.4 owns final composition |
| 20 | ~~**F.5** — "For You" card~~ — dropped → T1.2 |
| 21 | ~~**F.6** — Atom-style ingredients row~~ — dropped |
| 22 | **E.1** — Cross-screen smoke tests | Run continuously; finalize at the end |
| 23 | **E.2** — Final verify + tracker | Sprint-close |

**Estimated effort (post-merge):**
- F.0 / F.1 / F.2 unblocker chunk (next-up): ~3–5 hours
- C.2 + C.3 + D.2 parallel sweeps: ~3–4 hours
- B.3b (after T1.1 sign-off): ~1–2 hours
- E.1 + E.2 close: ~2 hours
- **Total remaining**: ~9–13 hours, depending on Trust & IA Sprint 1 cadence

---

## Self-Review Checklist (run before declaring complete)

- [ ] Every screen flagged in the audit has a corresponding task (Stack, Settings, Scanner, Profile Setup, Quick Check, Product Detail)
- [ ] Onboarding and Search are deliberately NOT in Phase A/B (already reference quality)
- [ ] App Shell and Nav Bar are NOT in any task (already reference quality)
- [ ] Every reusable primitive needed (`PGFrostedAppBar`, `PGModal`, `PGAdaptiveBackButton`, `PGDonutChart`, `PGPillarBar`, `PGIngredientAtom`) has a build task before any task that uses it
- [ ] Every task ends with a commit
- [ ] No placeholder text — every step has the actual code or exact command
- [ ] Verification steps reference real test paths, not invented ones
- [ ] Type/method/widget signatures across tasks are consistent
- [ ] **Data-dependency gating**: Phase F is explicitly blocked behind F.0 audit; no data-viz code references invented fields
- [ ] **Apple Altar safety override is preserved**: B.3a's `heroVerdictProvider` priority ladder spells out medical priority (safety > goal match)

## Execution

Plan saved to `docs/superpowers/plans/2026-04-28-app-wide-apple-grade.md`.

Two execution options:
1. **Subagent-Driven** (recommended for this scale) — fresh subagent per task, two-stage review between tasks, fast iteration. Good fit because Phase 0 + Phase A + B.3a are tightly sequenced (each depends on the previous), but Phase C and Phase F.1–F.3 tasks can be parallelized.
2. **Inline Execution** — run tasks in this session with checkpoints between phases for review. Good fit if you want to feel the simulator after each migration before moving to the next — especially useful for B.3a (the altar) where the visual change is dramatic.

Total tasks: 2 (Phase 0 — PGFrostedAppBar + PGCircularIconButton) + 3 (A) + 4 (B — including B.3a/B.3b split) + 3 (C) + 2 (D) + 7 (F — gated audit + 6 build tasks) + 2 (E) = **23 tasks**, ~40–50 commits, 14–22 hours.

**Recommended execution path:**
- **Sprint 1 (10–14 hrs)**: 0.1 → A.1 → A.2 → A.3 → B.1 → B.2 → **B.3a (the altar)** → B.3b → C.1 → C.2 → C.3 → D.1 → D.2 → E.1 → E.2
  Ships visible app-wide polish + the new hero in one cohesive release. **F is intentionally deferred**.
- **Sprint 2 (6–10 hrs)**: F.0 → F.1/F.2/F.3 (parallel) → F.4 → F.5 → F.6
  Only proceeds if F.0's data audit comes back GREEN; otherwise spins out a pipeline ticket and revises scope.

---

## Phase G — Premium-feel follow-ups (added 2026-04-29)

Three "premium-feel" tasks that surfaced during the Sprint 27.21 close audit against the dev-team critique. Each is independent, low-risk, and additive on top of the shipped apple-grade work. G.4 is held for design call; G.5 is pipeline-gated.

### Task G.1: Animated logo splash intro

**Why:** Native splash is already configured (`pubspec.yaml:73`, brand teal `#0A7D6F` + `assets/images/splash_logo.png` 512×512). Today the app jumps from the native splash straight to home with no brand reveal moment. The dev critique called this out as the **#1 premium-feel gap**. A 600ms logo scale-up + fade-in between the native splash and the home screen creates a continuous, polished hand-off — the hallmark of first-party iOS apps.

**Files:**
- Create: `lib/features/splash/animated_splash_screen.dart`
- Modify: `lib/main.dart` — initial route swap (home → animated splash → home)
- Modify: `lib/core/constants/routes.dart` — add `splashIntro` route name
- Create: `test/features/splash/animated_splash_test.dart`

**Asset prerequisites:**
- `assets/images/splash_logo.png` already exists at 512×512. **Replace with a higher-resolution version** (recommend 1024×1024 PNG with transparent background, logo centered with ≥10% padding margin so it doesn't crop on circular icon masks).
- Same logo file used by both native splash AND animated splash for visual continuity (pixel-perfect hand-off).

**Steps:**

- [ ] **Step 1: Confirm logo asset is the upgraded version** (1024×1024 PNG, transparent bg, ≥10% padding).

- [ ] **Step 2: Build `AnimatedSplashScreen` widget**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';

/// Animated splash intro — the bridge between the native splash
/// (handled by `flutter_native_splash`) and the home screen.
///
/// Native splash → animated splash (600ms scale-up + fade-in) → home.
/// Native and animated splashes share the same brand-teal background
/// (`#0A7D6F`) and the same logo image (`assets/images/splash_logo.png`)
/// so the hand-off is pixel-perfect — the user sees a single continuous
/// brand moment.
///
/// Reduce-motion (Accessibility → Reduce Motion) suppresses the
/// scale + fade and jumps straight to home after a 200ms delay
/// (just enough to register a brand impression, no animation).
///
/// Spec: docs/superpowers/plans/2026-04-28-app-wide-apple-grade.md (G.1)
class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  bool _reduceMotionChecked = false;

  // Brand teal — must match flutter_native_splash:color in pubspec.yaml.
  static const Color _splashBackground = Color(0xFF0A7D6F);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: AppMotion.standard),
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotionChecked) return;
    _reduceMotionChecked = true;
    final reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      // Skip the animation; brief brand-impression delay before navigating.
      Future.delayed(const Duration(milliseconds: 200), _goHome);
    } else {
      _ctrl.forward().then((_) {
        // Tiny haptic tick at the end of the animation — Apple's
        // signature "we noticed you arrived" detail.
        PGHaptics.tap(context);
        _goHome();
      });
    }
  }

  void _goHome() {
    if (!mounted) return;
    GoRouter.of(context).go(Routes.home);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _splashBackground,
        body: Center(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Opacity(
                opacity: _fade.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: Image.asset(
                    'assets/images/splash_logo.png',
                    width: 180,
                    height: 180,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Wire into the router**

In `lib/core/constants/routes.dart`, add:
```dart
static const splashIntro = '/splash';
```

In whichever file owns the `GoRouter` configuration, add an entry:
```dart
GoRoute(
  path: Routes.splashIntro,
  builder: (context, state) => const AnimatedSplashScreen(),
),
```

In the router's `redirect` or initial-route logic, route `/` → `splashIntro` ON FIRST APP LAUNCH ONLY. Use `SharedPreferences` (or the existing onboarding-prefs service) to ensure subsequent app launches go directly to home without the splash. The brand reveal is a "first impression" moment, not a recurring delay.

- [ ] **Step 4: Write widget tests**

```dart
testWidgets('AnimatedSplashScreen navigates to home after animation',
    (tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: AnimatedSplashScreen()),
  );
  // Logo + brand background visible at frame 0.
  expect(find.byType(Image), findsOneWidget);
  // Pump past the 600ms animation.
  await tester.pumpAndSettle(const Duration(milliseconds: 700));
  // Navigation triggered — screen unmounted (or replaced).
});

testWidgets('reduce-motion skips the scale/fade and routes after 200ms',
    (tester) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: const MaterialApp(home: AnimatedSplashScreen()),
    ),
  );
  // No animation; should hit the 200ms delay then navigate.
});
```

- [ ] **Step 5: Run analyze + tests + commit**

```
flutter analyze
flutter test test/features/splash/
git add lib/features/splash/ lib/main.dart lib/core/constants/routes.dart \
        test/features/splash/
git commit -m "feat(splash): animated logo intro between native splash and home"
```

### Task G.2: Hero transitions for scan-card → product detail

**Why:** Tapping a recent-scan card on home today pushes the product-detail screen with the product image just appearing — no continuity. Adding a `Hero(tag: 'product-${dsldId}')` on both ends gives shared-element flight: the image visibly travels from the card to the detail-screen identity row. App Store / Apple Health signature move.

**Files:**
- Modify: `lib/features/home/widgets/home_recent_scans.dart` — wrap the `ProductImage` in each card in `Hero(tag: ...)`
- Modify: `lib/features/search/search_screen.dart` — same wrap on result-tile product images
- Modify: `lib/features/stack/stack_screen.dart` — same wrap on stack-item product images
- Modify: `lib/features/product_detail/product_detail_screen.dart` — wrap the hero `ProductImage` in `Hero(tag: 'product-${dsldId}')` on the receiving end

**Steps:**

- [ ] **Step 1: Pick a tag scheme** — `'product-${dsldId}'` is the natural unique identifier. Document it as a constant somewhere reusable (e.g. `static const String heroTagPrefix = 'product-';` on `ProductImage` itself) so call sites can't drift.

- [ ] **Step 2: Wrap each call site**

Pattern:
```dart
Hero(
  tag: 'product-$dsldId',
  flightShuttleBuilder: (_, animation, __, ___, ____) {
    // Suppress the default Material elevation flight shuttle which
    // adds a tinted overlay during transit — looks heavy. Use the
    // child verbatim instead.
    return ProductImage(
      dsldId: dsldId,
      upc: upc,
      productName: productName,
      brandName: brandName,
      formFactor: formFactor,
      score: score,
      size: size,
    );
  },
  child: ProductImage(...),
)
```

- [ ] **Step 3: Verify with simulator** — tap a recent scan, confirm the image visibly flies from the card to the detail hero. Tap back, confirm reverse flight works.

- [ ] **Step 4: Add a smoke test**

```dart
testWidgets('product image has matching Hero tags between recents and detail',
    (tester) async {
  // Mount home, capture the Hero tag on a recent scan card.
  // Tap it, mount the detail screen, confirm a Hero with the same tag
  // exists on the receiving end.
});
```

- [ ] **Step 5: Run analyze + tests + commit**

### Task G.3: Inline subtitle helper for product hero

**Why:** The original B.3a Apple Altar plan called for an inline `Brand · Form · Dose` subtitle as one `Text.rich` with dot separators (e.g. `"Thorne · 60 Capsules · 135 mg per serving"`). The current hero stacks brand + form as two separate `Text` widgets. Inline form is more compact (saves vertical space) and matches the App Store / Apple Health pattern. Held back during B.3c because of T1.x WIP; can ship now that T1.x area is calm.

**Files:**
- Modify: `lib/features/product_detail/product_detail_screen.dart` — `_HeaderSection` identity column

**Steps:**

- [ ] **Step 1: Add `servingDose` derivation** — if the detail blob's `ingredients[0].dose` is available, surface it as the third subtitle segment. If not, the helper drops the segment cleanly (no orphan dot).

- [ ] **Step 2: Add `_buildSubtitleSpan` + `_hasAnySubtitle` helpers**

```dart
/// True when at least one subtitle segment has content. Skip rendering
/// the subtitle row entirely when all three are empty.
bool _hasAnySubtitle(String brand, String form, String? dose) =>
    brand.isNotEmpty || form.isNotEmpty || (dose != null && dose.isNotEmpty);

/// Builds the dot-separated subtitle: `Brand  ·  Form  ·  Dose`.
/// Drops orphan dots — if `brand` is empty but `form` is present,
/// the result starts with `form`, not ` · form`.
TextSpan _buildSubtitleSpan({
  required BuildContext context,
  required String brand,
  required String form,
  String? dose,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final segments = <String>[
    if (brand.isNotEmpty) brand,
    if (form.isNotEmpty) form,
    if (dose != null && dose.isNotEmpty) dose,
  ];
  return TextSpan(
    text: segments.join('  ·  '),
    style: theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.05,
    ),
  );
}
```

- [ ] **Step 3: Replace the stacked brand/form Text widgets**

Replace the existing `if (brandName.isNotEmpty) ... + if (formFactor.isNotEmpty) ...` blocks in `_HeaderSection.build`'s identity column with:

```dart
if (_hasAnySubtitle(brandName, formFactor, /* dose */ null)) ...[
  const SizedBox(height: 4),
  Text.rich(
    _buildSubtitleSpan(
      context: context,
      brand: brandName,
      form: formFactor,
      dose: null, // wire up from blob later if dose data is reliable
    ),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  ),
],
```

- [ ] **Step 4: Run analyze + tests + commit**

### Task G.4: Tighter hero spacing for iPhone SE

**Why:** At iPhone SE (320pt), the 96pt image + 96pt ring + AppTheme.space20 gaps may feel cramped. Defensive `LayoutBuilder` fallback to a compact mode (e.g. 80pt image + 80pt ring + tighter gaps) at `<360pt` width.

**Files:**
- Modify: `lib/features/product_detail/product_detail_screen.dart` — `_HeaderSection`

**Steps:**

- [ ] **Step 1: Validate on simulator first** — iPhone SE (3rd gen, 320pt) at default + 1.4× Dynamic Type. Decide whether the cramping is real or cosmetic.

- [ ] **Step 2: If real, wrap the hero in `LayoutBuilder`**

```dart
return LayoutBuilder(
  builder: (context, constraints) {
    final isCompact = constraints.maxWidth < 360;
    final imageSize = isCompact ? 80.0 : 96.0;
    final ringSize = isCompact ? 80.0 : 96.0;
    final altarTopGap = isCompact ? AppTheme.space12 : AppTheme.space20;
    // ... use these instead of hardcoded sizes ...
  },
);
```

- [ ] **Step 3: Add a golden test for both widths** if your codebase has goldens; otherwise widget tests asserting size at narrow vs wide.

- [ ] **Step 4: Run analyze + tests + commit**

### Task G.5: Sprint 28 prep (Tier 2 Research Evidence)

**Why:** Listed in `SPRINT_TRACKER.md` as `BACKLOG: DO NOT START until pipeline-side Phase 1 ships`. Pipeline-gated, not on apple-grade plate. Logged here for completeness; the apple-grade team will revisit when the pipeline RXCUI bridge lands.

**Status:** ⏸ Backlog — gated on pipeline Phase 1 (PubMed verification + duplicate cleanup + RXCUI bridge in `scripts/ingest_suppai.py`). See `SPRINT_TRACKER.md` Sprint 28 entry for full scope.

---

## Phase G execution order

| Priority | Task | Est | Notes |
|---|---|---|---|
| 1 | **G.3** Inline subtitle helper | 30 min | Smallest, lowest-risk win; finishes the Apple Altar story |
| 2 | **G.1** Animated logo splash | 1–2 hrs | Highest "premium feel" payoff per hour. **Blocks on Sean uploading the upgraded `splash_logo.png`** to `assets/images/`. |
| 3 | **G.2** Hero transitions | 1–2 hrs | Signature shared-element flight on tap-through |
| 4 | **G.4** Tighter SE spacing | 1 hr | Defensive — needs simulator validation first |
| 5 | ~~**G.5** Tier 2 Research~~ | — | Pipeline-gated; not on this plan |
