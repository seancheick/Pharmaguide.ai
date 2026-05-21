import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_selection_sheet.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/constants/schema_ids.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

/// Phase 11.7L.B.6 — v2 ProfileSetup restructure.
///
/// Replaces the legacy PageView "5-step wizard" with a single
/// scrollable settings-style surface where each health-context group
/// (Goals, Conditions, Allergies, Medications) is a tile row that
/// opens a `PGSelectionSheet` for editing. Basic profile details
/// (nickname, age bracket, sex) stay inline at the bottom — they
/// don't justify a sheet of their own.
///
/// ### Why this shape
/// Sean's directive Phase 11.7L.B.6: the page-per-step flow felt like
/// a Material onboarding wizard, not the calm clinical-intelligence
/// editor the rest of the app is becoming. The single-scroll + sheet
/// pattern mirrors the website's profile settings and the iOS
/// Settings app: see everything at once, drill into the one group
/// you came to edit, return.
///
/// ### Information architecture
/// Allergies move from a separate step to live alongside Health
/// conditions and Medications — they're health context, not a
/// disconnected setting. The new order:
///
///   1. Goals
///   2. Health conditions
///   3. Allergies / sensitivities
///   4. Medications
///   5. Basic info (nickname + age bracket + sex)
///
/// ### Explicit "None"
/// Each of the four sheet-backed groups exposes a "None" affordance
/// at the top of its sheet. Selecting None clears the rest of the
/// draft selection; tapping any real chip clears the None pick. The
/// resolved (selected, noneSelected) pair flows through the
/// `set*WithNone` notifier methods which persist the appropriate
/// sentinel ID from `SchemaIds`. The tile summary surfaces the
/// explicit "No specific goal right now" / "No known allergies"
/// copy when set — never an ambiguous empty state.
///
/// ### What did NOT change (intentional)
/// - `profileProvider` + `saveToDb` semantics — same single drift
///   write before navigating to home.
/// - `SchemaIds.goals` / `conditions` / `drugClasses` / `allergens`
///   (full lists used; nothing curated down).
/// - Skip → goes home without saving.
/// - Save & continue → writes the profile, then goes home.
///
/// ### Removed
/// - PageView, NeverScrollableScrollPhysics body.
/// - LinearProgressIndicator (legacy progress bar — long deprecated
///   per Sean) and PGProgressDots from the v2 first-pass mirror.
/// - Step counter eyebrow / step labels — there are no steps.
/// - The legacy curated 13-chip allergen list (Shellfish / Gluten-
///   free as group toggles). The sheet now exposes all 17 canonical
///   allergens individually.
class ProfileSetupV2Screen extends ConsumerStatefulWidget {
  const ProfileSetupV2Screen({super.key});

  @override
  ConsumerState<ProfileSetupV2Screen> createState() =>
      _ProfileSetupV2ScreenState();
}

class _ProfileSetupV2ScreenState extends ConsumerState<ProfileSetupV2Screen> {
  bool _saving = false;

