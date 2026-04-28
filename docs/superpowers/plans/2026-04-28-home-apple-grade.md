# Home Apple-Grade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take the PharmaGuide home screen from "good redesign" to first-party Apple-grade by fixing the bugs from the verification audit and adding the missing physics layer (haptics, press feedback, frosted scroll-edge search, snap-carousel Recents, large-title chrome, platform-adaptive primitives).

**Architecture:** Layer in three passes. (A) Fix the seven defects in the existing redesign so the foundation is sound. (B) Build two reusable primitives — `PGPressable` and a `PGFrostedHeader` slot — and adopt them across home. (C) Replace the home `CustomScrollView` shell with proper iOS chrome: collapsing hero, scroll-aware frosted search, snap-paginated Recents, platform-adaptive refresh + sheets. The existing `StackSafetyScorer`, `PGCard`, `PGShimmerBox`, `PGHaptics`, `AppMotion`, and `AppTheme` stay — we use what's already there.

**Tech Stack:** Flutter 3.41 stable, Riverpod, Material 3 + Cupertino, `BackdropFilter`, `SliverPersistentHeader`, `PageController`, `flutter/services.dart` haptics.

**Baseline state (2026-04-28):** Sprint 27.18 redesign shipped with uncommitted changes on `main`. `flutter analyze` clean, 14 home/stack tests passing. Two HIGH bugs (first-launch reactivity, Show all cliff at 10) and several MEDIUM/LOW issues identified in the verification report at `INITIATIVE_PRODUCT_TRUST_AND_IA.md` follow-up.

**Out of scope (deliberate):**
- "Today" smart insight (user removed — would duplicate Stack Health)
- Streak / consistency pill (user removed)
- Time-of-day-stack greeting ("Time for your AM stack" — user removed)
- Replacement of `StackSafetyScorer` with a new engine (separate sprint 27.20)
- Category rail (already removed)
- "AM stack" copy anywhere

**Branch policy:** All work on `main` with one commit per task (matches existing project convention). Each task ends with `flutter analyze` + targeted test run before commit.

---

## Phase A — Fix the seven defects (foundation)

Fix the bugs from the verification report **before** layering motion/material work on top. Otherwise we build polish on top of a broken provider.

### Task A1: Make `_isFirstLaunchHomeProvider` reactive to stack changes

**Why:** The provider uses `ref.read` (no subscription). After a first-launch user adds their first stack item or completes their first scan, home stays in collapsed mode until the screen rebuilds from scratch. This breaks the exact moment that matters.

**Files:**
- Modify: `lib/features/home/home_screen.dart:17-23`
- Modify: `test/features/home/home_screen_test.dart` (add reactivity test)

- [ ] **Step 1: Read existing test file to understand fixture pattern**

Run: `Read tool on test/features/home/home_screen_test.dart` (full file)
Expected: see how the in-memory user DB is built and how the activeStack fixture is set up.

- [ ] **Step 2: Write the failing reactivity test**

Add to `test/features/home/home_screen_test.dart` (after existing tests, inside the same `group`):

```dart
testWidgets('HomeScreen exits first-launch mode when stack gains an item',
    (tester) async {
  final container = ProviderContainer(overrides: [
    // start with empty stack + empty scans
    activeStackProvider.overrideWith((ref) => Stream<List<StackEntry>>.value(<StackEntry>[])),
    userDatabaseProvider.overrideWith((ref) => _emptyUserDb),
  ]);
  addTearDown(container.dispose);

  // First build: should be first-launch (no Stack Health card)
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Stack health'), findsNothing,
      reason: 'first-launch should hide Stack Health');

  // Now invalidate the provider, simulating "user added stack item then home rebuilt"
  container.invalidate(_isFirstLaunchHomeProvider);
  // After fix, providers re-eval should also fire from stack mutation alone — but
  // the minimum bar is: invalidate works AND build reflects new state.
  await tester.pumpAndSettle();

  // We can't easily mutate the stream-based override mid-test, so this test asserts
  // the provider is at least invalidate-driven. Full reactivity is asserted by
  // a unit test in Step 4 below.
});
```

(Note: full reactivity is unit-tested in step 4. The widget test above only asserts invalidation works.)

- [ ] **Step 3: Run test, expect existing tests still pass and new test passes (or expose the issue)**

Run: `flutter test test/features/home/home_screen_test.dart`
Expected: 7 of 8 pass; new test may fail or pass depending on timing — what we actually need is the unit test in Step 4.

- [ ] **Step 4: Write unit test for provider reactivity**

Create: `test/features/home/providers/is_first_launch_provider_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ... imports for activeStackProvider, userDatabaseProvider, _isFirstLaunchHomeProvider
//     (provider must be made @visibleForTesting — see Step 6)

void main() {
  test('isFirstLaunchHome flips to false when stack becomes non-empty', () async {
    final stackController = StreamController<List<StackEntry>>.broadcast();
    final container = ProviderContainer(overrides: [
      activeStackProvider.overrideWith((ref) => stackController.stream),
      userDatabaseProvider.overrideWith((ref) => FakeUserDb(scans: [])),
    ]);
    addTearDown(() {
      stackController.close();
      container.dispose();
    });

    // Initial: empty stack, empty scans → true
    stackController.add(<StackEntry>[]);
    expect(await container.read(isFirstLaunchHomeProvider.future), true);

    // Stack gains item → must re-evaluate to false
    stackController.add([_fakeStackEntry()]);
    // Force the future provider to re-resolve — with ref.watch this happens
    // automatically; with ref.read it does not.
    await Future<void>.delayed(Duration.zero);
    expect(await container.read(isFirstLaunchHomeProvider.future), false);
  });
}
```

- [ ] **Step 5: Run unit test, expect it to FAIL with current `ref.read` implementation**

Run: `flutter test test/features/home/providers/is_first_launch_provider_test.dart`
Expected: FAIL — provider does not re-evaluate when stack stream emits.

- [ ] **Step 6: Fix the provider in `home_screen.dart:17-23`**

Replace:

```dart
final _isFirstLaunchHomeProvider = FutureProvider.autoDispose<bool>((ref) async {
  final userDb = ref.read(userDatabaseProvider);
  final stack = await ref.read(activeStackProvider.future);
  if (stack.isNotEmpty) return false;
  final scans = await userDb.getRecentScans(limit: 1);
  return scans.isEmpty;
});
```

With:

```dart
@visibleForTesting
final isFirstLaunchHomeProvider = FutureProvider.autoDispose<bool>((ref) async {
  // ref.watch subscribes the provider to changes — required for reactivity
  // when the user's first scan or first stack item lands.
  final stack = await ref.watch(activeStackProvider.future);
  if (stack.isNotEmpty) return false;
  final userDb = ref.watch(userDatabaseProvider);
  final scans = await userDb.getRecentScans(limit: 1);
  return scans.isEmpty;
});
```

