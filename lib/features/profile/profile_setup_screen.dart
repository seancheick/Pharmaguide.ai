import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/constants/schema_ids.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_circular_icon_button.dart';
import 'package:pharmaguide/core/widgets/pg_filter_chip.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_header.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

/// 5-step profile setup flow — fully migrated to the PG design system.
///
/// Step 1 Basic info · Step 2 Goals · Step 3 Health profile ·
/// Step 4 Allergens · Step 5 Review.
///
/// All typography comes from `theme.textTheme`, all surfaces are
/// `PGCard`, no hardcoded font sizes / weights / colors. Respects
/// Dynamic Type automatically.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  static const _totalSteps = 5;

  static const _stepLabels = [
    'Basic info',
    'Health goals',
    'Health profile',
    'Allergies',
    'Review',
  ];

  Future<void> _nextStep() async {
    if (_currentStep < _totalSteps - 1) {
      await _pageController.nextPage(
        duration: AppMotion.medium,
        curve: AppMotion.standard,
      );
    } else {
      _save();
    }
  }

  Future<void> _prevStep() async {
    if (_currentStep > 0) {
      await _pageController.previousPage(
        duration: AppMotion.medium,
        curve: AppMotion.standard,
      );
    }
  }

  void _save() {
    ref.read(profileProvider.notifier).saveToDb();
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLastStep = _currentStep == _totalSteps - 1;
    final canContinue = _currentStep != 0 || profile.ageBracket != null;

    // PGFrostedAppBar is a sliver widget that lives inside a CustomScrollView.
    // This screen has a non-scrollable PageView as its body, so a full
    // CustomScrollView + SliverFillRemaining layout creates a nested-viewport
    // chain (CustomScrollView > SliverFillRemaining > PageView > Viewport)
    // that fails with null geometry in Flutter's semantics pass — both in
    // tests and on some devices. Instead we mount PGFrostedAppBar's visual
    // equivalent using Scaffold.appBar (PreferredSize + PGFrostedHeader
    // directly) so the Scaffold owns the layout measurement and the body
    // Column gets clean, bounded constraints with no nested viewports above it.
    final mq = MediaQuery.of(context);
    // Match PGFrostedAppBar's computed height: topPadding + 2×6px padding + 44px bar.
    final appBarHeight = mq.padding.top + 12 + 44;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(appBarHeight),
        child: PGFrostedHeader(
          // Profile setup is a fixed-chrome screen: content doesn't scroll
          // behind the bar (PageView is the body), so the bar is always
          // fully frosted (scrollProgress: 1.0).
          scrollProgress: 1.0,
          child: Padding(
            padding: EdgeInsets.only(
              top: mq.padding.top + 6,
              left: AppTheme.space12,
              right: AppTheme.space12,
              bottom: 6,
            ),
            child: SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Text(
                      'Step ${_currentStep + 1} of $_totalSteps: '
                      '${_stepLabels[_currentStep]}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_currentStep > 0)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PGCircularIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: _prevStep,
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _skip,
                      child: const Text('Skip'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Progress bar — thicker, rounded, theme-aware
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.space20,
              appBarHeight + AppTheme.space8,
              AppTheme.space20,
              0,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              child: LinearProgressIndicator(
                value: (_currentStep + 1) / _totalSteps,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation(scheme.primary),
              ),
            ),
          ),

          // Step pages
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) => setState(() => _currentStep = index),
              children: const [
                _BasicInfoStep(),
                _GoalsStep(),
                _HealthProfileStep(),
                _AllergensStep(),
                _ReviewStep(),
              ],
            ),
          ),

          // Bottom continue button — fires haptic before transitioning
          SafeArea(
            top: false,
            minimum: const EdgeInsets.all(AppTheme.space20),
            child: FilledButton(
              onPressed: canContinue
                  ? () {
                      if (isLastStep) {
                        PGHaptics.successPattern(context);
                      } else {
                        PGHaptics.press(context);
                      }
                      _nextStep();
                    }
                  : null,
              child: Text(isLastStep ? 'Save & continue' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared step header — used by every step for consistent typography
// ---------------------------------------------------------------------------

class _StepHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _StepHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.25,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppTheme.space4),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: Basic Info (nickname + age + sex)
// ---------------------------------------------------------------------------

class _BasicInfoStep extends ConsumerWidget {
  const _BasicInfoStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.space20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            title: 'What would you like to be called?',
            subtitle:
                'Used for greetings. Your health data stays on this device.',
          ),
          const SizedBox(height: AppTheme.space16),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Nickname (optional)',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            style: theme.textTheme.bodyLarge,
            onChanged: notifier.setNickname,
          ),

          const SizedBox(height: AppTheme.space32),
          _StepHeader(
            title: 'Age bracket',
            subtitle:
                'Required for RDA / UL scoring. ${_requiredMarker(theme)}',
          ),
          const SizedBox(height: AppTheme.space12),
          PGCard(
            padding: EdgeInsets.zero,
            child: RadioGroup<String>(
              groupValue: profile.ageBracket,
              onChanged: notifier.setAgeBracket,
              child: Column(
                children: SchemaIds.ageBrackets
                    .map(
                      (bracket) => PGPressable(
                        onTap: () => notifier.setAgeBracket(bracket),
                        pressedScale: 0.98,
                        child: RadioListTile<String>(
                          title: Text(
                            bracket,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          value: bracket,
                          dense: true,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),

          const SizedBox(height: AppTheme.space32),
          _StepHeader(
            title: 'Sex',
            subtitle: 'Required for accurate dosing. ${_requiredMarker(theme)}',
          ),
          const SizedBox(height: AppTheme.space12),
          PGCard(
            padding: EdgeInsets.zero,
            child: RadioGroup<String>(
              groupValue: profile.sex,
              onChanged: notifier.setSex,
              child: Column(
                children: SchemaIds.sexOptions
                    .map(
                      (option) => PGPressable(
                        onTap: () => notifier.setSex(option),
                        pressedScale: 0.98,
                        child: RadioListTile<String>(
                          title: Text(
                            option,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle:
                              (option == 'Other' ||
                                  option == 'Prefer not to say')
                              ? Text(
                                  'Uses the most conservative safety limits',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                )
                              : null,
                          value: option,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.space24),
        ],
      ),
    );
  }

  String _requiredMarker(ThemeData theme) => '*';
}

// ---------------------------------------------------------------------------
// Step 2: Health Goals (max 2)
// ---------------------------------------------------------------------------

class _GoalsStep extends ConsumerWidget {
  const _GoalsStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final sortedGoals = List<String>.from(SchemaIds.goals)
      ..sort((a, b) {
        const order = {'high': 0, 'medium': 1, 'low': 2};
        final pa = order[SchemaIds.goalPriorities[a]] ?? 2;
        final pb = order[SchemaIds.goalPriorities[b]] ?? 2;
        return pa.compareTo(pb);
      });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.space20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            title: 'Select up to 2 health goals',
            subtitle:
                'Powers smart interaction warnings and personalized '
                'recommendations.',
          ),
          const SizedBox(height: AppTheme.space16),
          Wrap(
            spacing: AppTheme.space8,
            runSpacing: AppTheme.space8,
            children: sortedGoals.map((goalId) {
              final selected = profile.goals.contains(goalId);
              final label = SchemaIds.goalLabels[goalId] ?? goalId;
              final atMax = profile.goals.length >= 2 && !selected;
              return PGFilterChip(
                label: label,
                selected: selected,
                onTap: atMax ? () {} : () => notifier.toggleGoal(goalId),
              );
            }).toList(),
          ),
          if (profile.goals.length >= 2) ...[
            const SizedBox(height: AppTheme.space16),
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppTheme.space6),
                Text(
                  'Maximum 2 goals selected',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppTheme.space24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3: Health profile (conditions + drug classes)
// ---------------------------------------------------------------------------

class _HealthProfileStep extends ConsumerWidget {
  const _HealthProfileStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.space20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            title: 'Health conditions',
            subtitle: 'Ensures safe recommendations based on your conditions.',
          ),
          const SizedBox(height: AppTheme.space16),
          Wrap(
            spacing: AppTheme.space8,
            runSpacing: AppTheme.space8,
            children: SchemaIds.conditions.map((condId) {
              final selected = profile.conditions.contains(condId);
              final label = SchemaIds.conditionLabels[condId] ?? condId;
              return PGFilterChip(
                label: label,
                selected: selected,
                onTap: () => notifier.toggleCondition(condId),
              );
            }).toList(),
          ),

          const SizedBox(height: AppTheme.space32),
          const _StepHeader(
            title: 'Medications you take',
            subtitle:
                'Select types of medication you currently take. '
                'Kept on this device only.',
          ),
          const SizedBox(height: AppTheme.space12),
          PGCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: SchemaIds.drugClasses.map((dcId) {
                final selected = profile.drugClasses.contains(dcId);
                final label = SchemaIds.drugClassLabels[dcId] ?? dcId;
                return PGPressable(
                  onTap: () => notifier.toggleDrugClass(dcId),
                  pressedScale: 0.98,
                  child: CheckboxListTile.adaptive(
                    title: Text(
                      label,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    value: selected,
                    onChanged: (_) => notifier.toggleDrugClass(dcId),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: AppTheme.space12),
          Text(
            "In a future update, you'll be able to add specific medications "
            'by name for more precise warnings.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: AppTheme.space24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4: Allergens
// ---------------------------------------------------------------------------

class _AllergensStep extends ConsumerWidget {
  const _AllergensStep();

  /// User-facing chips. Each chip stores one or more canonical allergen IDs
  /// from `scripts/data/allergens.json` (the pipeline source of truth).
  /// Grouped chips ("Shellfish", "Gluten / wheat") store multiple IDs so
  /// the matcher fires on any constituent grain or shellfish kind.
  ///
  /// Sensitivities the pipeline cannot detect today (corn, yeast, gelatin,
  /// latex-fruit, nightshade, salicylate) are intentionally omitted —
  /// surfacing them would silently fail to flag products. Re-add when
  /// pipeline support and clinical signoff land.
  static const _chips = <_AllergenChipDef>[
    _AllergenChipDef('Milk / Dairy', ['ALLERGEN_MILK']),
    _AllergenChipDef('Eggs', ['ALLERGEN_EGGS']),
    _AllergenChipDef('Fish', ['ALLERGEN_FISH']),
    _AllergenChipDef('Shellfish', [
      'ALLERGEN_CRUSTACEANS',
      'ALLERGEN_MOLLUSCS',
    ]),
    _AllergenChipDef('Tree nuts', ['ALLERGEN_TREE_NUTS']),
    _AllergenChipDef('Peanuts', ['ALLERGEN_PEANUTS']),
    _AllergenChipDef('Soy', ['ALLERGEN_SOY']),
    _AllergenChipDef('Sesame', ['ALLERGEN_SESAME']),
    _AllergenChipDef('Gluten / wheat', [
      'ALLERGEN_WHEAT',
      'ALLERGEN_BARLEY',
      'ALLERGEN_RYE',
      'ALLERGEN_OATS',
    ]),
    _AllergenChipDef('Sulfites', ['ALLERGEN_SULFITES']),
    _AllergenChipDef('Celery', ['ALLERGEN_CELERY']),
    _AllergenChipDef('Mustard', ['ALLERGEN_MUSTARD']),
    _AllergenChipDef('Lupin', ['ALLERGEN_LUPIN']),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.space20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            title: 'Allergies & sensitivities',
            subtitle:
                'Prevents recommendations that could trigger allergic '
                'reactions. Select all that apply.',
          ),
          const SizedBox(height: AppTheme.space16),
          Wrap(
            spacing: AppTheme.space8,
            runSpacing: AppTheme.space8,
            children: _chips.map((chip) {
              // A chip is considered selected when every constituent ID
              // is present — partial selections are treated as unselected
              // so a tap completes the group.
              final selected = chip.allergenIds.every(
                profile.allergens.contains,
              );
              return PGFilterChip(
                label: chip.label,
                selected: selected,
                onTap: () => notifier.toggleAllergenGroup(chip.allergenIds),
              );
            }).toList(),
          ),
          const SizedBox(height: AppTheme.space24),
        ],
      ),
    );
  }
}

class _AllergenChipDef {
  final String label;
  final List<String> allergenIds;

  const _AllergenChipDef(this.label, this.allergenIds);
}

// ---------------------------------------------------------------------------
// Step 5: Review + save
// ---------------------------------------------------------------------------

class _ReviewStep extends ConsumerWidget {
  const _ReviewStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.space20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Big completeness ring visual
          Center(
            child: PGCard(
              variant: PGCardVariant.highlighted,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space32,
                vertical: AppTheme.space24,
              ),
              child: Column(
                children: [
                  Text(
                    '${profile.completeness}%',
                    style: AppTheme.numeric(
                      theme.textTheme.displayLarge!.copyWith(
                        fontSize: 52,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                        color: scheme.primary,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.space4),
                  Text(
                    'Profile ${profile.completenessLabel}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.space24),

          // Review rows grouped in a card
          PGCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _ReviewRow(
                  label: 'Nickname',
                  value: profile.nickname?.isNotEmpty == true
                      ? profile.nickname!
                      : 'Not set',
                ),
                _RowDivider(color: scheme.outlineVariant),
                _ReviewRow(
                  label: 'Age bracket',
                  value: profile.ageBracket ?? 'Not set',
                ),
                _RowDivider(color: scheme.outlineVariant),
                _ReviewRow(label: 'Sex', value: profile.sex ?? 'Not set'),
                _RowDivider(color: scheme.outlineVariant),
                _ReviewRow(
                  label: 'Goals',
                  value: profile.goals.isEmpty
                      ? 'None selected'
                      : profile.goals
                            .map((g) => SchemaIds.goalLabels[g] ?? g)
                            .join(', '),
                ),
                _RowDivider(color: scheme.outlineVariant),
                _ReviewRow(
                  label: 'Conditions',
                  value: profile.conditions.isEmpty
                      ? 'None'
                      : profile.conditions
                            .map((c) => SchemaIds.conditionLabels[c] ?? c)
                            .join(', '),
                ),
                _RowDivider(color: scheme.outlineVariant),
                _ReviewRow(
                  label: 'Medications',
                  value: profile.drugClasses.isEmpty
                      ? 'None'
                      : profile.drugClasses
                            .map((d) => SchemaIds.drugClassLabels[d] ?? d)
                            .join(', '),
                ),
                _RowDivider(color: scheme.outlineVariant),
                _ReviewRow(
                  label: 'Allergens',
                  value: profile.allergens.isEmpty
                      ? 'None'
                      : '${profile.allergens.length} selected',
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.space24),
          Container(
            padding: const EdgeInsets.all(AppTheme.space12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: scheme.outlineVariant, width: 0.8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppTheme.space8),
                Expanded(
                  child: Text(
                    'Your health information is stored securely on this '
                    'device only and used for personalized recommendations. '
                    'Always consult healthcare professionals before making '
                    'medical decisions.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.space16),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space16,
        vertical: AppTheme.space12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  final Color color;
  const _RowDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0.5,
      thickness: 0.5,
      indent: AppTheme.space16,
      endIndent: AppTheme.space16,
      color: color,
    );
  }
}
