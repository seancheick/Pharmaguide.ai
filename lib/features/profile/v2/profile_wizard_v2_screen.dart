import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_progress_dots.dart';
import 'package:pharmaguide/core/components/pg_selection_sheet.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/constants/schema_ids.dart';
import 'package:pharmaguide/core/data/clinical_profile_schema.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/onboarding_prefs.dart';

/// Phase 11.7L.B.9 — First-time profile wizard.
///
/// Sean 2026-05-16: ProfileSetup needs a hybrid pattern. For first
/// install we want a short, guided 3-step setup that earns
/// completion without overwhelming. After that, profile editing
/// happens through the dashboard (`ProfileSetupV2Screen`) where
/// each row opens a premium bottom sheet.
///
/// Wizard order (3 steps, all optional — every step has a Skip):
///
///   1. **Nickname** — inline text field. "What should we call you?"
///   2. **Basics** — Age bracket + Sex. Tile rows that open the
///      same single-select sheets the dashboard uses (so a returning
///      user editing later sees the same affordance).
///   3. **Health context** — Goals, Conditions, Allergies,
///      Medication classes. Tile rows that open the same
///      multi-select sheets as the dashboard.
///
/// ### Flow plumbing
///
/// - `OnboardingPrefs.hasSeenProfileWizard()` gates whether the
///   wizard shows. Both Save and Skip mark it seen — the wizard is
///   a one-shot.
/// - Save persists the profile via the existing `profileProvider`
///   notifier; the underlying drift columns are identical to what
///   the dashboard writes, so a user who later goes to Edit profile
///   sees their wizard picks reflected back.
/// - Final navigation is `Routes.home`. The legacy ProfileSetup
///   screen used the same destination.
///
/// ### What this screen is NOT
///
/// - Not the editor. Returning users land on
///   `ProfileSetupV2Screen` (the dashboard) via Settings → Edit
///   profile. The wizard appears only on the post-auth handoff for
///   accounts that have not yet been through it.
/// - Not the brand onboarding. That's `OnboardingV2Screen` — the
///   editorial 4-step intro that runs BEFORE auth.
class ProfileWizardV2Screen extends ConsumerStatefulWidget {
  /// When false (used by the dev gallery), the wizard preview is
  /// non-destructive: Skip / Save still navigate but do NOT mark
  /// the wizard seen, so reviewers can replay the flow freely.
  final bool autoFinish;

  const ProfileWizardV2Screen({super.key, this.autoFinish = true});

  @override
  ConsumerState<ProfileWizardV2Screen> createState() =>
      _ProfileWizardV2ScreenState();
}

class _ProfileWizardV2ScreenState extends ConsumerState<ProfileWizardV2Screen> {
  // This wizard never tears the PageView out of the tree (no
  // celebration / replay surface), so the controller can stay
  // `final`. If we ever add one, switch to the
  // mutable-recreate-on-reset pattern from OnboardingV2Screen to
  // dodge the page_view.dart:189 `positions.isNotEmpty` assertion.
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _saving = false;

  static const int _totalSteps = 3;

  static const List<String> _stepEyebrows = [
    'Step 01 / 03 · Hello',
    'Step 02 / 03 · About you',
    'Step 03 / 03 · Health context',
  ];

  static const List<String> _stepTitles = [
    'Welcome to PharmaGuide.',
    'A bit about you.',
    'Anything we should flag?',
  ];

  static const List<String> _stepHelpers = [
    'A nickname is optional, but it makes the greeting feel like '
        'yours. You can skip this and complete it later.',
    'Used only to apply the right RDA / UL ranges and safety checks '
        'on this device.',
    'PharmaGuide tailors warnings and recommendations to whatever '
        'matters to you. Every selection lives on this device only.',
  ];

  // ───────── navigation ─────────

  Future<void> _next() async {
    if (_currentStep < _totalSteps - 1) {
      await _pageController.nextPage(
        duration: V2Motion.base,
        curve: V2Motion.smooth,
      );
    } else {
      await _save();
    }
  }