Update line 40: `ref.watch(_isFirstLaunchHomeProvider)` → `ref.watch(isFirstLaunchHomeProvider)`

Add at the top of the file: `import 'package:flutter/foundation.dart' show visibleForTesting;`

- [ ] **Step 7: Re-run unit test — expect PASS**

Run: `flutter test test/features/home/providers/is_first_launch_provider_test.dart`
Expected: PASS.

- [ ] **Step 8: Run full home test suite — expect all 8 tests pass**

Run: `flutter test test/features/home/home_screen_test.dart test/features/home/providers/is_first_launch_provider_test.dart`
Expected: ALL PASS.

- [ ] **Step 9: Run analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add lib/features/home/home_screen.dart \
  test/features/home/home_screen_test.dart \
  test/features/home/providers/is_first_launch_provider_test.dart
git commit -m "fix(home): make isFirstLaunchHome reactive to stack/scan changes

ref.read inside FutureProvider doesn't subscribe, so first-launch users
stayed in collapsed home after their first scan/stack add until rebuild.
Switch to ref.watch + add unit test for stream-driven re-evaluation."
```

---

### Task A2: Lower "Show all" threshold from 10 to 5 in Recents

**Why:** Users with 5–9 scans currently can't open the bottom sheet at all. The 10-cliff hides the action.

**Files:**
- Modify: `lib/features/home/widgets/home_recent_scans.dart:62-65`
- Modify: `test/features/home/home_screen_test.dart` (add count-threshold test)

- [ ] **Step 1: Write failing test for threshold = 5**

Add to existing test file:

```dart
testWidgets('HomeScreen shows "Show all" when 5+ recent scans exist',
    (tester) async {
  final fakeScans = List.generate(5, (i) => _fakeScan(i));
  // ... build container with fakeScans ...
  await tester.pumpWidget(...);
  await tester.pumpAndSettle();
  expect(find.text('Show all'), findsOneWidget);
});

testWidgets('HomeScreen hides "Show all" when fewer than 5 recent scans',
    (tester) async {
  final fakeScans = List.generate(4, (i) => _fakeScan(i));
  // ... build container with fakeScans ...
  await tester.pumpWidget(...);
  await tester.pumpAndSettle();
  expect(find.text('Show all'), findsNothing);
});
```

- [ ] **Step 2: Run test — expect FAIL on the 5-threshold case**

Run: `flutter test test/features/home/home_screen_test.dart`
Expected: new tests fail because current threshold is `>= 10`.

- [ ] **Step 3: Fix the threshold**

In `home_recent_scans.dart:62-65`, replace `scans.length >= 10` (both occurrences) with `scans.length >= 5`. Also update the doc comment near the provider definition (line 46 region) to say "max 25, surfaced when ≥5".

- [ ] **Step 4: Run tests — expect PASS**

Run: `flutter test test/features/home/home_screen_test.dart`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/widgets/home_recent_scans.dart \
  test/features/home/home_screen_test.dart
git commit -m "fix(home): lower 'Show all' threshold to 5 recent scans

Users with 5-9 scans previously couldn't access the full-list bottom sheet.
Threshold moves from >= 10 to >= 5; test coverage added at boundary."
```

---

### Task A3: Fix shimmer width-shift in Recents loading state

**Why:** Loading row uses `Row + Expanded × 3` (~124px wide on iPhone 14). Real cards render at fixed 156px in a horizontal `ListView.separated`. When data loads, every card visibly jumps wider. Skeletons must be **shape-preserving** to count as a real solution.

**Files:**
- Modify: `lib/features/home/widgets/home_recent_scans.dart:92-116`

- [ ] **Step 1: Replace `_buildLoadingState` with shape-preserving variant**

In `home_recent_scans.dart`, replace lines 92–116 with:

```dart
/// Shown while the DB query is in flight. Three shimmer cards at the EXACT
/// width of the real card (156px) inside a horizontal ListView, so when data
/// lands there is zero width-shift — only an opacity crossfade.
static Widget _buildLoadingState() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PGSectionHeader(
        title: 'Recent scans',
        subtitle: 'Your last checked products',
        padding: EdgeInsets.zero,
      ),
      const SizedBox(height: AppTheme.space12),
      SizedBox(
        height: 210,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, __) => const SizedBox(
            width: 156,
            child: PGShimmerCard(height: 210),
          ),
        ),
      ),
    ],
  );
}
```

- [ ] **Step 2: Confirm `PGShimmerCard` accepts only `height` (it does — see `pg_shimmer_box.dart:83-95`).** No changes needed there.

- [ ] **Step 3: Run analyze**

Run: `flutter analyze lib/features/home/widgets/home_recent_scans.dart`
Expected: `No issues found!`

- [ ] **Step 4: Manual smoke test**