  // ───────── nav helpers ─────────

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    unawaited(HapticFeedback.mediumImpact());
    // Same await-the-drift-write semantics as the legacy screen — see
    // `ProfileSetupScreen._save` for the race-condition rationale.
    await ref.read(profileProvider.notifier).saveToDb();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    // We deliberately don't await `closed` here — the brief delayed
    // navigation below gives the user enough time to read the
    // confirmation without coupling save flow to snackbar dismissal.
    unawaited(
      messenger
          .showSnackBar(
            SnackBar(
              content: Text(
                'Profile saved on this device.',
                style: V2Typography.bodySm(color: V2Colors.bg),
              ),
              backgroundColor: V2Colors.accent,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(V2Spacing.space16),
              duration: const Duration(milliseconds: 1600),
            ),
          )
          .closed,
    );
    // Brief hold so the snackbar registers before the route swap.
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;
    GoRouter.of(context).go(Routes.home);
  }

  void _skip() {
    GoRouter.of(context).go(Routes.home);
  }

  // ───────── sheet openers ─────────

  Future<void> _openGoalsSheet() async {
    final profile = ref.read(profileProvider);
    // Goal priority-sort: high → medium → low. Same ordering the
    // legacy screen used so analytics + recommender stay consistent.
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
      noneSubtitle: "You'll still get safety warnings — just not goal "
          'recommendations.',
      maxSelection: 2,
      maxSelectionHint: 'Pick up to 2.',
      searchable: true,
    );
    if (result == null || !mounted) return;
    ref.read(profileProvider.notifier).setGoalsWithNone(
          selected: result.selected,
          noneSelected: result.noneSelected,
        );
  }

  Future<void> _openConditionsSheet() async {
    final profile = ref.read(profileProvider);
    final result = await showPGSelectionSheet(
      context: context,
      eyebrow: 'Health conditions',
      title: 'Anything we should know about?',
      helperText:
          'Used only to personalize safety checks on this device. '
          'PharmaGuide does not diagnose — these flag interactions '
          'worth a conversation with your clinician.',
      options: SchemaIds.conditions
          .map(
            (id) => PGSelectionOption(
              id: id,
              label: SchemaIds.conditionLabels[id] ?? id,
            ),
          )
          .toList(),
      initialSelection: profile.conditionsForEvaluator.toSet(),
      initialNoneSelected: profile.hasConditionNone,
      noneLabel: 'None of these',
      noneSubtitle: 'Skip and come back any time — your profile is '
          'fully editable.',
      searchable: true,
    );
    if (result == null || !mounted) return;
    ref.read(profileProvider.notifier).setConditionsWithNone(
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
      noneSubtitle: "We won't surface allergen flags — you can change "
          'this any time.',
      searchable: true,
    );
    if (result == null || !mounted) return;
    ref.read(profileProvider.notifier).setAllergensWithNone(
          selected: result.selected,
          noneSelected: result.noneSelected,
        );
  }

  Future<void> _openMedicationsSheet() async {
    final profile = ref.read(profileProvider);
    final result = await showPGSelectionSheet(
      context: context,
      eyebrow: 'Medications',
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
    ref.read(profileProvider.notifier).setDrugClassesWithNone(
          selected: result.selected,
          noneSelected: result.noneSelected,
        );
  }

  // ───────── demographic sheets (single-select, required) ─────────
  //
  // Sean 2026-05-16: chips can feel like casual tags here, and a
  // rolling picker reads like DOB collection. Both sheets use the
  // `PGSheetLayout.rows` variant so each option lands as a clean
  // answer, with a "why we ask" helper line at the top and an
  // explicit "I'll add this later" dismiss action so the user can
  // bail without swiping down.

  Future<void> _openAgeSheet() async {
    final profile = ref.read(profileProvider);
    // The schema is purely numeric brackets; "Prefer not to say" is
    // tacked on here for the UI. Picked → stored as the literal
    // string in `profile.ageBracket`; the matcher falls back to the
    // most conservative RDA/UL ranges for non-numeric brackets.
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
    // Sean 2026-05-16: drop "Other" from the v2 sheet — Female /
    // Male / Prefer not to say is the respectful minimum surface
    // for clinical dosing logic. The underlying schema still
    // accepts "Other" (legacy profiles preserve it on load), but
    // the v2 picker doesn't surface it as a new choice.
    const sexOptions = [
      PGSelectionOption(id: 'Female', label: 'Female'),
      PGSelectionOption(id: 'Male', label: 'Male'),
      PGSelectionOption(
        id: 'Prefer not to say',
        label: 'Prefer not to say',
      ),
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
      initialSelection:
          profile.sex == null ? <String>{} : {profile.sex!},
      singleSelect: true,
      layout: PGSheetLayout.rows,
      dismissLabel: "I'll add this later",
    );
    if (result == null || !mounted) return;
    if (result.selected.isEmpty) return;
    ref.read(profileProvider.notifier).setSex(result.selected.first);
  }

  // ───────── build ─────────

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final mq = MediaQuery.of(context);

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
          bottom: false,
          child: Stack(
            children: [
              ListView(
                padding: EdgeInsets.fromLTRB(
                  V2Spacing.space24,
                  V2Spacing.space12,
                  V2Spacing.space24,
                  mq.padding.bottom + 96, // room for the sticky Save bar
                ),
                children: [
                  _TopRow(onSkip: _skip),
                  const SizedBox(height: V2Spacing.space24),
                  const _Header(),
                  const SizedBox(height: V2Spacing.space32),
                  // Order per Sean 2026-05-16: Nickname first, then
                  // the four health-context groups, then demographics
                  // (age / sex) which are required for scoring but
                  // less expressive than the health groups.
                  const _NicknameTile(),
                  const SizedBox(height: V2Spacing.space12),
                  _GroupTile(
                    eyebrow: 'Health goals',
                    title: _goalsSummaryTitle(profile),
                    body: _goalsSummaryBody(profile),
                    icon: Icons.flag_outlined,
                    onTap: _openGoalsSheet,
                  ),
                  const SizedBox(height: V2Spacing.space12),
                  _GroupTile(
                    eyebrow: 'Health conditions',
                    title: _conditionsSummaryTitle(profile),
                    body: _conditionsSummaryBody(profile),
                    icon: Icons.favorite_outline_rounded,
                    onTap: _openConditionsSheet,
                  ),
                  const SizedBox(height: V2Spacing.space12),
                  _GroupTile(
                    eyebrow: 'Allergies / sensitivities',
                    title: _allergensSummaryTitle(profile),
                    body: _allergensSummaryBody(profile),
                    icon: Icons.warning_amber_outlined,
                    onTap: _openAllergensSheet,
                  ),
                  const SizedBox(height: V2Spacing.space12),
                  _GroupTile(
                    eyebrow: 'Medication classes',
                    title: _medsSummaryTitle(profile),
                    body: _medsSummaryBody(profile),
                    icon: Icons.medication_outlined,
                    onTap: _openMedicationsSheet,
                  ),
                  const SizedBox(height: V2Spacing.space12),
                  _GroupTile(
                    eyebrow: 'Age bracket',
                    title: _ageSummaryTitle(profile),
                    body: _ageSummaryBody(profile),
                    icon: Icons.cake_outlined,
                    onTap: _openAgeSheet,
                  ),
                  const SizedBox(height: V2Spacing.space12),
                  _GroupTile(
                    eyebrow: 'Sex',
                    title: _sexSummaryTitle(profile),
                    body: _sexSummaryBody(profile),
                    icon: Icons.person_outline_rounded,
                    onTap: _openSexSheet,
                  ),
                  const SizedBox(height: V2Spacing.space24),
                  const _PrivacyFooter(),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _StickySaveBar(
                  saving: _saving,
                  onSave: _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────── tile summary builders ─────────

  String _goalsSummaryTitle(ProfileState p) {
    if (p.hasGoalNone) return 'No specific goal right now';
    if (p.goals.isEmpty) return 'Tap to choose up to 2';
    return p.goals
        .where((g) => g != SchemaIds.goalNone)
        .map((g) => SchemaIds.goalLabels[g] ?? g)
        .join(' · ');
  }

  String? _goalsSummaryBody(ProfileState p) {
    if (p.hasGoalNone) return null;
    if (p.goals.isEmpty) return 'Helps personalize your recommendations.';
    return null;
  }

  String _conditionsSummaryTitle(ProfileState p) {
    if (p.hasConditionNone) return 'None of these';
    final n = p.conditionsForEvaluator.length;
    if (n == 0) return 'Tap to pick';
    if (n == 1) {
      return SchemaIds.conditionLabels[p.conditionsForEvaluator.first] ??
          p.conditionsForEvaluator.first;
    }
    return '$n selected';
  }

  String? _conditionsSummaryBody(ProfileState p) {
    if (p.hasConditionNone) return null;
    if (p.conditions.isEmpty) {
      return 'Used to flag interactions worth a clinician chat.';
    }
    return null;
  }

  String _allergensSummaryTitle(ProfileState p) {
    if (p.hasAllergenNone) return 'No known allergies';
    final n = p.allergensForEvaluator.length;
    if (n == 0) return 'Tap to pick';
    if (n == 1) {
      return SchemaIds.allergenLabels[p.allergensForEvaluator.first] ??
          p.allergensForEvaluator.first;
    }
    return '$n selected';
  }

  String? _allergensSummaryBody(ProfileState p) {
    if (p.hasAllergenNone) return null;
    if (p.allergens.isEmpty) {
      return "PharmaGuide will flag what you can't take.";
    }
    return null;
  }

  String _medsSummaryTitle(ProfileState p) {
    if (p.hasDrugClassNone) return 'No medications right now';
    final n = p.drugClassesForEvaluator.length;
    if (n == 0) return 'Tap to pick';
    if (n == 1) {
      return SchemaIds.drugClassLabels[p.drugClassesForEvaluator.first]
          ?? p.drugClassesForEvaluator.first;
    }
    return '$n selected';
  }

  String? _medsSummaryBody(ProfileState p) {
    if (p.hasDrugClassNone) return null;
    if (p.drugClasses.isEmpty) {
      return 'Helps flag supplement–medication interactions.';
    }
    return null;
  }

  String _ageSummaryTitle(ProfileState p) {
    if (p.ageBracket == null) return 'Tap to pick';
    return '${p.ageBracket} years';
  }

  String? _ageSummaryBody(ProfileState p) {
    if (p.ageBracket == null) return 'Used for RDA / UL scoring.';
    return null;
  }

  String _sexSummaryTitle(ProfileState p) {
    return p.sex ?? 'Tap to pick';
  }

  String? _sexSummaryBody(ProfileState p) {
    if (p.sex == null) return 'Used for accurate dosing.';
    return null;
  }
}

// =============================================================================
// Top row — page title + ghost Skip CTA. No back button: profile setup
// is reached from Settings → "Edit profile" (push) or from a fresh
// install (replace), so popping or going home is the right exit.
// =============================================================================

class _TopRow extends StatelessWidget {
  final VoidCallback onSkip;
  const _TopRow({required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const PGEyebrow('Profile'),
        const Spacer(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSkip,
          child: Text(
            'Skip for now',
            style: V2Typography.label(color: V2Colors.fgMuted),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Tell us what matters\nto you.",
          style: V2Typography.displaySm(color: V2Colors.fg),
        ),
        const SizedBox(height: V2Spacing.space12),
        Text(
          'Used only to personalize safety checks on this device. '
          'You can skip this and complete it later.',
          style: V2Typography.body(color: V2Colors.fgMuted),
        ),
      ],
    );
  }
}

// =============================================================================
// Group tile — eyebrow + serif title + optional body + leading icon
// + trailing chevron. Tapping opens the corresponding selection
// sheet. Visual: cream surface with hairline outline and soft sm
// shadow, same surface treatment as `_ProfileHero` in Settings.
// =============================================================================

class _GroupTile extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? body;
  final IconData icon;
  final VoidCallback onTap;

  const _GroupTile({
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
        child: AnimatedContainer(
          duration: V2Motion.fast,
          curve: V2Motion.smooth,
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
              const Icon(
                Icons.chevron_right_rounded,
                color: V2Colors.fgSubtle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Nickname tile — the only dashboard row whose value is edited in
// place (text input) rather than via a bottom-sheet selector. The
// outer card matches `_GroupTile` exactly (icon + eyebrow + body
// space) so all six dashboard rows visually agree.
//
// Sean 2026-05-16 — explicit copy contract:
//   Label       : "Nickname"
//   Placeholder : "What should we call you?"  (single line — must
//                                              not wrap or overflow
//                                              the input box)
//   Helper      : "Used only to personalize your greeting."
//
// The Home greeting reads `profile.nickname` directly: filled →
// "Good morning, Sean", empty → "Good morning" / "Hello there".
// =============================================================================

class _NicknameTile extends ConsumerStatefulWidget {
  const _NicknameTile();

  @override
  ConsumerState<_NicknameTile> createState() => _NicknameTileState();
}

class _NicknameTileState extends ConsumerState<_NicknameTile> {
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
    return Container(
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space16,
        V2Spacing.space16,
        V2Spacing.space16,
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
            child: const Icon(
              Icons.waving_hand_outlined,
              size: 18,
              color: V2Colors.accent,
            ),
          ),
          const SizedBox(width: V2Spacing.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PGEyebrow('Nickname', color: V2Colors.fgMuted),
                const SizedBox(height: V2Spacing.space4),
                // Inline editable field. No background fill on the
                // text itself — the surrounding tile is already
                // cream, and an inner border would read as a Material
                // form field. Focus is communicated by the cursor +
                // a hairline accent underline below the input.
                AnimatedContainer(
                  duration: V2Motion.fast,
                  curve: V2Motion.smooth,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: focused
                            ? V2Colors.accent
                            : V2Colors.outline,
                        width: focused ? 1.5 : 1.0,
                      ),
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
                        vertical: V2Spacing.space8,
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
                const SizedBox(height: V2Spacing.space8),
                Text(
                  'Used only to personalize your greeting.',
                  style: V2Typography.caption(color: V2Colors.fgMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Privacy footer — calm reassurance, body small + muted color, no
// bordered Material container. Mirrors the Settings footer.
// =============================================================================

class _PrivacyFooter extends StatelessWidget {
  const _PrivacyFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space4),
      child: Row(
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
              'Your health information stays on this device. Used only '
              'to personalize safety checks — never to identify you.',
              style: V2Typography.caption(color: V2Colors.fgMuted),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Sticky Save bar — sits over the bottom of the scroll, cream
// background with a soft top divider so content reads through. The
// pill CTA always shows "Save & continue" since this screen never
// has a "you must fill X first" gate (the underlying provider
// accepts any partial profile).
// =============================================================================

class _StickySaveBar extends StatelessWidget {
  final bool saving;
  final VoidCallback onSave;

  const _StickySaveBar({
    required this.saving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: V2Colors.bg,
        border: Border(top: BorderSide(color: V2Colors.outline)),
      ),
      padding: EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space12,
        V2Spacing.space24,
        MediaQuery.of(context).padding.bottom + V2Spacing.space12,
      ),
      child: PGPillButton(
        label: saving ? 'Saving…' : 'Save & continue',
        expand: true,
        onPressed: saving ? null : onSave,
      ),
    );
  }
}
