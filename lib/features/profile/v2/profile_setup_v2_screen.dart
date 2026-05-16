import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_goal_chip.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_progress_dots.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/constants/schema_ids.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

/// Phase 11.7L.B — v2 mirror of [ProfileSetupScreen].
///
/// The legacy 5-step editor's INFORMATION ARCHITECTURE is preserved
/// 1:1 — same step order, same fields, same providers, same save
/// semantics. Only the visual layer changes to match the v2 design
/// system that Settings, Stack, Product Detail, and Onboarding already
/// inhabit. From the user's perspective, opening "Edit profile" should
/// no longer feel like a tonal break from the rest of the app.
///
/// What changed visually:
/// - **Chrome**: frosted Material header → cream Scaffold + lightweight
///   row with back chip, centered mono-caps eyebrow `STEP 02 / 05`, and
///   a ghost "Skip" CTA. Sits on `V2Colors.bg` (warm), not a tinted bar.
/// - **Progress**: thick LinearProgressIndicator → `PGProgressDots`
///   (same component onboarding uses) so the two onramp surfaces feel
///   like one product.
/// - **Step titles**: Geist Sans 600 → Newsreader serif (`displayXs`),
///   the same accent typography used on Onboarding emotional moments.
///   Subtitles drop to `V2Typography.body` muted.
/// - **Chips** (Goals, Conditions, Allergens): `PGFilterChip` → reuse
///   `PGGoalChip` so chip styling matches Onboarding's Goals page.
/// - **Radio rows** (Age bracket, Sex) and **checkbox rows** (Drug
///   classes): bespoke `_V2RadioTile` / `_V2CheckboxTile` that use
///   accent radio/check marks on a cream pressable surface, with a
///   subtle hairline divider stack instead of Material's `RadioListTile`.
/// - **Nickname input**: `_V2TextField` — cream fill, hairline outline
///   resolving to accent on focus, body text at `bodyXl`, no Material
///   helper icons that don't fit the editorial restraint.
/// - **Continue CTA**: `FilledButton` → `PGPillButton.primary` (pill
///   with accent fill, soft elevation, expand-to-fill width).
/// - **Review card**: `PGCard` rows → cream surface card with hairline
///   dividers indented to a 110px label column; values use
///   `V2Typography.body` and labels use `V2Typography.eyebrow` mono caps.
/// - **Privacy footer**: bordered Material container → flat cream-on-bg
///   advisory paragraph in `bodySm` muted.
///
/// What did NOT change (intentional):
/// - `profileProvider` and every notifier method are reused as-is.
/// - `SchemaIds` lookups, the goal-ranking sort, the
///   "max 2 goals" constraint, the allergen-group toggle semantics,
///   and the `saveToDb`-then-navigate save sequence are byte-for-byte
///   the same as the legacy screen. This screen is a pure visual
///   transform — no behavior change.
/// - Same exit route (`Routes.home`).
class ProfileSetupV2Screen extends ConsumerStatefulWidget {
  const ProfileSetupV2Screen({super.key});

  @override
  ConsumerState<ProfileSetupV2Screen> createState() =>
      _ProfileSetupV2ScreenState();
}

class _ProfileSetupV2ScreenState extends ConsumerState<ProfileSetupV2Screen> {
  // Unlike `OnboardingV2Screen`, this flow has no celebration / reset
  // path that swaps the PageView out of the tree, so the controller can
  // stay `final` without triggering the page_view.dart:189
  // `positions.isNotEmpty` assertion. If we ever add a "celebrate save"
  // surface here, mirror the Onboarding pattern: hold the controller in
  // a mutable field and recreate it on reset.
  final PageController _pageController = PageController();
  int _currentStep = 0;

  static const int _totalSteps = 5;