Run: `flutter run` on iPhone simulator. Open home with empty cache so Recents loads. Visually confirm no card-width jump. (If automating, add a golden test — out of scope for this task.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/widgets/home_recent_scans.dart
git commit -m "fix(home): shape-preserving shimmer in Recents loading state

Replace Expanded x3 row with a 156px-wide horizontal ListView matching
the real card width — eliminates the width-jump when data lands."
```

---

### Task A4: Delete dead `home_category_rail.dart`

**Why:** File still in `lib/features/home/widgets/` but no longer imported anywhere. Misleads next dev. The category rail removal was a Sprint 27.18 deliverable; the file should have been deleted with it.

**Files:**
- Delete: `lib/features/home/widgets/home_category_rail.dart`

- [ ] **Step 1: Confirm zero imports**

Run: `cd "/Users/seancheick/PharmaGuide ai" && grep -rn "home_category_rail\|HomeCategoryRail" lib/ test/`
Expected: only the file itself appears, or empty.

- [ ] **Step 2: Delete**

Run: `rm "/Users/seancheick/PharmaGuide ai/lib/features/home/widgets/home_category_rail.dart"`

- [ ] **Step 3: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add -A lib/features/home/widgets/
git commit -m "chore(home): remove dead home_category_rail.dart

Category rail was removed from the screen in Sprint 27.18 but the file
remained — orphan widget now deleted."
```

---

### Task A5: Extract `_timeAgo()` to shared helper

**Why:** Identical implementation duplicated in `_RecentScanCard` (~225–231) and `_RecentScanListTile` (~488–494). Will drift on next edit.

**Files:**
- Create: `lib/core/utils/relative_time.dart`
- Create: `test/core/utils/relative_time_test.dart`
- Modify: `lib/features/home/widgets/home_recent_scans.dart` (remove both private methods, import helper)

- [ ] **Step 1: Read both `_timeAgo` implementations**

Run: `grep -n "_timeAgo" lib/features/home/widgets/home_recent_scans.dart`
Then `Read tool` on the surrounding 10 lines of each match. Confirm they are byte-identical (or document the diff).

- [ ] **Step 2: Write failing test for shared helper**

Create `test/core/utils/relative_time_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/utils/relative_time.dart';

void main() {
  group('relativeTime', () {
    final now = DateTime(2026, 4, 28, 12, 0, 0);

    test('returns "just now" for under 60 seconds', () {
      expect(relativeTime(now.subtract(const Duration(seconds: 30)), now: now),
          'just now');
    });
    test('returns "5m ago" for minutes', () {
      expect(relativeTime(now.subtract(const Duration(minutes: 5)), now: now),
          '5m ago');
    });
    test('returns "3h ago" for hours', () {
      expect(relativeTime(now.subtract(const Duration(hours: 3)), now: now),
          '3h ago');
    });
    test('returns "2d ago" for days under 7', () {
      expect(relativeTime(now.subtract(const Duration(days: 2)), now: now),
          '2d ago');
    });
    test('returns ISO date for >= 7 days', () {
      expect(relativeTime(now.subtract(const Duration(days: 8)), now: now),
          '2026-04-20');
    });
  });
}
```

- [ ] **Step 3: Run test — expect FAIL (file doesn't exist yet)**

Run: `flutter test test/core/utils/relative_time_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 4: Create the helper**

Create `lib/core/utils/relative_time.dart`:

```dart
/// Returns a compact human-readable relative timestamp like "just now",
/// "5m ago", "3h ago", "2d ago", or an ISO date for older entries.
///
/// [now] is exposed for testability — production callers omit it.
String relativeTime(DateTime when, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(when);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return when.toIso8601String().split('T').first;
}
```

(Note: adjust the cases above to match the exact behavior in the existing private methods — read them first in Step 1 and adapt these branches if they differ. The test cases must match the **existing** behavior, not a new spec.)

- [ ] **Step 5: Run tests — expect PASS**

Run: `flutter test test/core/utils/relative_time_test.dart`
Expected: 5/5 PASS.

- [ ] **Step 6: Replace duplicates in `home_recent_scans.dart`**

Add import: `import 'package:pharmaguide/core/utils/relative_time.dart';`

Find both `_timeAgo` methods. Delete both. Replace any `_timeAgo(scannedAt)` call with `relativeTime(scannedAt)`.

- [ ] **Step 7: Run home tests + analyze**

Run: `flutter test test/features/home/home_screen_test.dart && flutter analyze`
Expected: ALL PASS, analyze clean.

- [ ] **Step 8: Commit**

```bash
git add lib/core/utils/relative_time.dart \
  test/core/utils/relative_time_test.dart \
  lib/features/home/widgets/home_recent_scans.dart
git commit -m "refactor(core): extract relativeTime helper from home recents

Two identical private _timeAgo implementations consolidated into a single
testable helper. 5 unit tests cover the case ladder."
```

---

### Task A6: Remove duplicate "Status:" label on Stack screen

**Why:** `_StackSummaryCard` renders `healthLabel.label` as both the title (line 275) and as `'Status: …'` body text (line 291). Visible repetition.

**Files:**
- Modify: `lib/features/stack/stack_screen.dart:286-292`
- Modify: `test/features/stack/stack_screen_test.dart`

- [ ] **Step 1: Read the surrounding region**

Run: `Read tool on stack_screen.dart, offset 260, limit 50` to confirm exact code.

- [ ] **Step 2: Write failing test asserting label appears exactly once**

Add to `stack_screen_test.dart`:

```dart
testWidgets('StackScreen does not duplicate health label as "Status:" line',
    (tester) async {
  // ... build container with a populated stack producing 'Solid' label ...
  await tester.pumpWidget(...);
  await tester.pumpAndSettle();
  // The label should appear once (as the card title), not twice.
  expect(find.text('Solid'), findsOneWidget);
  expect(find.textContaining('Status:'), findsNothing);
});
```

- [ ] **Step 3: Run — expect FAIL**

Run: `flutter test test/features/stack/stack_screen_test.dart`
Expected: FAIL — `Status: Solid` text still rendered.

- [ ] **Step 4: Remove the duplicate `Text('Status: …')` widget**

In `stack_screen.dart` around line 291, delete the `Text('Status: ${safetyScore.healthLabel.label}', style: …)` widget and any surrounding `SizedBox` used only as its spacer.

- [ ] **Step 5: Run — expect PASS**

Run: `flutter test test/features/stack/stack_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/stack/stack_screen.dart test/features/stack/stack_screen_test.dart
git commit -m "fix(stack): remove duplicate health label from summary card

healthLabel.label was rendered twice — as title and as 'Status: ...' body.
Title is sufficient; body line removed."
```

---

### Task A7: Add boundary tests for tier-cap at score 84/85

**Why:** `stack_safety_score_test.dart` covers `score 86 + monitor → solid` (cap kicks in) but not `score 85 + monitor` (cap boundary) or `score 84 + monitor` (cap doesn't apply, already solid). Without these, a future tweak to the cap threshold could regress silently.

**Files:**
- Modify: `test/core/models/stack_safety_score_test.dart`

- [ ] **Step 1: Add three boundary tests**

```dart
test('score 85 with monitor issue caps to solid (boundary)', () {
  expect(buildScore(85, issues: [_issue(Severity.monitor)]).healthLabel,
      StackHealthLabel.solid);
});

test('score 84 with monitor issue stays solid (already below cap)', () {
  expect(buildScore(84, issues: [_issue(Severity.monitor)]).healthLabel,
      StackHealthLabel.solid);
});

test('score 86 with no monitor issues stays optimized (cap does not apply)', () {
  expect(buildScore(86).healthLabel, StackHealthLabel.optimized);
});
```

- [ ] **Step 2: Run — confirm all PASS**

Run: `flutter test test/core/models/stack_safety_score_test.dart`
Expected: ALL PASS (these tests should already pass under current logic; we're locking the contract).

- [ ] **Step 3: Commit**

```bash
git add test/core/models/stack_safety_score_test.dart
git commit -m "test(stack): add boundary coverage for tier-cap at score 84/85

Locks the optimized→solid cap behavior at the boundary so future tweaks
can't silently regress."
```

---

### Task A8: Update greeting copy to morning / hello there / evening / night

**Why:** User specified the greeting set: "Good morning, Hello there, Good evening, Goodnight". Current code maps to `Good morning / Good afternoon / Good evening`. Add the night branch and replace afternoon with "Hello there".

**Files:**
- Modify: `lib/features/home/widgets/home_hero_section.dart:19-24`
- Create: `test/features/home/widgets/home_hero_section_test.dart`

- [ ] **Step 1: Write failing test for the four greeting branches**

Create `test/features/home/widgets/home_hero_section_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/home/widgets/home_hero_section.dart';

void main() {
  group('HomeHeroSection.greetingFor', () {
    test('5–11 returns "Good morning"', () {
      expect(HomeHeroSection.greetingFor(5), 'Good morning');
      expect(HomeHeroSection.greetingFor(11), 'Good morning');
    });
    test('12–16 returns "Hello there"', () {
      expect(HomeHeroSection.greetingFor(12), 'Hello there');
      expect(HomeHeroSection.greetingFor(16), 'Hello there');
    });
    test('17–20 returns "Good evening"', () {
      expect(HomeHeroSection.greetingFor(17), 'Good evening');
      expect(HomeHeroSection.greetingFor(20), 'Good evening');
    });
    test('21–4 returns "Good night"', () {
      expect(HomeHeroSection.greetingFor(21), 'Good night');
      expect(HomeHeroSection.greetingFor(0), 'Good night');
      expect(HomeHeroSection.greetingFor(4), 'Good night');
    });
  });
}
```

- [ ] **Step 2: Run — expect FAIL (method doesn't exist)**

Run: `flutter test test/features/home/widgets/home_hero_section_test.dart`
Expected: FAIL — `greetingFor` not defined.

- [ ] **Step 3: Refactor `_greeting` to a static testable method + add night branch**

In `home_hero_section.dart`, replace:

```dart
String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}
```

With:

```dart
@visibleForTesting
static String greetingFor(int hour) {
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Hello there';
  if (hour >= 17 && hour < 21) return 'Good evening';
  return 'Good night';
}
```

Then update line 51 from `${_greeting()}$name.` to `${greetingFor(DateTime.now().hour)}$name.`

Add import: `import 'package:flutter/foundation.dart' show visibleForTesting;`

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/features/home/widgets/home_hero_section_test.dart`
Expected: 4/4 PASS.

- [ ] **Step 5: Run analyze + full home test suite**

Run: `flutter test test/features/home/ && flutter analyze`
Expected: ALL PASS, analyze clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/home/widgets/home_hero_section.dart \
  test/features/home/widgets/home_hero_section_test.dart
git commit -m "feat(home): four-tier time-of-day greeting

Adds night branch (Good night, 21:00–04:59) and replaces 'Good afternoon'
with 'Hello there' (12:00–16:59). Makes greetingFor static + testable;
unit-covered at every boundary hour."
```

---

## Phase B — Material hierarchy unification

Strict three-tier surface system. Every home component maps to **exactly one** of: `hero` (the scan CTA gradient — singular), `standard` (`PGCard.plain` or `PGCard.elevated`), `recessed` (`PGCard.recessed`). No bespoke `Container + BoxDecoration` for visible surfaces.

### Task B1: Audit home surfaces and document tier mapping

**Files:**
- Create: `docs/superpowers/plans/2026-04-28-home-apple-grade.surfaces.md` (audit doc — kept alongside plan)

- [ ] **Step 1: Walk every home widget file, list every visible surface**

For each of: `home_screen.dart`, `home_hero_section.dart`, `home_scan_cta.dart`, `home_search_launcher.dart`, `home_profile_completeness_card.dart`, `home_stack_health.dart`, `home_recent_scans.dart`, `home_quick_check_cta.dart`, `home_citation_strip.dart` — list each surface (Container, DecoratedBox, Card, PGCard, etc.) with: file:line, current tier, target tier (one of hero/standard/recessed/raw-text).

- [ ] **Step 2: Save the audit table as `surfaces.md` next to this plan**

Document format:

```markdown
| File | Line | Current | Target | Action |
|---|---|---|---|---|
| home_scan_cta.dart | 40 | LinearGradient + BoxShadow | hero | KEEP |
| home_search_launcher.dart | 17 | Container white | standard | MIGRATE to PGCard.plain |
| home_profile_completeness_card.dart | 22 | PGCard.plain | recessed | MIGRATE — it's a nudge |
| ... | ... | ... | ... | ... |
```

- [ ] **Step 3: Commit the audit doc**

```bash
git add docs/superpowers/plans/2026-04-28-home-apple-grade.surfaces.md
git commit -m "docs(home): surface-tier audit before migration

Pre-work for B2: every visible home surface mapped to one of three
strict tiers (hero / standard / recessed). Migration follows."
```

### Task B2: Migrate non-conforming surfaces to PGCard variants

**Files:** all files flagged in B1's audit with action `MIGRATE`.

- [ ] **Step 1: For each MIGRATE row, replace raw `Container + BoxDecoration` with `PGCard(variant: ..., child: ...)`**

Example pattern — before:
```dart
Container(
  decoration: BoxDecoration(
    color: scheme.surface,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: scheme.outlineVariant),
  ),
  padding: const EdgeInsets.all(16),
  child: ...,
)
```

After:
```dart
PGCard(
  variant: PGCardVariant.plain,
  padding: const EdgeInsets.all(AppTheme.space16),
  child: ...,
)
```

Apply per file, one file per commit.

- [ ] **Step 2: After each file, run analyze + visual smoke**

Run: `flutter analyze && flutter test test/features/home/`
Expected: clean.

- [ ] **Step 3: One commit per migrated file**

```bash
git add lib/features/home/widgets/<file>.dart
git commit -m "refactor(home): migrate <component> to PGCard.<variant>

