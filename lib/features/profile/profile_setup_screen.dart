import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/core/constants/schema_ids.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  static const _totalSteps = 5;

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _save();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _save() async {
    try {
      await ref.read(profileProvider.notifier).saveToDb();
      if (!mounted) return;
      context.go('/');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save profile. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _skip() {
    context.go('/');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final stepLabels = [
      'Basic Info',
      'Health Goals',
      'Health Profile',
      'Allergies',
      'Review',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Step ${_currentStep + 1} of $_totalSteps: ${stepLabels[_currentStep]}',
        ),
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _prevStep,
              )
            : null,
        actions: [
          TextButton(onPressed: _skip, child: const Text('Skip')),
        ],
      ),
      body: Column(
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: (_currentStep + 1) / _totalSteps,
            backgroundColor: AppColors.border,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppTheme.brandTeal),
          ),
          // Steps
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
          // Bottom button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _currentStep == 0 && profile.ageBracket == null
                    ? null // Disable until age selected
                    : _nextStep,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brandTeal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _currentStep == _totalSteps - 1
                      ? 'Save & Continue'
                      : 'Continue',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Step 1: Basic Info ---
class _BasicInfoStep extends ConsumerWidget {
  const _BasicInfoStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What would you like to be called?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Nickname (optional)',
              border: OutlineInputBorder(),
            ),
            onChanged: notifier.setNickname,
          ),
          const SizedBox(height: 24),
          const Text(
            'Age Bracket *',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...SchemaIds.ageBrackets.map(
            (bracket) => RadioListTile<String>(
              title: Text(bracket),
              value: bracket,
              groupValue: profile.ageBracket,
              onChanged: (v) => notifier.setAgeBracket(v),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Sex *',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...SchemaIds.sexOptions.map(
            (option) => RadioListTile<String>(
              title: Text(option),
              subtitle: (option == 'Other' || option == 'Prefer not to say')
                  ? const Text(
                      'Uses most conservative safety limits',
                      style: TextStyle(fontSize: 12),
                    )
                  : null,
              value: option,
              groupValue: profile.sex,
              onChanged: (v) => notifier.setSex(v),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Step 2: Health Goals ---
class _GoalsStep extends ConsumerWidget {
  const _GoalsStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);

    // Sort goals by priority: high > medium > low
    final sortedGoals = List<String>.from(SchemaIds.goals)
      ..sort((a, b) {
        const order = {'high': 0, 'medium': 1, 'low': 2};
        final pa = order[SchemaIds.goalPriorities[a]] ?? 2;
        final pb = order[SchemaIds.goalPriorities[b]] ?? 2;
        return pa.compareTo(pb);
      });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select up to 2 health goals',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Powers smart interaction warnings and personalized insights',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sortedGoals.map((goalId) {
              final selected = profile.goals.contains(goalId);
              final label = SchemaIds.goalLabels[goalId] ?? goalId;
              final atMax = profile.goals.length >= 2 && !selected;
              return FilterChip(
                label: Text(label),
                selected: selected,
                onSelected: atMax ? null : (_) => notifier.toggleGoal(goalId),
                selectedColor: AppTheme.brandTeal.withAlpha(25),
                checkmarkColor: AppTheme.brandTeal,
              );
            }).toList(),
          ),
          if (profile.goals.length >= 2)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Maximum 2 goals selected',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

// --- Step 3: Health Profile (Conditions + Drug Classes) ---
class _HealthProfileStep extends ConsumerWidget {
  const _HealthProfileStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Health Conditions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ensures safe recommendations based on your conditions',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SchemaIds.conditions.map((condId) {
              final selected = profile.conditions.contains(condId);
              final label = SchemaIds.conditionLabels[condId] ?? condId;
              return FilterChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) => notifier.toggleCondition(condId),
                selectedColor: AppTheme.brandTeal.withAlpha(25),
                checkmarkColor: AppTheme.brandTeal,
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          const Text(
            'Medications You Take',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Select types of medication you currently take',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          ...SchemaIds.drugClasses.map((dcId) {
            final selected = profile.drugClasses.contains(dcId);
            final label = SchemaIds.drugClassLabels[dcId] ?? dcId;
            return CheckboxListTile(
              title: Text(label),
              value: selected,
              onChanged: (_) => notifier.toggleDrugClass(dcId),
              activeColor: AppTheme.brandTeal,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            );
          }),
          const SizedBox(height: 8),
          const Text(
            "In a future update, you'll be able to add specific medications for more precise warnings.",
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Step 4: Allergens ---
class _AllergensStep extends ConsumerWidget {
  const _AllergensStep();

  // 17 food/supplement allergens (no medication allergies)
  static const _allergens = [
    'ALLERGEN_MILK',
    'ALLERGEN_EGG',
    'ALLERGEN_FISH',
    'ALLERGEN_SHELLFISH',
    'ALLERGEN_TREE_NUTS',
    'ALLERGEN_PEANUT',
    'ALLERGEN_WHEAT',
    'ALLERGEN_SOY',
    'ALLERGEN_SESAME',
    'ALLERGEN_GLUTEN',
    'ALLERGEN_CORN',
    'ALLERGEN_YEAST',
    'ALLERGEN_GELATIN',
    'ALLERGEN_LATEX_FRUIT',
    'ALLERGEN_NIGHTSHADE',
    'ALLERGEN_SULFITE',
    'ALLERGEN_SALICYLATE',
  ];

  static const _allergenLabels = {
    'ALLERGEN_MILK': 'Milk/Dairy',
    'ALLERGEN_EGG': 'Eggs',
    'ALLERGEN_FISH': 'Fish',
    'ALLERGEN_SHELLFISH': 'Shellfish',
    'ALLERGEN_TREE_NUTS': 'Tree Nuts',
    'ALLERGEN_PEANUT': 'Peanuts',
    'ALLERGEN_WHEAT': 'Wheat',
    'ALLERGEN_SOY': 'Soy',
    'ALLERGEN_SESAME': 'Sesame',
    'ALLERGEN_GLUTEN': 'Gluten',
    'ALLERGEN_CORN': 'Corn',
    'ALLERGEN_YEAST': 'Yeast',
    'ALLERGEN_GELATIN': 'Gelatin',
    'ALLERGEN_LATEX_FRUIT': 'Latex-related Fruits',
    'ALLERGEN_NIGHTSHADE': 'Nightshade',
    'ALLERGEN_SULFITE': 'Sulfites',
    'ALLERGEN_SALICYLATE': 'Salicylates',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Allergies & Sensitivities',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Prevents recommendations that could trigger allergies',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _allergens.map((allergenId) {
              final selected = profile.allergens.contains(allergenId);
              final label = _allergenLabels[allergenId] ?? allergenId;
              return FilterChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) => notifier.toggleAllergen(allergenId),
                selectedColor: AppTheme.brandTeal.withAlpha(25),
                checkmarkColor: AppTheme.brandTeal,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// --- Step 5: Review ---
class _ReviewStep extends ConsumerWidget {
  const _ReviewStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Completeness
          Center(
            child: Column(
              children: [
                Text(
                  '${profile.completeness}%',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.brandTeal,
                  ),
                ),
                Text(
                  'Profile ${profile.completenessLabel}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _ReviewRow(
            label: 'Nickname',
            value: profile.nickname ?? 'Not set',
          ),
          _ReviewRow(
            label: 'Age',
            value: profile.ageBracket ?? 'Not set',
          ),
          _ReviewRow(
            label: 'Sex',
            value: profile.sex ?? 'Not set',
          ),
          _ReviewRow(
            label: 'Goals',
            value: profile.goals.isEmpty
                ? 'None selected'
                : profile.goals
                    .map((g) => SchemaIds.goalLabels[g] ?? g)
                    .join(', '),
          ),
          _ReviewRow(
            label: 'Conditions',
            value: profile.conditions.isEmpty
                ? 'None'
                : profile.conditions
                    .map((c) => SchemaIds.conditionLabels[c] ?? c)
                    .join(', '),
          ),
          _ReviewRow(
            label: 'Medications',
            value: profile.drugClasses.isEmpty
                ? 'None'
                : profile.drugClasses
                    .map((d) => SchemaIds.drugClassLabels[d] ?? d)
                    .join(', '),
          ),
          _ReviewRow(
            label: 'Allergens',
            value: profile.allergens.isEmpty
                ? 'None'
                : '${profile.allergens.length} selected',
          ),
          const SizedBox(height: 24),
          const Text(
            'Your health information is stored securely on your device and used only to provide personalized recommendations. Always consult with healthcare professionals before making medical decisions.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