  /// Mono-caps step label that lives in the top-bar eyebrow alongside
  /// the step counter. Matches the legacy step ordering so save logic
  /// downstream stays unchanged.
  static const List<String> _stepLabels = [
    'Basic info',
    'Health goals',
    'Health profile',
    'Allergies',
    'Review',
  ];

  Future<void> _nextStep() async {
    if (_currentStep < _totalSteps - 1) {
      await _pageController.nextPage(
        duration: V2Motion.base,
        curve: V2Motion.smooth,
      );
    } else {
      await _save();
    }
  }

  Future<void> _prevStep() async {
    if (_currentStep > 0) {
      await _pageController.previousPage(
        duration: V2Motion.base,
        curve: V2Motion.smooth,
      );
    }
  }

  Future<void> _save() async {
    // Same await-the-drift-write semantics as the legacy screen — see
    // `ProfileSetupScreen._save` for the race-condition rationale.
    await ref.read(profileProvider.notifier).saveToDb();
    if (!mounted) return;
    GoRouter.of(context).go(Routes.home);
  }

  void _skip() {
    GoRouter.of(context).go(Routes.home);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final isLastStep = _currentStep == _totalSteps - 1;
    // Step 1 (Basic info) requires age bracket before the user can
    // continue; every other step is optional-by-design so the user
    // can advance to Review without filling everything in.
    final canContinue = _currentStep != 0 || profile.ageBracket != null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: V2Colors.bg,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: V2Colors.bg,
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(
                step: _currentStep,
                total: _totalSteps,
                label: _stepLabels[_currentStep],
                canGoBack: _currentStep > 0,
                onBack: _prevStep,
                onSkip: _skip,
              ),
              const SizedBox(height: V2Spacing.space16),
              PGProgressDots(total: _totalSteps, current: _currentStep),
              const SizedBox(height: V2Spacing.space24),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentStep = i),
                  children: const [
                    _BasicInfoV2Step(),
                    _GoalsV2Step(),
                    _HealthProfileV2Step(),
                    _AllergensV2Step(),
                    _ReviewV2Step(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  V2Spacing.space24,
                  V2Spacing.space8,
                  V2Spacing.space24,
                  V2Spacing.space24,
                ),
                child: PGPillButton(
                  label: isLastStep ? 'Save & continue' : 'Continue',
                  expand: true,
                  onPressed: canContinue
                      ? () {
                          // Match the legacy haptic ladder — success
                          // pattern on the terminal save, lighter press
                          // on intermediate steps.
                          if (isLastStep) {
                            HapticFeedback.heavyImpact();
                          } else {
                            HapticFeedback.selectionClick();
                          }
                          _nextStep();
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Top bar — back chip, eyebrow with step counter, skip CTA.
// =============================================================================

class _TopBar extends StatelessWidget {
  final int step;
  final int total;
  final String label;
  final bool canGoBack;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  const _TopBar({
    required this.step,
    required this.total,
    required this.label,
    required this.canGoBack,
    required this.onBack,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space16,
        V2Spacing.space12,
        V2Spacing.space16,
        0,
      ),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: canGoBack
                  ? IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: V2Colors.fg,
                        size: 18,
                      ),
                      onPressed: onBack,
                      splashRadius: 20,
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: Center(
                child: PGEyebrow(
                  'Step ${(step + 1).toString().padLeft(2, "0")}'
                  ' / ${total.toString().padLeft(2, "0")} · $label',
                ),
              ),
            ),
            SizedBox(
              width: 60,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSkip,
                child: Center(
                  child: Text(
                    'Skip',
                    style: V2Typography.label(color: V2Colors.fgMuted),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Shared step header — Newsreader serif title + Geist Sans subtitle.
// =============================================================================

class _StepHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _StepHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: V2Typography.displayXs(color: V2Colors.fg),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: V2Spacing.space8),
          Text(
            subtitle!,
            style: V2Typography.body(color: V2Colors.fgMuted),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// v2 text field — cream fill, hairline outline that resolves to accent
// on focus. Internal `_V2TextField` so the rest of the app keeps using
// Material text fields until Phase 11.10 promotes this to the component
// library after Search v2 / MedicationEntry v2 confirm the API.
// =============================================================================

class _V2TextField extends StatefulWidget {
  final String hint;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final IconData? prefixIcon;

  const _V2TextField({
    required this.hint,
    required this.initialValue,
    required this.onChanged,
    this.prefixIcon,
  });

  @override
  State<_V2TextField> createState() => _V2TextFieldState();
}

class _V2TextFieldState extends State<_V2TextField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return AnimatedContainer(
      duration: V2Motion.fast,
      curve: V2Motion.smooth,
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space16,
      ),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(
          color: focused ? V2Colors.accent : V2Colors.outline,
          width: focused ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          if (widget.prefixIcon != null) ...[
            Icon(
              widget.prefixIcon,
              size: 20,
              color: focused ? V2Colors.accent : V2Colors.fgSubtle,
            ),
            const SizedBox(width: V2Spacing.space12),
          ],
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: V2Typography.body(color: V2Colors.fgSubtle),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: V2Spacing.space16,
                ),
                isCollapsed: true,
              ),
              style: V2Typography.bodyXl(color: V2Colors.fg),
              cursorColor: V2Colors.accent,
              cursorWidth: 1.5,
              onChanged: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// v2 radio row — accent ring with inner accent dot when selected, on a
// pressable cream tile. Grouped tiles stack inside a cream surface card
// with hairline dividers between rows.
// =============================================================================

class _V2RadioTile extends StatelessWidget {
  final String label;
  final String? caption;
  final bool selected;
  final VoidCallback onTap;
  final bool showDivider;

  const _V2RadioTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.caption,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space16,
                vertical: V2Spacing.space16,
              ),
              child: Row(
                children: [
                  _V2RadioMark(selected: selected),
                  const SizedBox(width: V2Spacing.space16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: V2Typography.bodyMedium(color: V2Colors.fg),
                        ),
                        if (caption != null) ...[
                          const SizedBox(height: V2Spacing.space4),
                          Text(
                            caption!,
                            style: V2Typography.caption(
                              color: V2Colors.fgMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showDivider)
              const Padding(
                padding: EdgeInsets.only(left: V2Spacing.space48),
                child: Divider(
                  height: 1,
                  thickness: 0.5,
                  color: V2Colors.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _V2RadioMark extends StatelessWidget {
  final bool selected;
  const _V2RadioMark({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: V2Motion.fast,
      curve: V2Motion.smooth,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? V2Colors.accent : Colors.transparent,
        border: Border.all(
          color: selected ? V2Colors.accent : V2Colors.outline,
          width: selected ? 0 : 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}

// =============================================================================
// v2 checkbox row — accent fill with white tick when selected. Used for
// "Medications you take" (drug classes) where the user can choose any
// number; mirrors `_V2RadioTile` visually so grouped lists feel uniform.
// =============================================================================

class _V2CheckboxTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showDivider;

  const _V2CheckboxTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space16,
                vertical: V2Spacing.space16,
              ),
              child: Row(
                children: [
                  _V2CheckMark(selected: selected),
                  const SizedBox(width: V2Spacing.space16),
                  Expanded(
                    child: Text(
                      label,
                      style: V2Typography.bodyMedium(color: V2Colors.fg),
                    ),
                  ),
                ],
              ),
            ),
            if (showDivider)
              const Padding(
                padding: EdgeInsets.only(left: V2Spacing.space48),
                child: Divider(
                  height: 1,
                  thickness: 0.5,
                  color: V2Colors.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _V2CheckMark extends StatelessWidget {
  final bool selected;
  const _V2CheckMark({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: V2Motion.fast,
      curve: V2Motion.smooth,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: selected ? V2Colors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: selected ? V2Colors.accent : V2Colors.outline,
          width: selected ? 0 : 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? const Icon(
              Icons.check_rounded,
              size: 14,
              color: Colors.white,
            )
          : null,
    );
  }
}

// =============================================================================
// Cream surface card wrapper for grouped tile lists. Subtle outline +
// V2Shadows.sm so the card has the same restrained presence as
// `_ProfileHero` in Settings.
// =============================================================================

class _V2GroupCard extends StatelessWidget {
  final List<Widget> children;
  const _V2GroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

// =============================================================================
// Step 1 — Basic info: nickname, age bracket, sex.
// =============================================================================

class _BasicInfoV2Step extends ConsumerWidget {
  const _BasicInfoV2Step();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            title: 'What would you like to be called?',
            subtitle:
                'Used for greetings only. Your health data stays on this device.',
          ),
          const SizedBox(height: V2Spacing.space16),
          _V2TextField(
            hint: 'Nickname (optional)',
            initialValue: profile.nickname ?? '',
            onChanged: notifier.setNickname,
            prefixIcon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: V2Spacing.space32),
          const _StepHeader(
            title: 'Age bracket',
            subtitle: 'Required for RDA / UL scoring.',
          ),
          const SizedBox(height: V2Spacing.space12),
          _V2GroupCard(
            children: [
              for (var i = 0; i < SchemaIds.ageBrackets.length; i++)
                _V2RadioTile(
                  label: SchemaIds.ageBrackets[i],
                  selected: profile.ageBracket == SchemaIds.ageBrackets[i],
                  onTap: () =>
                      notifier.setAgeBracket(SchemaIds.ageBrackets[i]),
                  showDivider: i < SchemaIds.ageBrackets.length - 1,
                ),
            ],
          ),
          const SizedBox(height: V2Spacing.space32),
          const _StepHeader(
            title: 'Sex',
            subtitle: 'Required for accurate dosing.',
          ),
          const SizedBox(height: V2Spacing.space12),
          _V2GroupCard(
            children: [
              for (var i = 0; i < SchemaIds.sexOptions.length; i++)
                _V2RadioTile(
                  label: SchemaIds.sexOptions[i],
                  caption: (SchemaIds.sexOptions[i] == 'Other' ||
                          SchemaIds.sexOptions[i] == 'Prefer not to say')
                      ? 'Uses the most conservative safety limits'
                      : null,
                  selected: profile.sex == SchemaIds.sexOptions[i],
                  onTap: () => notifier.setSex(SchemaIds.sexOptions[i]),
                  showDivider: i < SchemaIds.sexOptions.length - 1,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Step 2 — Health Goals: max 2 chips from the priority-sorted goal list.
// =============================================================================

class _GoalsV2Step extends ConsumerWidget {
  const _GoalsV2Step();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);

    // Same goal-priority sort as the legacy screen so analytics +
    // recommendation ordering stay consistent across both visual paths.
    final sortedGoals = List<String>.from(SchemaIds.goals)
      ..sort((a, b) {
        const order = {'high': 0, 'medium': 1, 'low': 2};
        final pa = order[SchemaIds.goalPriorities[a]] ?? 2;
        final pb = order[SchemaIds.goalPriorities[b]] ?? 2;
        return pa.compareTo(pb);
      });

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            title: 'Pick up to two goals',
            subtitle:
                'Powers smart interaction warnings and personalized '
                'recommendations.',
          ),
          const SizedBox(height: V2Spacing.space16),
          Wrap(
            spacing: V2Spacing.space8,
            runSpacing: V2Spacing.space8,
            children: sortedGoals.map((goalId) {
              final selected = profile.goals.contains(goalId);
              final label = SchemaIds.goalLabels[goalId] ?? goalId;
              final atMax = profile.goals.length >= 2 && !selected;
              return PGGoalChip(
                label: label,
                selected: selected,
                disabled: atMax,
                onTap: atMax ? null : () => notifier.toggleGoal(goalId),
              );
            }).toList(),
          ),
          if (profile.goals.length >= 2) ...[
            const SizedBox(height: V2Spacing.space16),
            Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: V2Colors.fgMuted,
                ),
                const SizedBox(width: V2Spacing.space8),
                Text(
                  'Maximum 2 goals selected',
                  style: V2Typography.caption(color: V2Colors.fgMuted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Step 3 — Health Profile: conditions (chip wrap) + drug classes
// (checkbox card).
// =============================================================================

class _HealthProfileV2Step extends ConsumerWidget {
  const _HealthProfileV2Step();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            title: 'Health conditions',
            subtitle:
                'Ensures safe recommendations based on your conditions.',
          ),
          const SizedBox(height: V2Spacing.space16),
          Wrap(
            spacing: V2Spacing.space8,
            runSpacing: V2Spacing.space8,
            children: SchemaIds.conditions.map((condId) {
              final selected = profile.conditions.contains(condId);
              final label = SchemaIds.conditionLabels[condId] ?? condId;
              return PGGoalChip(
                label: label,
                selected: selected,
                onTap: () => notifier.toggleCondition(condId),
              );
            }).toList(),
          ),
          const SizedBox(height: V2Spacing.space32),
          const _StepHeader(
            title: 'Medications you take',
            subtitle:
                'Select types of medication you currently take. '
                'Kept on this device only.',
          ),
          const SizedBox(height: V2Spacing.space12),
          _V2GroupCard(
            children: [
              for (var i = 0; i < SchemaIds.drugClasses.length; i++)
                _V2CheckboxTile(
                  label: SchemaIds.drugClassLabels[SchemaIds.drugClasses[i]] ??
                      SchemaIds.drugClasses[i],
                  selected:
                      profile.drugClasses.contains(SchemaIds.drugClasses[i]),
                  onTap: () =>
                      notifier.toggleDrugClass(SchemaIds.drugClasses[i]),
                  showDivider: i < SchemaIds.drugClasses.length - 1,
                ),
            ],
          ),
          const SizedBox(height: V2Spacing.space12),
          Text(
            "In a future update, you'll be able to add specific medications "
            'by name for more precise warnings.',
            style: V2Typography.caption(color: V2Colors.fgMuted),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Step 4 — Allergies. Reuses the legacy `_AllergenChipDef` grouping
// (Shellfish/Gluten-free expand to multiple canonical IDs) so the
// matcher fires the same way regardless of which screen the user used.
// =============================================================================

class _AllergensV2Step extends ConsumerWidget {
  const _AllergensV2Step();

  /// Mirrored 1:1 from `ProfileSetupScreen._AllergensStep._chips`. Keep
  /// in sync if the legacy list grows or shrinks — both screens must
  /// expose the same canonical group definitions.
  static const List<_V2AllergenChipDef> _chips = [
    _V2AllergenChipDef('Milk / Dairy', ['ALLERGEN_MILK']),
    _V2AllergenChipDef('Eggs', ['ALLERGEN_EGGS']),
    _V2AllergenChipDef('Fish', ['ALLERGEN_FISH']),
    _V2AllergenChipDef('Shellfish', [
      'ALLERGEN_CRUSTACEANS',
      'ALLERGEN_MOLLUSCS',
    ]),
    _V2AllergenChipDef('Tree nuts', ['ALLERGEN_TREE_NUTS']),
    _V2AllergenChipDef('Peanuts', ['ALLERGEN_PEANUTS']),
    _V2AllergenChipDef('Soy', ['ALLERGEN_SOY']),
    _V2AllergenChipDef('Sesame', ['ALLERGEN_SESAME']),
    _V2AllergenChipDef('Gluten-free', [
      'ALLERGEN_WHEAT',
      'ALLERGEN_BARLEY',
      'ALLERGEN_RYE',
      'ALLERGEN_OATS',
    ]),
    _V2AllergenChipDef('Sulfites', ['ALLERGEN_SULFITES']),
    _V2AllergenChipDef('Celery', ['ALLERGEN_CELERY']),
    _V2AllergenChipDef('Mustard', ['ALLERGEN_MUSTARD']),
    _V2AllergenChipDef('Lupin', ['ALLERGEN_LUPIN']),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            title: 'Allergies & sensitivities',
            subtitle:
                'Prevents recommendations that could trigger allergic '
                'reactions. Select all that apply.',
          ),
          const SizedBox(height: V2Spacing.space16),
          Wrap(
            spacing: V2Spacing.space8,
            runSpacing: V2Spacing.space8,
            children: _chips.map((chip) {
              // A group chip is considered selected when every
              // constituent ID is present — partial selections (e.g.
              // wheat without barley) are treated as unselected so a
              // tap completes the group atomically.
              final selected = chip.allergenIds.every(
                profile.allergens.contains,
              );
              return PGGoalChip(
                label: chip.label,
                selected: selected,
                onTap: () => notifier.toggleAllergenGroup(chip.allergenIds),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _V2AllergenChipDef {
  final String label;
  final List<String> allergenIds;
  const _V2AllergenChipDef(this.label, this.allergenIds);
}

// =============================================================================
// Step 5 — Review + privacy footer. Same data sources as the legacy
// review step; only the surface styling shifts.
// =============================================================================

class _ReviewV2Step extends ConsumerWidget {
  const _ReviewV2Step();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            title: "Here's what we'll remember",
            subtitle: 'Tap Save & continue to finish setup.',
          ),
          const SizedBox(height: V2Spacing.space16),
          _V2GroupCard(
            children: [
              _V2ReviewRow(
                label: 'Nickname',
                value: profile.nickname?.isNotEmpty == true
                    ? profile.nickname!
                    : 'Not set',
              ),
              _V2ReviewRow(
                label: 'Age bracket',
                value: profile.ageBracket ?? 'Not set',
              ),
              _V2ReviewRow(label: 'Sex', value: profile.sex ?? 'Not set'),
              _V2ReviewRow(
                label: 'Goals',
                value: profile.goals.isEmpty
                    ? 'None selected'
                    : profile.goals
                        .map((g) => SchemaIds.goalLabels[g] ?? g)
                        .join(', '),
              ),
              _V2ReviewRow(
                label: 'Conditions',
                value: profile.conditions.isEmpty
                    ? 'None'
                    : profile.conditions
                        .map((c) => SchemaIds.conditionLabels[c] ?? c)
                        .join(', '),
              ),
              _V2ReviewRow(
                label: 'Medications',
                value: profile.drugClasses.isEmpty
                    ? 'None'
                    : profile.drugClasses
                        .map((d) => SchemaIds.drugClassLabels[d] ?? d)
                        .join(', '),
              ),
              _V2ReviewRow(
                label: 'Allergens',
                value: profile.allergens.isEmpty
                    ? 'None'
                    : '${profile.allergens.length} selected',
                last: true,
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.space24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: V2Colors.fgMuted,
              ),
              const SizedBox(width: V2Spacing.space8),
              Expanded(
                child: Text(
                  'Your health information stays on this device. We use it '
                  'to personalize recommendations — never to identify you. '
                  'Always consult healthcare professionals before making '
                  'medical decisions.',
                  style: V2Typography.caption(color: V2Colors.fgMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _V2ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  final bool last;

  const _V2ReviewRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.space16,
            vertical: V2Spacing.space12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  label.toUpperCase(),
                  style: V2Typography.eyebrow(color: V2Colors.fgMuted),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: V2Typography.body(color: V2Colors.fg),
                ),
              ),
            ],
          ),
        ),
        if (!last)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: V2Spacing.space16),
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: V2Colors.outline,
            ),
          ),
      ],
    );
  }
}