Part of material-hierarchy unification — every home surface now uses one
of three tiers (hero/standard/recessed)."
```

### Task B3: Verify dark-mode surface ladder uses iOS-grade tiers

**Files:**
- Modify (if needed): `lib/core/theme/app_theme.dart`

- [ ] **Step 1: Read the current dark `ColorScheme`**

Run: `grep -n "surface\|surfaceContainer" lib/core/theme/app_theme.dart` and inspect the dark scheme's surface ladder values.

- [ ] **Step 2: Confirm or add the iOS-grade ladder**

Target values (iOS systemGray reference):
- `surface`: `#000000` (page bg, dark)
- `surfaceContainerLowest`: `#0A0A0A`
- `surfaceContainerLow`: `#141414`
- `surfaceContainer`: `#1C1C1E` (matches systemGray6)
- `surfaceContainerHigh`: `#2C2C2E` (matches systemGray5)
- `surfaceContainerHighest`: `#3A3A3C` (matches systemGray4)

If current values are within ±4 RGB units of these, leave them. Otherwise update.

- [ ] **Step 3: Visual smoke on iPhone dark mode**

Run app on simulator with dark mode. Confirm no visible regression.

- [ ] **Step 4: Commit (only if changes made)**

```bash
git add lib/core/theme/app_theme.dart
git commit -m "refactor(theme): align dark surface ladder with iOS systemGray tiers

surfaceContainer/High/Highest now match systemGray6/5/4 within RGB
tolerance — produces native-feel dark elevation."
```