  Future<void> _back() async {
    if (_currentStep == 0) return;
    await _pageController.previousPage(
      duration: V2Motion.base,
      curve: V2Motion.smooth,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    unawaited(HapticFeedback.mediumImpact());
    await ref.read(profileProvider.notifier).saveToDb();
    if (widget.autoFinish) {
      await OnboardingPrefs.markProfileWizardSeen();
    }
    if (!mounted) return;
    PGToast.show(
      context,
      "You're set. Profile saved on this device.",
      variant: PGToastVariant.success,
      duration: const Duration(milliseconds: 1600),
    );
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;
    if (widget.autoFinish) {
      GoRouter.of(context).go(Routes.home);
    } else {
      GoRouter.of(context).go('/dev/v2');
    }
  }

  Future<void> _skip() async {
    if (widget.autoFinish) {
      // Skip still counts as "user has seen the wizard" — we never
      // want to nag. The dashboard remains available from Settings
      // → Edit profile so they can complete it any time.
      await OnboardingPrefs.markProfileWizardSeen();
    }
    if (!mounted) return;
    GoRouter.of(context).go(widget.autoFinish ? Routes.home : '/dev/v2');
  }

  // ───────── sheets — reuse the dashboard helpers verbatim so the ──
  //           two surfaces stay in lockstep ────────────────────────

  Future<void> _openAgeSheet() async {
    final profile = ref.read(profileProvider);
    final ageOptions = <PGSelectionOption>[
      for (final b in SchemaIds.ageBrackets)
        PGSelectionOption(id: b, label: '$b years'),
      const PGSelectionOption(
        id: 'Prefer not to say',
        label: 'Prefer not to say',
      ),
    ];
    final result = await showPGSelectionSheet(
      context: context,
      eyebrow: 'Age bracket',
      title: 'Roughly how old are you?',
      helperText:
          'Recommended intake ranges shift with age. Used only on '
          'this device to apply the right RDA and upper limits.',
      options: ageOptions,
      initialSelection: profile.ageBracket == null
          ? <String>{}
          : {profile.ageBracket!},
      singleSelect: true,
      layout: PGSheetLayout.rows,
      dismissLabel: "I'll add this later",
    );
    if (result == null || !mounted) return;
    if (result.selected.isEmpty) return;
    ref.read(profileProvider.notifier).setAgeBracket(result.selected.first);
  }

  Future<void> _openSexSheet() async {
    final profile = ref.read(profileProvider);
    const sexOptions = [
      PGSelectionOption(id: 'Female', label: 'Female'),
      PGSelectionOption(id: 'Male', label: 'Male'),
      PGSelectionOption(id: 'Prefer not to say', label: 'Prefer not to say'),
    ];
    final result = await showPGSelectionSheet(
      context: context,
      eyebrow: 'Sex for safety checks',
      title: 'Which dosing ranges apply?',
      helperText:
          'Used for safety checks where dosage limits, '
          'pregnancy-related cautions, or nutrient guidance can '
          'differ. Stored only on this device.',
      options: sexOptions,
      initialSelection: profile.sex == null ? <String>{} : {profile.sex!},
      singleSelect: true,
      layout: PGSheetLayout.rows,
      dismissLabel: "I'll add this later",
    );
    if (result == null || !mounted) return;
    if (result.selected.isEmpty) return;
    ref.read(profileProvider.notifier).setSex(result.selected.first);
  }

  Future<void> _openGoalsSheet() async {
    final profile = ref.read(profileProvider);
    final sortedGoals = List<String>.from(SchemaIds.goals)
      ..sort((a, b) {
        const order = {'high': 0, 'medium': 1, 'low': 2};
        final pa = order[SchemaIds.goalPriorities[a]] ?? 2;
        final pb = order[SchemaIds.goalPriorities[b]] ?? 2;
        return pa.compareTo(pb);
      });
    final result = await showPGSelectionSheet(
      context: context,
      eyebrow: 'Goals',
      title: 'What are you focused on?',
      helperText:
          'Helps PharmaGuide show warnings and recommendations that '
          'match what matters to you. Used only on this device.',
      options: sortedGoals
          .map(
            (id) => PGSelectionOption(
              id: id,
              label: SchemaIds.goalLabels[id] ?? id,
            ),
          )
          .toList(),
      initialSelection: profile.goalsForEvaluator.toSet(),
      initialNoneSelected: profile.hasGoalNone,
      noneLabel: 'No specific goal right now',
      noneSubtitle:
          "You'll still get safety warnings — just not goal recommendations.",
      maxSelection: 2,
      maxSelectionHint: 'Pick up to 2.',
      searchable: true,
    );
    if (result == null || !mounted) return;
    ref
        .read(profileProvider.notifier)
        .setGoalsWithNone(
          selected: result.selected,
          noneSelected: result.noneSelected,
        );
  }

  Future<void> _openConditionsSheet() async {
    final profile = ref.read(profileProvider);
    final ClinicalProfileSchema schema;
    final loaded = ref.read(clinicalProfileSchemaProvider).asData?.value;
    if (loaded != null) {
      schema = loaded;
    } else {
      try {
        schema = await ref.read(clinicalProfileSchemaProvider.future);
      } on Object {
        if (mounted) {
          PGToast.show(
            context,
            'Clinical profile options are unavailable. Please try again.',
            variant: PGToastVariant.error,
          );
        }
        return;
      }
    }
    if (!mounted) return;
    final result = await showPGSelectionSheet(
      context: context,
      eyebrow: 'Health conditions',
      title: 'Anything we should know about?',
      helperText:
          'Used only to personalize safety checks on this device. '
          'PharmaGuide does not diagnose — these flag interactions '
          'worth a conversation with your clinician.',
      options: schema.selectableConditions
          .map(
            (condition) =>
                PGSelectionOption(id: condition.id, label: condition.label),
          )
          .toList(),
      initialSelection: profile.conditionsForEvaluator.toSet(),
      initialNoneSelected: profile.hasConditionNone,
      noneLabel: 'None of these',
      noneSubtitle:
          'Skip and come back any time — your profile is fully editable.',
      searchable: true,
    );
    if (result == null || !mounted) return;
    ref
        .read(profileProvider.notifier)
        .setConditionsWithNone(
          selected: result.selected,
          noneSelected: result.noneSelected,
        );
  }

  Future<void> _openAllergensSheet() async {
    final profile = ref.read(profileProvider);
    final result = await showPGSelectionSheet(
      context: context,
      eyebrow: 'Allergies / sensitivities',
      title: 'Any allergies we should flag?',
      helperText:
          'PharmaGuide highlights products that contain — or may '
          'contain — what you select. Stored only on this device.',
      options: SchemaIds.allergens
          .map(
            (id) => PGSelectionOption(
              id: id,
              label: SchemaIds.allergenLabels[id] ?? id,
            ),
          )
          .toList(),
      initialSelection: profile.allergensForEvaluator.toSet(),
      initialNoneSelected: profile.hasAllergenNone,
      noneLabel: 'No known allergies',
      noneSubtitle:
          "We won't surface allergen flags — you can change this any time.",
      searchable: true,
    );
    if (result == null || !mounted) return;
    ref
        .read(profileProvider.notifier)
        .setAllergensWithNone(
          selected: result.selected,
          noneSelected: result.noneSelected,
        );
  }

  Future<void> _openMedicationsSheet() async {
    final profile = ref.read(profileProvider);
    final result = await showPGSelectionSheet(
      context: context,
      eyebrow: 'Medication classes',
      title: 'Anything you take regularly?',
      helperText:
          'Helps PharmaGuide flag supplement–medication interactions. '
          'Pick the types you take — kept on this device only.',
      options: SchemaIds.drugClasses
          .map(
            (id) => PGSelectionOption(
              id: id,
              label: SchemaIds.drugClassLabels[id] ?? id,
            ),
          )
          .toList(),
      initialSelection: profile.drugClassesForEvaluator.toSet(),
      initialNoneSelected: profile.hasDrugClassNone,
      noneLabel: 'No medications right now',
      noneSubtitle: 'You can update this whenever something changes.',
      searchable: true,
    );
    if (result == null || !mounted) return;
    ref
        .read(profileProvider.notifier)
        .setDrugClassesWithNone(
          selected: result.selected,
          noneSelected: result.noneSelected,
        );
  }

  // ───────── build ─────────

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isLastStep = _currentStep == _totalSteps - 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: v2SystemOverlay(context),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _TopRow(
                canGoBack: _currentStep > 0,
                onBack: _back,
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
                  children: [
                    _NicknameStep(
                      eyebrow: _stepEyebrows[0],
                      title: _stepTitles[0],
                      helper: _stepHelpers[0],
                    ),
                    _BasicsStep(
                      eyebrow: _stepEyebrows[1],
                      title: _stepTitles[1],
                      helper: _stepHelpers[1],
                      onTapAge: _openAgeSheet,
                      onTapSex: _openSexSheet,
                    ),
                    _HealthContextStep(
                      eyebrow: _stepEyebrows[2],
                      title: _stepTitles[2],
                      helper: _stepHelpers[2],
                      onTapGoals: _openGoalsSheet,
                      onTapConditions: _openConditionsSheet,
                      onTapAllergens: _openAllergensSheet,
                      onTapMedications: _openMedicationsSheet,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  V2Spacing.space24,
                  V2Spacing.space8,
                  V2Spacing.space24,
                  mq.padding.bottom + V2Spacing.space16,
                ),
                child: PGPillButton(
                  label: _saving
                      ? 'Saving…'
                      : (isLastStep ? 'Save & continue' : 'Continue'),
                  expand: true,
                  onPressed: _saving ? null : _next,
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
// Top row — back chip (left), eyebrow gap (centered visually by the
// progress dots below), Skip ghost CTA (right).
// =============================================================================

class _TopRow extends StatelessWidget {
  final bool canGoBack;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  const _TopRow({
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
            const Spacer(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSkip,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.space8,
                ),
                child: Text(
                  'Skip for now',
                  style: V2Typography.label(color: V2Colors.fgMuted),
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
// Step 1 — Nickname. Inline editable field with the exact copy
// contract Sean approved on the dashboard tile, surfaced here a
// little larger so the first impression is "we want to learn your
// name," not "fill out a profile form."
// =============================================================================

class _NicknameStep extends ConsumerStatefulWidget {
  final String eyebrow;
  final String title;
  final String helper;

  const _NicknameStep({
    required this.eyebrow,
    required this.title,
    required this.helper,
  });

  @override
  ConsumerState<_NicknameStep> createState() => _NicknameStepState();
}

class _NicknameStepState extends ConsumerState<_NicknameStep> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(profileProvider).nickname ?? '',
    );
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
          _StepIntro(
            eyebrow: widget.eyebrow,
            title: widget.title,
            helper: widget.helper,
          ),
          const SizedBox(height: V2Spacing.space32),
          Text('Nickname', style: V2Typography.label(color: V2Colors.fg)),
          const SizedBox(height: V2Spacing.space8),
          AnimatedContainer(
            duration: V2Motion.fast,
            curve: V2Motion.smooth,
            padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space16),
            decoration: BoxDecoration(
              color: V2Colors.surface,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(
                color: focused ? V2Colors.accent : V2Colors.outline,
                width: focused ? 1.5 : 1.0,
              ),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: 1,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'What should we call you?',
                hintStyle: V2Typography.body(color: V2Colors.fgSubtle),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: V2Spacing.space16,
                ),
                isCollapsed: true,
                isDense: true,
              ),
              style: V2Typography.titleSm(color: V2Colors.fg),
              cursorColor: V2Colors.accent,
              cursorWidth: 1.5,
              onChanged: (value) =>
                  ref.read(profileProvider.notifier).setNickname(value),
            ),
          ),
          const SizedBox(height: V2Spacing.space12),
          Text(
            'Used only to personalize your greeting.',
            style: V2Typography.caption(color: V2Colors.fgMuted),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Step 2 — Basics. Age + Sex as tile rows that open the same
// single-select sheets the dashboard uses, so muscle memory carries
// forward between first-time setup and later editing.
// =============================================================================

class _BasicsStep extends ConsumerWidget {
  final String eyebrow;
  final String title;
  final String helper;
  final VoidCallback onTapAge;
  final VoidCallback onTapSex;

  const _BasicsStep({
    required this.eyebrow,
    required this.title,
    required this.helper,
    required this.onTapAge,
    required this.onTapSex,
  });

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
          _StepIntro(eyebrow: eyebrow, title: title, helper: helper),
          const SizedBox(height: V2Spacing.space32),
          _WizardTile(
            eyebrow: 'Age bracket',
            title: profile.ageBracket == null
                ? 'Tap to pick'
                : '${profile.ageBracket} years',
            body: profile.ageBracket == null
                ? 'Used for RDA / UL scoring.'
                : null,
            icon: Icons.cake_outlined,
            onTap: onTapAge,
          ),
          const SizedBox(height: V2Spacing.space12),
          _WizardTile(
            eyebrow: 'Sex for safety checks',
            title: profile.sex ?? 'Tap to pick',
            body: profile.sex == null ? 'Used for accurate dosing.' : null,
            icon: Icons.person_outline_rounded,
            onTap: onTapSex,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Step 3 — Health context. All four multi-select tiles in one
// scrollable surface so the user can sweep through.
// =============================================================================

class _HealthContextStep extends ConsumerWidget {
  final String eyebrow;
  final String title;
  final String helper;
  final VoidCallback onTapGoals;
  final VoidCallback onTapConditions;
  final VoidCallback onTapAllergens;
  final VoidCallback onTapMedications;

  const _HealthContextStep({
    required this.eyebrow,
    required this.title,
    required this.helper,
    required this.onTapGoals,
    required this.onTapConditions,
    required this.onTapAllergens,
    required this.onTapMedications,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final clinicalSchema = ref
        .watch(clinicalProfileSchemaProvider)
        .asData
        ?.value;
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
          _StepIntro(eyebrow: eyebrow, title: title, helper: helper),
          const SizedBox(height: V2Spacing.space32),
          _WizardTile(
            eyebrow: 'Health goals',
            title: _goalsTitle(profile),
            body: profile.goals.isEmpty
                ? 'Helps personalize your recommendations.'
                : null,
            icon: Icons.flag_outlined,
            onTap: onTapGoals,
          ),
          const SizedBox(height: V2Spacing.space12),
          _WizardTile(
            eyebrow: 'Health conditions',
            title: _conditionsTitle(profile, clinicalSchema),
            body: profile.conditions.isEmpty
                ? 'Used to flag interactions worth a clinician chat.'
                : null,
            icon: Icons.favorite_outline_rounded,
            onTap: onTapConditions,
          ),
          const SizedBox(height: V2Spacing.space12),
          _WizardTile(
            eyebrow: 'Allergies / sensitivities',
            title: _allergensTitle(profile),
            body: profile.allergens.isEmpty
                ? "PharmaGuide will flag what you can't take."
                : null,
            icon: Icons.warning_amber_outlined,
            onTap: onTapAllergens,
          ),
          const SizedBox(height: V2Spacing.space12),
          _WizardTile(
            eyebrow: 'Medication classes',
            title: _medsTitle(profile),
            body: profile.drugClasses.isEmpty
                ? 'Helps flag supplement–medication interactions.'
                : null,
            icon: Icons.medication_outlined,
            onTap: onTapMedications,
          ),
        ],
      ),
    );
  }

  String _goalsTitle(ProfileState p) {
    if (p.hasGoalNone) return 'No specific goal right now';
    if (p.goals.isEmpty) return 'Tap to choose up to 2';
    return p.goals
        .where((g) => g != SchemaIds.goalNone)
        .map((g) => SchemaIds.goalLabels[g] ?? g)
        .join(' · ');
  }

  String _conditionsTitle(ProfileState p, ClinicalProfileSchema? schema) {
    if (p.hasConditionNone) return 'None of these';
    final n = p.conditionsForEvaluator.length;
    if (n == 0) return 'Tap to pick';
    if (n == 1) {
      return schema?.conditionLabel(p.conditionsForEvaluator.first) ??
          '1 selected';
    }
    return '$n selected';
  }

  String _allergensTitle(ProfileState p) {
    if (p.hasAllergenNone) return 'No known allergies';
    final n = p.allergensForEvaluator.length;
    if (n == 0) return 'Tap to pick';
    if (n == 1) {
      return SchemaIds.allergenLabels[p.allergensForEvaluator.first] ??
          p.allergensForEvaluator.first;
    }
    return '$n selected';
  }

  String _medsTitle(ProfileState p) {
    if (p.hasDrugClassNone) return 'No medications right now';
    final n = p.drugClassesForEvaluator.length;
    if (n == 0) return 'Tap to pick';
    if (n == 1) {
      return SchemaIds.drugClassLabels[p.drugClassesForEvaluator.first] ??
          p.drugClassesForEvaluator.first;
    }
    return '$n selected';
  }
}

// =============================================================================
// Shared step intro — mono-caps eyebrow with step counter and label
// (e.g. "STEP 02 / 03 · ABOUT YOU"), Newsreader serif title, body
// helper paragraph. Same typographic shape as the dashboard header
// so a returning user reading the wizard once before editing later
// finds the two surfaces tonally identical.
// =============================================================================

class _StepIntro extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String helper;

  const _StepIntro({
    required this.eyebrow,
    required this.title,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PGEyebrow(eyebrow),
        const SizedBox(height: V2Spacing.space12),
        Text(title, style: V2Typography.displaySm(color: V2Colors.fg)),
        const SizedBox(height: V2Spacing.space12),
        Text(helper, style: V2Typography.body(color: V2Colors.fgMuted)),
      ],
    );
  }
}

// =============================================================================
// Wizard tile — mirrors the dashboard `_GroupTile` exactly so the
// wizard's interaction model carries over to the dashboard without
// retraining the user. Same icon square, eyebrow, serif title, body
// caption, and chevron-right trailing affordance.
// =============================================================================

class _WizardTile extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? body;
  final IconData icon;
  final VoidCallback onTap;

  const _WizardTile({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Colors.surface,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(color: V2Colors.outline),
            boxShadow: V2Shadows.sm,
          ),
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space16,
            V2Spacing.space16,
            V2Spacing.space12,
            V2Spacing.space16,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: V2Colors.accentTint,
                  borderRadius: BorderRadius.circular(V2Spacing.space8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: V2Colors.accent),
              ),
              const SizedBox(width: V2Spacing.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PGEyebrow(eyebrow, color: V2Colors.fgMuted),
                    const SizedBox(height: V2Spacing.space4),
                    Text(
                      title,
                      style: V2Typography.titleSm(color: V2Colors.fg),
                    ),
                    if (body != null) ...[
                      const SizedBox(height: V2Spacing.space4),
                      Text(
                        body!,
                        style: V2Typography.caption(color: V2Colors.fgMuted),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: V2Colors.fgSubtle),
            ],
          ),
        ),
      ),
    );
  }
}