---

## Phase C — Tactile / motion (PGPressable + haptics adoption)

Build one reusable wrapper and apply it everywhere a finger lands.

### Task C1: Build `PGPressable` widget

**Why:** Apple's tactile signature is press-down compression with a subtle spring release. Currently no tappable surface in the app does this — `PGCard.onTap` uses `InkWell` (Material ripple, not iOS-feel).

**Files:**
- Create: `lib/core/widgets/pg_pressable.dart`
- Create: `test/core/widgets/pg_pressable_test.dart`

- [ ] **Step 1: Write failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';

void main() {
  testWidgets('PGPressable scales down to 0.96 on press-in', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PGPressable(
          onTap: () {},
          child: const SizedBox(width: 100, height: 100, key: Key('child')),
        ),
      ),
    ));
    final finder = find.byType(PGPressable);
    final gesture = await tester.startGesture(tester.getCenter(finder));
    await tester.pump(const Duration(milliseconds: 80));
    final transform = tester
        .widget<AnimatedScale>(find.descendant(
            of: finder, matching: find.byType(AnimatedScale)))
        .scale;
    expect(transform, lessThan(1.0));
    expect(transform, greaterThanOrEqualTo(0.96));
    await gesture.up();
  });

  testWidgets('PGPressable returns to 1.0 after release', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PGPressable(
          onTap: () {},
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    ));
    final finder = find.byType(PGPressable);
    final g = await tester.startGesture(tester.getCenter(finder));
    await tester.pump(const Duration(milliseconds: 80));
    await g.up();
    await tester.pumpAndSettle();
    final scale = tester
        .widget<AnimatedScale>(find.descendant(
            of: finder, matching: find.byType(AnimatedScale)))
        .scale;
    expect(scale, 1.0);
  });

  testWidgets('PGPressable fires onTap and haptic', (tester) async {
    int taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PGPressable(
          onTap: () => taps++,
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    ));
    await tester.tap(find.byType(PGPressable));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/core/widgets/pg_pressable_test.dart`
Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Create `pg_pressable.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';

/// Apple-style press feedback: scales the child to 0.96 on press-in,
/// springs back on release, and fires [PGHaptics.press] on tap.
///
/// Use this for any tappable card, tile, or button surface where you want
/// the iOS tactile signature instead of a Material ripple.
///
/// ```dart
/// PGPressable(
///   onTap: () => context.push('/product/$id'),
///   child: PGCard(child: ...),
/// )
/// ```
///
/// Honors `MediaQueryData.disableAnimations` (reduce-motion / accessibility):
/// when set, the scale animation is skipped but the tap still fires.
class PGPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Scale at the bottom of the press. Default 0.96 — matches App Store /
  /// Apple TV tile press depth.
  final double pressedScale;

  /// Whether to fire a haptic on tap. Default true. Disable for very
  /// frequent taps (e.g. keyboard rows) to avoid haptic fatigue.
  final bool haptic;

  const PGPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.haptic = true,
  });

  @override
  State<PGPressable> createState() => _PGPressableState();
}

class _PGPressableState extends State<PGPressable> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) PGHaptics.press(context);
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed && !reduceMotion ? widget.pressedScale : 1.0,
        duration: _pressed ? AppMotion.fast : AppMotion.medium,
        curve: _pressed ? AppMotion.standard : AppMotion.spring,
        child: widget.child,
      ),
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS (3/3)**

Run: `flutter test test/core/widgets/pg_pressable_test.dart`
Expected: 3/3 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/pg_pressable.dart test/core/widgets/pg_pressable_test.dart
git commit -m "feat(core): PGPressable — Apple-style press feedback wrapper

Scales child to 0.96 on press-in, springs back via AppMotion.spring on
release, fires PGHaptics.press on tap. Honors reduce-motion. Replaces
Material InkWell for surfaces that should feel iOS-native."
```

---

### Task C2: Wrap Recent Scan cards with `PGPressable`

**Files:**
- Modify: `lib/features/home/widgets/home_recent_scans.dart` (`_RecentScanCard`)

- [ ] **Step 1: Identify current tap mechanism**

Run: `grep -n "onTap\|InkWell\|GestureDetector" lib/features/home/widgets/home_recent_scans.dart`

- [ ] **Step 2: Wrap the card body in `PGPressable`**

Replace the existing tap wrapper (likely an `InkWell` or `GestureDetector`) with:

```dart
PGPressable(
  onTap: () {
    // existing navigation
    context.push('/product/${product.id}');
  },
  child: <existing card visual>,
)
```

Remove any duplicated haptic call if one existed.

- [ ] **Step 3: Run home tests + analyze**

Run: `flutter test test/features/home/ && flutter analyze`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add lib/features/home/widgets/home_recent_scans.dart
git commit -m "feat(home): PGPressable on Recent scan cards

Apple-style press compression + spring release + tap haptic on each
recent scan tile."
```

---

### Task C3: Wrap Scan CTA with `PGPressable`

**Files:**
- Modify: `lib/features/home/widgets/home_scan_cta.dart`

- [ ] **Step 1: Replace existing tap surface (InkWell or Material) with `PGPressable(haptic: true, ...)`**

Wrap only the *content* of the scan CTA, NOT the gradient surface itself, so the gradient and shadow visually scale together. The press should affect the *whole card*.

If the file currently uses `InkWell` inside the gradient, change to `PGPressable` wrapping the gradient `Container`. Test reduces motion path.

- [ ] **Step 2: Test scan-flow haptic**

Manual smoke: tap scan CTA on physical iPhone — confirm a single light haptic, no double-tap.

- [ ] **Step 3: Run analyze + tests**

Run: `flutter analyze && flutter test test/features/home/`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add lib/features/home/widgets/home_scan_cta.dart
git commit -m "feat(home): PGPressable on Scan CTA

Hero card now compresses on press and spring-releases. Existing scan
flow haptic preserved (one haptic per tap, not two)."
```

---

### Task C4: Wrap Quick Check CTA with `PGPressable`

**Files:**
- Modify: `lib/features/home/widgets/home_quick_check_cta.dart`

Same pattern as C3. Tap target is the whole row.

- [ ] **Step 1: Replace tap wrapper**
- [ ] **Step 2: Run tests + analyze**
- [ ] **Step 3: Commit**

```bash
git commit -m "feat(home): PGPressable on Quick Check CTA"
```

---

### Task C5: Wrap Profile Completeness card with `PGPressable`

**Files:**
- Modify: `lib/features/home/widgets/home_profile_completeness_card.dart`

Same pattern. The card currently routes to profile edit on tap — preserve that.

- [ ] **Step 1: Replace tap wrapper**
- [ ] **Step 2: Run tests + analyze**
- [ ] **Step 3: Commit**

```bash
git commit -m "feat(home): PGPressable on Profile Completeness card"
```

---

### Task C6: Migrate scanner from raw `HapticFeedback` to `PGHaptics`

**Why:** `lib/features/scanner/scanner_screen.dart:50, 90` still calls raw `HapticFeedback.lightImpact()` and `mediumImpact()`. Once we migrate, EVERY haptic in the app routes through `PGHaptics` and respects reduce-motion.

**Files:**
- Modify: `lib/features/scanner/scanner_screen.dart`

- [ ] **Step 1: Replace line 50**

Find `unawaited(HapticFeedback.lightImpact());` and replace with `unawaited(PGHaptics.tap(context));` (decorative — should be reduce-motion-suppressible).

- [ ] **Step 2: Replace line 90**

Find `unawaited(HapticFeedback.mediumImpact());` — this is scan-success, which is safety-critical. Use `unawaited(PGHaptics.warning());` if it's a warning-tier event, or `unawaited(PGHaptics.success(context));` if it's just success confirmation. Read the surrounding code to determine intent.

- [ ] **Step 3: Update imports — remove `package:flutter/services.dart` if no longer needed; add `pg_haptics.dart`**

- [ ] **Step 4: Run scanner tests + analyze**

Run: `flutter test test/features/scanner/ 2>/dev/null; flutter analyze`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/scanner/scanner_screen.dart
git commit -m "refactor(scanner): use PGHaptics instead of raw HapticFeedback

Now every haptic in the app routes through PGHaptics and respects
reduce-motion / accessibility correctly."
```

---

## Phase D — Search as embedded scroll-aware system surface

Replace the static search launcher with a `SliverPersistentHeader` that pins to the top edge while you scroll, gains a frosted-glass background past the hero, and shows a subtle bottom hairline only when content scrolls underneath.

### Task D1: Build `PGFrostedHeader` slot widget

**Why:** `PGFrostedNavBar` proves the BackdropFilter recipe works; we need the same recipe for a sliver-mounted top-of-screen surface.

**Files:**
- Create: `lib/core/widgets/pg_frosted_header.dart`
- Create: `test/core/widgets/pg_frosted_header_test.dart`

- [ ] **Step 1: Write minimal API test (smoke — frosted is visual)**

Test that the widget renders without crashing and exposes `isCondensed` based on a `scrollOffset` parameter.

- [ ] **Step 2: Build the widget — the simplest possible signature**

```dart
import 'dart:ui';
import 'package:flutter/material.dart';

/// Frosted-glass header surface that sits above scrollable content.
/// Visually quiet at scroll offset 0 (transparent); turns frosted with a
/// hairline divider once content has scrolled underneath.
///
/// Drop into a `SliverPersistentHeader(delegate: _FrostedDelegate(...))`,
/// or wrap in a `SliverAppBar.flexibleSpace` for a hybrid layout.
class PGFrostedHeader extends StatelessWidget {
  final Widget child;
  final double scrollProgress; // 0..1 — host computes from scroll
  final double blurSigma;

  const PGFrostedHeader({
    super.key,
    required this.child,
    required this.scrollProgress,
    this.blurSigma = 30,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final p = scrollProgress.clamp(0.0, 1.0);
    final fillAlpha = (isDark ? 0.72 : 0.78) * p;
    final hairlineAlpha = 0.6 * p;

    return ClipRect(
      child: BackdropFilter(
        filter: p == 0
            ? ImageFilter.blur(sigmaX: 0, sigmaY: 0)
            : ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: fillAlpha),
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: hairlineAlpha),
                width: 0.5,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Test passes**

Run: `flutter test test/core/widgets/pg_frosted_header_test.dart`

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(core): PGFrostedHeader — scroll-aware frosted top surface"
```

---

### Task D2: Convert home scroll shell to sliver-mounted frosted search

**Why:** Currently search is a `SliverPadding > HomeSearchLauncher`. It scrolls away with the hero. For Apple-grade behavior, the search should pin under the status bar after the hero scrolls past, with a frosted background fading in.

**Files:**
- Modify: `lib/features/home/home_screen.dart`
- Possibly modify: `lib/features/home/widgets/home_search_launcher.dart` (no longer responsible for top padding)

- [ ] **Step 1: Wrap home `CustomScrollView` body in a `NotificationListener<ScrollUpdateNotification>` to track offset**

In `HomeScreen` state, add a `ValueNotifier<double>` for scroll progress (0 at top, 1 once user scrolls past hero ~120px). Pass to `PGFrostedHeader`.

- [ ] **Step 2: Restructure the CustomScrollView**

Move the search launcher OUT of the inline scroll order. Wrap the entire scroll view in a `Stack` with the search pinned at top via a top-aligned `Positioned`.

Architecture:

```dart
return Scaffold(
  extendBodyBehindAppBar: true,
  body: Stack(
    children: [
      CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: mq.padding.top + AppTheme.space12 + searchHeight)),
          // hero, scan, profile, stack, recents, quick check, citation, footer
          ...
        ],
      ),
      // Frosted search overlay
      Positioned(
        top: 0, left: 0, right: 0,
        child: ValueListenableBuilder<double>(
          valueListenable: _scrollProgress,
          builder: (_, p, __) => PGFrostedHeader(
            scrollProgress: p,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: HomeSearchLauncher(),
              ),
            ),
          ),
        ),
      ),
    ],
  ),
);
```

The scroll listener computes `p = (offset / 120).clamp(0.0, 1.0)`.

- [ ] **Step 3: Run home tests — they may break because layout changed**

Run: `flutter test test/features/home/`
Expected: tests that match `find.text('Search supplements')` should still find the launcher; tests that asserted vertical order may need updating to account for the search now being in a `Stack`, not inline.

- [ ] **Step 4: Update tests if needed; never weaken assertions**

If a test checked that search appears between hero and scan, change it to: search is reachable AND hero is reachable AND scan is reachable. The Stack composition means the literal Y-order test from before is no longer meaningful; semantic reachability is.

- [ ] **Step 5: Manual smoke — scroll past hero on simulator**

Confirm: search bar gains frosted background as you scroll. Hairline appears when content is underneath. No layout jumps.

- [ ] **Step 6: Commit**

```bash
git add lib/features/home/home_screen.dart \
  lib/features/home/widgets/home_search_launcher.dart \
  test/features/home/home_screen_test.dart
git commit -m "feat(home): pinned frosted search header

Search is no longer inline — pins to the top edge and fades in a frosted
background as the user scrolls past the hero. Matches the iOS large-title
collapse pattern (App Store, Settings, Mail)."
```

---

### Task D3: Animate search focus state

**Files:**
- Modify: `lib/features/home/widgets/home_search_launcher.dart`

- [ ] **Step 1: On tap-down, add a subtle glow/border highlight**

Wrap the launcher's visible chip in a `PGPressable` with `pressedScale: 0.99` (almost imperceptible) and `haptic: false` (we don't want a haptic just for entering search — that's the destination's job).

- [ ] **Step 2: Replace `readOnly TextField` with a tappable label-pill**

The launcher already exists — review what it currently uses. If it's a `TextField`, swap to a `PGPressable > Container > Row > Icon + Text` pattern, since the launcher only navigates to a search screen on tap (no inline typing).

- [ ] **Step 3: Test + analyze**

Run: `flutter test test/features/home/ && flutter analyze`

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(home): tactile search launcher

Replace readOnly TextField with a press-aware launcher pill. No haptic
on tap-down (search screen owns the entry haptic)."
```

---

## Phase E — Recents as object-like carousel

Snap behavior + selection haptic + tap haptic. Cards now feel like physical cells, not abstract tiles.

### Task E1: Replace ListView.separated with PageView snap

**Files:**
- Modify: `lib/features/home/widgets/home_recent_scans.dart`

- [ ] **Step 1: Read current ListView.separated implementation (lines ~70–82)**

- [ ] **Step 2: Replace with PageView using viewportFraction**

```dart
SizedBox(
  height: 210,
  child: PageView.builder(
    controller: PageController(
      viewportFraction: 0.42,    // ~156px on a 390px iPhone
      padEnds: false,            // first card flush with leading edge
    ),
    physics: const PageScrollPhysics(),
    padEnds: false,
    itemCount: scans.length,
    onPageChanged: (_) => PGHaptics.tap(context),
    itemBuilder: (context, index) {
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: _RecentScanCard(
          product: scans[index].product,
          scannedAt: scans[index].scannedAt,
        ),
      );
    },
  ),
),
```

- [ ] **Step 3: Verify shimmer skeleton still has the same width** (Task A3 already used a horizontal ListView; confirm it visually matches the new PageView card width)

- [ ] **Step 4: Run analyze + smoke**

Run: `flutter analyze && flutter test test/features/home/`

- [ ] **Step 5: Manual smoke — feel the snap**

On simulator/device: swipe through 5+ scans, confirm snap behavior, confirm one selection haptic per card crossed.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(home): snap-paginated Recents carousel with selection haptic

PageView with viewportFraction:0.42 produces Apple-style snap behavior
(App Store/TV row pattern). PGHaptics.tap fires on each card-snap event
— Apple Music's mini-player + Photos year/month signature."
```

---

### Task E2: Polish empty state with PGPressable nudge

**Files:**
- Modify: `lib/features/home/widgets/home_recent_scans.dart` (`_buildEmptyState`)

- [ ] **Step 1: Wrap the "Scan your first supplement" button in PGPressable**

If currently using a `FilledButton` or `ElevatedButton`, leave it — Material buttons already have ripple. But if it's a custom card-style CTA, wrap with `PGPressable`.

- [ ] **Step 2: Confirm the existing `AnimatedContainer` with `AppMotion.fast` for the empty-state CTA still works alongside PGPressable**

(May need to remove the AnimatedContainer if PGPressable now provides the press animation.)

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(home): tactile empty-state CTA in Recents"
```

---

## Phase F — iOS chrome / large-title / platform-adaptive

The hardest phase — also the highest visual payoff. After this, the home page reads as iOS-native.

### Task F1: Replace hardcoded 96pt bottom safe-area with dynamic

**Files:**
- Modify: `lib/features/home/home_screen.dart:182` (hardcoded `SizedBox(height: 96)`)

- [ ] **Step 1: Find the hardcoded value**

`grep -n "96" lib/features/home/home_screen.dart`

- [ ] **Step 2: Replace with computed value**

```dart
SliverToBoxAdapter(
  child: SizedBox(
    height: kPGNavBarHeight + mq.padding.bottom,
  ),
),
```

(`kPGNavBarHeight` is already exported from `pg_frosted_nav_bar.dart`.)

- [ ] **Step 3: Test + analyze**

- [ ] **Step 4: Commit**

```bash
git commit -m "fix(home): dynamic bottom safe-area instead of hardcoded 96pt"
```

---

### Task F2: AnnotatedRegion for status bar style adaptation

**Why:** The hero zone is light text on a (likely white) page background, but on the gradient scan CTA, light text. As the user scrolls past, the status bar should crossfade between light-content and dark-content.

**Files:**
- Modify: `lib/features/home/home_screen.dart` (wrap Scaffold body in `AnnotatedRegion`)

- [ ] **Step 1: Wrap the Scaffold or its body**

```dart
return AnnotatedRegion<SystemUiOverlayStyle>(
  value: theme.brightness == Brightness.dark
      ? SystemUiOverlayStyle.light
      : SystemUiOverlayStyle.dark,
  child: Scaffold(...),
);
```

For now, keep the style aligned with the system theme (no scroll-driven crossfade — that's a stretch goal). The frosted search bar already provides the visual signal that the user has scrolled.

- [ ] **Step 2: Add import: `import 'package:flutter/services.dart';`**

- [ ] **Step 3: Run app on iPhone simulator — confirm status bar text contrast**

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(home): AnnotatedRegion for status bar text contrast"
```

---

### Task F3: PlatformAdaptive pull-to-refresh

**Why:** iOS users expect pull-to-refresh on home — Apple Mail set the convention in 2008. Use `CupertinoSliverRefreshControl` on iOS, `RefreshIndicator` on Android.

**Files:**
- Modify: `lib/features/home/home_screen.dart`

- [ ] **Step 1: Add a refresh handler**

```dart
Future<void> _onRefresh(WidgetRef ref) async {
  await PGHaptics.tap();
  ref.invalidate(isFirstLaunchHomeProvider);
  // also invalidate recents + stack-health providers
  ref.invalidate(_recentScansProvider(10));
  ref.invalidate(_recentScansProvider(25));
  // give the UI a beat to look intentional
  await Future<void>.delayed(const Duration(milliseconds: 350));
}
```

- [ ] **Step 2: Add a leading sliver for the refresh control**

```dart
slivers: [
  if (Platform.isIOS)
    CupertinoSliverRefreshControl(
      onRefresh: () => _onRefresh(ref),
    )
  else
    SliverToBoxAdapter(
      child: RefreshIndicator(
        onRefresh: () => _onRefresh(ref),
        child: SizedBox.shrink(),
      ),
    ),
  // ... rest of slivers
],
```

(The Android branch is awkward inside a `CustomScrollView`; the cleaner Android pattern is to wrap the entire `CustomScrollView` in a `RefreshIndicator`. Refactor accordingly — the sliver-based approach above is iOS-only.)

Recommended structure: wrap the entire `Scaffold` body in a platform check:

```dart
final scrollView = CustomScrollView(slivers: [...]);
final body = Platform.isIOS
    ? scrollView // CupertinoSliverRefreshControl is inserted as the FIRST sliver above
    : RefreshIndicator(onRefresh: () => _onRefresh(ref), child: scrollView);
```

- [ ] **Step 3: Test + smoke on both platforms**

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(home): platform-adaptive pull-to-refresh

CupertinoSliverRefreshControl on iOS, RefreshIndicator on Android. Refresh
invalidates first-launch + recents providers. Light haptic on pull trigger."
```

---

### Task F4: Wire `CupertinoPageRoute` for swipe-back on iOS at the router

**Files:**
- Modify: wherever the GoRouter / Navigator routes are defined (likely `lib/app.dart` or `lib/router.dart`)

- [ ] **Step 1: Find the router file**

Run: `grep -rn "GoRouter\|MaterialPageRoute\|PageRouteBuilder" lib/app.dart lib/`

- [ ] **Step 2: Wrap routes in a platform-conditional page builder**

For each top-level navigable route, build a `pageBuilder` that returns `CupertinoPage` on iOS and `MaterialPage` elsewhere. If using GoRouter, this is one helper used across all routes:

```dart
Page<dynamic> platformPage(BuildContext ctx, GoRouterState state, Widget child) {
  return Platform.isIOS
      ? CupertinoPage(child: child, key: state.pageKey)
      : MaterialPage(child: child, key: state.pageKey);
}
```

Apply to every route's `pageBuilder`.

- [ ] **Step 3: Test swipe-back from product detail on iPhone simulator**

Confirm the gesture works AND scrollable content within the route doesn't swallow the gesture (left-edge swipe should always pop).

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(routing): CupertinoPageRoute on iOS for swipe-back

Every route on iOS now supports left-edge swipe-back gesture. Android
keeps MaterialPage with system back behavior."
```

---

## Phase G — Polish

Final layer.

### Task G1: Conditional SF font on iOS

**Why:** Inter is fine on Android. iOS apps that use the system font feel native; ones that don't never quite do.

**Files:**
- Modify: `lib/core/theme/app_theme.dart` (theme builder)

- [ ] **Step 1: Find the `fontFamily` setting in `ThemeData` definitions**

Run: `grep -n "fontFamily\|GoogleFonts\|Inter" lib/core/theme/app_theme.dart`

- [ ] **Step 2: Make `fontFamily` platform-conditional**

```dart
import 'dart:io' show Platform;
// ...
fontFamily: Platform.isIOS ? null : 'Inter',
```

`null` on iOS lets Flutter fall through to the system font (`.SF Pro Text` / `.SF Pro Display` based on optical sizing).

- [ ] **Step 3: Verify no asset errors**

Run: `flutter run` on both simulators. Confirm no missing-font errors and that iOS shows SF, Android shows Inter.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(theme): conditional SF font on iOS

iOS uses system font (.SF Pro) for native feel; Android keeps Inter. Zero
asset cost — Flutter falls through to platform default when fontFamily is
null."
```

---

### Task G2: Global Dynamic Type clamping

**Why:** Currently only the scan CTA clamps. Other surfaces over-scale at large accessibility sizes, breaking layout.

**Files:**
- Modify: `lib/app.dart` (`MaterialApp.builder`)

- [ ] **Step 1: Add a `builder` to MaterialApp that wraps with MediaQuery override**

```dart
MaterialApp(
  // ...existing config...
  builder: (context, child) {
    final mq = MediaQuery.of(context);
    final scale = mq.textScaler.clamp(
      minScaleFactor: 0.9,
      maxScaleFactor: 1.4,
    );
    return MediaQuery(
      data: mq.copyWith(textScaler: scale),
      child: child!,
    );
  },
);
```

- [ ] **Step 2: Remove per-component clamps that are now redundant**

Check `home_scan_cta.dart:21-22` — if it duplicates the global clamp, remove the local one.

- [ ] **Step 3: Smoke — set iOS simulator to AX5 (largest accessibility size) and confirm home doesn't break layout**

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(theme): global Dynamic Type clamp at 0.9–1.4x

App-wide cap prevents AX5 from breaking card layouts; replaces per-card
clamps in scan CTA."
```

---

## Self-Review Checklist (run before declaring complete)

- [ ] All 7 verification-report defects fixed: A1 (reactivity), A2 (5-threshold), A3 (shimmer width), A4 (dead file), A5 (timeAgo dedup), A6 (status duplicate), A7 (boundary tests)
- [ ] All 5 user-requested high-level items addressed: Search (D1–D3), Motion+touch (C1–C6), Material hierarchy (B1–B3), Recents (E1–E2), Top chrome (F1–F4)
- [ ] Greeting copy matches user spec: morning/hello there/evening/night, no "AM stack" anywhere (A8)
- [ ] Show all threshold = 5 (A2)
- [ ] Streak / "Today insight" / category rail explicitly NOT introduced
- [ ] `flutter analyze` clean after every commit
- [ ] Every TDD task has the red-green cycle verified
- [ ] All file:line citations in this plan resolved to real code
- [ ] No placeholder text in any task
- [ ] Each task ends in a commit

## Execution

Plan saved to `docs/superpowers/plans/2026-04-28-home-apple-grade.md`.

Two execution options:
1. **Subagent-Driven** (recommended) — fresh subagent per task, two-stage review between tasks, fast iteration.
2. **Inline Execution** — run tasks in this session with checkpoints between phases for review.

Total tasks: 8 (Phase A) + 3 (B) + 6 (C) + 3 (D) + 2 (E) + 4 (F) + 2 (G) = **28 tasks**.

User said "fix one task at the time, until everything is completed, nothing left behind" → **Inline Execution recommended** so the user can sanity-check each phase as it lands.
