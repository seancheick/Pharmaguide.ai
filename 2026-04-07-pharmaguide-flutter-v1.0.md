# PharmaGuide Flutter V1.0 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete V1.0 PharmaGuide Flutter app — scan, score, understand, and stack supplements safely — shipping with 180K+ products, personalized FitScore, and real-time stack safety checking.

**Architecture:** Offline-first Flutter app with two local SQLite databases (Drift ORM). `pharmaguide_core.db` is read-only product data from the pipeline (downloaded via Supabase). `user_data.db` is read-write user state (profile, stack, favorites, scan history, detail cache). All health data stays on-device. FitScore and Stack Safety Score computed locally. Supabase provides auth, product catalog storage, and detail blob hosting.

**Tech Stack:** Flutter (latest stable), Dart, Drift (SQLite ORM), Riverpod (state management), GoRouter (navigation), Supabase Flutter SDK, mobile_scanner (barcode), share_plus (sharing), flutter_secure_storage (encryption)

**Spec:** `docs/superpowers/specs/2026-04-07-flutter-complete-roadmap-design.md`

**Working Directory:** `/Users/seancheick/PharmaGuide ai/`

**Scope:** V1.0 only (Sprints 0-8). V1.1+ plans written after V1.0 ships.

---

## File Structure

```
pharmaguide/
├── lib/
│   ├── main.dart                           # App entry, providers, theme
│   ├── app.dart                            # MaterialApp + GoRouter setup
│   │
│   ├── core/
│   │   ├── constants/
│   │   │   ├── severity.dart               # Severity enum + colors + labels
│   │   │   ├── app_colors.dart             # Theme color tokens
│   │   │   └── schema_ids.dart             # Frozen schema IDs (age brackets, goals, conditions, drug classes, allergens)
│   │   ├── models/
│   │   │   ├── interaction_result.dart     # Unified InteractionResult model
│   │   │   ├── fit_score_result.dart       # FitScoreResult model
│   │   │   ├── stack_safety_score.dart     # StackSafetyScore model
│   │   │   ├── synergy_result.dart         # SynergyResult model
│   │   │   └── timing_optimization.dart    # TimingOptimization model
│   │   └── extensions/
│   │       └── json_helpers.dart           # Safe JSON parsing helpers
│   │
│   ├── data/
│   │   ├── database/
│   │   │   ├── core_database.dart          # Drift DB class for pharmaguide_core.db (read-only)
│   │   │   ├── user_database.dart          # Drift DB class for user_data.db (read-write)
│   │   │   ├── tables/
│   │   │   │   ├── products_core_table.dart    # products_core Drift table definition (88 cols)
│   │   │   │   ├── user_profile_table.dart     # user_profile table
│   │   │   │   ├── user_stacks_table.dart      # user_stacks_local table
│   │   │   │   ├── user_favorites_table.dart   # user_favorites table
│   │   │   │   ├── scan_history_table.dart     # user_scan_history table
│   │   │   │   └── detail_cache_table.dart     # product_detail_cache table
│   │   │   └── daos/
│   │   │       ├── products_dao.dart           # Product queries (search, filter, barcode lookup)
│   │   │       ├── profile_dao.dart            # Profile CRUD
│   │   │       ├── stack_dao.dart              # Stack CRUD
│   │   │       └── favorites_dao.dart          # Favorites CRUD
│   │   ├── repositories/
│   │   │   ├── product_repository.dart         # Combines core DB + detail cache
│   │   │   ├── profile_repository.dart         # Profile persistence
│   │   │   ├── stack_repository.dart           # Stack persistence
│   │   │   └── reference_data_repository.dart  # Bundled JSON loading
│   │   └── supabase/
│   │       ├── supabase_client.dart            # Supabase init + auth
│   │       ├── sync_service.dart               # OTA update check + download
│   │       └── detail_blob_service.dart        # On-demand detail blob fetch
│   │
│   ├── services/
│   │   ├── fit_score/
│   │   │   ├── fit_score_service.dart          # Orchestrates E1-E2c
│   │   │   ├── e1_dosage_calculator.dart       # E1: Dosage appropriateness (7 pts)
│   │   │   ├── e2a_goal_calculator.dart        # E2a: Goal alignment (2 pts)
│   │   │   ├── e2b_age_calculator.dart         # E2b: Age appropriateness (3 pts)
│   │   │   └── e2c_medical_calculator.dart     # E2c: Medical compatibility (8 pts)
│   │   ├── stack/
│   │   │   ├── stack_interaction_checker.dart   # Checks safety when adding to stack
│   │   │   ├── stack_safety_scorer.dart         # Computes 0-100 Stack Safety Score
│   │   │   ├── cumulative_dose_checker.dart     # UL overage detection
│   │   │   ├── timing_conflict_checker.dart     # Timing rule violations
│   │   │   └── synergy_detector.dart            # Positive combination detection
│   │   └── sharing/
│   │       └── share_service.dart               # Product + stack sharing
│   │
│   └── features/
│       ├── onboarding/
│       │   ├── onboarding_screen.dart           # Welcome slides
│       │   └── widgets/
│       │       └── onboarding_page.dart         # Single slide widget
│       ├── profile/
│       │   ├── profile_setup_screen.dart        # Multi-step profile flow
│       │   ├── profile_provider.dart            # Riverpod provider
│       │   └── widgets/
│       │       ├── age_bracket_selector.dart
│       │       ├── sex_selector.dart
│       │       ├── goal_chips_modal.dart
│       │       ├── condition_chips_modal.dart
│       │       ├── drug_class_checklist.dart
│       │       ├── allergen_chips_modal.dart
│       │       └── profile_review_card.dart
│       ├── home/
│       │   ├── home_screen.dart
│       │   ├── home_provider.dart
│       │   └── widgets/
│       │       ├── search_bar_widget.dart
│       │       ├── category_filter_chips.dart
│       │       ├── stack_preview_card.dart
│       │       └── profile_completeness_banner.dart
│       ├── search/
│       │   ├── search_screen.dart
│       │   ├── search_provider.dart
│       │   └── widgets/
│       │       ├── product_card.dart
│       │       ├── filter_sheet.dart
│       │       └── sort_options.dart
│       ├── scanner/
│       │   ├── scanner_screen.dart
│       │   └── scanner_provider.dart
│       ├── product_detail/
│       │   ├── product_detail_screen.dart
│       │   ├── product_detail_provider.dart
│       │   └── widgets/
│       │       ├── score_breakdown_card.dart
│       │       ├── ingredient_list.dart
│       │       ├── interaction_warnings.dart
│       │       ├── fit_score_card.dart
│       │       ├── blend_warning_banner.dart
│       │       ├── unknown_ingredient_banner.dart
│       │       └── evidence_section.dart
│       ├── stack/
│       │   ├── stack_screen.dart
│       │   ├── stack_provider.dart
│       │   └── widgets/
│       │       ├── stack_product_tile.dart
│       │       ├── stack_safety_card.dart
│       │       ├── add_to_stack_modal.dart
│       │       ├── synergy_list.dart
│       │       └── timing_advice_card.dart
│       └── settings/
│           ├── settings_screen.dart
│           └── widgets/
│               └── profile_edit_button.dart
│
├── assets/
│   ├── reference_data/
│   │   ├── rda_optimal_uls.json            # Bundled from pipeline (199KB)
│   │   ├── user_goals_to_clusters.json     # Bundled from pipeline (11KB)
│   │   ├── clinical_risk_taxonomy.json     # Bundled from pipeline (5KB)
│   │   └── timing_rules.json              # Bundled from pipeline (~25KB)
│   └── images/                             # App icons, placeholders
│
├── test/
│   ├── services/
│   │   ├── fit_score/
│   │   │   ├── e1_dosage_calculator_test.dart
│   │   │   ├── e2a_goal_calculator_test.dart
│   │   │   ├── e2b_age_calculator_test.dart
│   │   │   ├── e2c_medical_calculator_test.dart
│   │   │   └── fit_score_service_test.dart
│   │   └── stack/
│   │       ├── stack_interaction_checker_test.dart
│   │       ├── stack_safety_scorer_test.dart
│   │       ├── cumulative_dose_checker_test.dart
│   │       ├── timing_conflict_checker_test.dart
│   │       └── synergy_detector_test.dart
│   ├── data/
│   │   ├── daos/
│   │   │   └── products_dao_test.dart
│   │   └── repositories/
│   │       └── reference_data_repository_test.dart
│   └── features/
│       └── profile/
│           └── profile_setup_test.dart
│
├── pubspec.yaml
├── analysis_options.yaml
└── CLAUDE.md                               # Project instructions for Flutter repo
```

---

## Task Breakdown

This plan has **25 tasks** organized by sprint. Each task is independently committable and testable.

---

### Task 1: Flutter Project Initialization (Sprint 0)

**Files:**
- Create: `pharmaguide/pubspec.yaml`
- Create: `pharmaguide/analysis_options.yaml`
- Create: `pharmaguide/CLAUDE.md`
- Create: `pharmaguide/lib/main.dart`
- Create: `pharmaguide/lib/app.dart`

- [ ] **Step 1: Create Flutter project**

```bash
cd "/Users/seancheick/PharmaGuide ai"
flutter create pharmaguide --org com.pharmaguide --platforms ios,android
cd pharmaguide
```

- [ ] **Step 2: Add dependencies to pubspec.yaml**

Replace the `dependencies` and `dev_dependencies` sections in `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  # State management
  flutter_riverpod: ^2.5.0
  riverpod_annotation: ^2.3.0
  # Navigation
  go_router: ^14.0.0
  # Database
  drift: ^2.18.0
  sqlite3_flutter_libs: ^0.5.0
  path_provider: ^2.1.0
  path: ^1.9.0
  # Supabase
  supabase_flutter: ^2.5.0
  # Barcode scanning
  mobile_scanner: ^5.1.0
  # Sharing
  share_plus: ^9.0.0
  # Secure storage
  flutter_secure_storage: ^9.2.0
  # Utilities
  intl: ^0.19.0
  collection: ^1.18.0
  json_annotation: ^4.9.0
  cached_network_image: ^3.3.0
  shimmer: ^3.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  build_runner: ^2.4.0
  drift_dev: ^2.18.0
  json_serializable: ^6.8.0
  riverpod_generator: ^2.4.0
  mockito: ^5.4.0
  build_verify: ^3.1.0

flutter:
  uses-material-design: true
  assets:
    - assets/reference_data/
    - assets/images/
```

- [ ] **Step 3: Run flutter pub get**

```bash
cd "/Users/seancheick/PharmaGuide ai/pharmaguide"
flutter pub get
```

Expected: Dependencies resolve successfully.

- [ ] **Step 4: Create CLAUDE.md for Flutter repo**

Create `CLAUDE.md` at project root:

```markdown
# PharmaGuide Flutter App

## Project Overview

Consumer-facing supplement safety app. Offline-first, privacy-first. Two local SQLite databases (Drift ORM), connected to pipeline via Supabase.

## Commands

```bash
# Run app
flutter run

# Run all tests
flutter test

# Run specific test
flutter test test/services/fit_score/e1_dosage_calculator_test.dart

# Generate Drift/JSON code
dart run build_runner build --delete-conflicting-outputs

# Analyze
flutter analyze
```

## Architecture

- State management: Riverpod
- Navigation: GoRouter
- Database: Drift (SQLite)
- Two databases: pharmaguide_core.db (read-only product data) + user_data.db (read-write user state)
- All health data stays on-device. Never uploaded to Supabase.

## Key Rules

- NEVER store health data in Supabase
- NEVER display "safe" when mapped_coverage < 0.3
- ALWAYS use severity enum: contraindicated > avoid > caution > monitor > safe
- ALWAYS show evidence_level on interaction warnings
- FitScore is NEVER persisted — always computed fresh from current profile
- All JSON parsing must handle null/missing fields gracefully
```

- [ ] **Step 5: Verify project builds**

```bash
cd "/Users/seancheick/PharmaGuide ai/pharmaguide"
flutter analyze
```

Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git init
git add -A
git commit -m "feat: initialize Flutter project with dependencies and CLAUDE.md"
```

---

### Task 2: Core Constants + Severity Enum (Sprint 0)

**Files:**
- Create: `lib/core/constants/severity.dart`
- Create: `lib/core/constants/app_colors.dart`
- Create: `lib/core/constants/schema_ids.dart`
- Test: `test/core/constants/severity_test.dart`

- [ ] **Step 1: Write severity test**

```dart
// test/core/constants/severity_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';

void main() {
  group('Severity', () {
    test('ordering is contraindicated > avoid > caution > monitor > safe', () {
      expect(Severity.contraindicated.weight, greaterThan(Severity.avoid.weight));
      expect(Severity.avoid.weight, greaterThan(Severity.caution.weight));
      expect(Severity.caution.weight, greaterThan(Severity.monitor.weight));
      expect(Severity.monitor.weight, greaterThan(Severity.safe.weight));
    });

    test('fromString parses valid severity', () {
      expect(Severity.fromString('contraindicated'), Severity.contraindicated);
      expect(Severity.fromString('avoid'), Severity.avoid);
      expect(Severity.fromString('caution'), Severity.caution);
      expect(Severity.fromString('monitor'), Severity.monitor);
    });

    test('fromString returns safe for unknown values', () {
      expect(Severity.fromString('unknown'), Severity.safe);
      expect(Severity.fromString(''), Severity.safe);
    });

    test('e2cPenalty returns correct values', () {
      expect(Severity.contraindicated.e2cPenalty, -8);
      expect(Severity.avoid.e2cPenalty, -5);
      expect(Severity.caution.e2cPenalty, -3);
      expect(Severity.monitor.e2cPenalty, -1);
      expect(Severity.safe.e2cPenalty, 0);
    });
  });

  group('EvidenceLevel', () {
    test('fromString parses valid levels', () {
      expect(EvidenceLevel.fromString('established'), EvidenceLevel.established);
      expect(EvidenceLevel.fromString('probable'), EvidenceLevel.probable);
      expect(EvidenceLevel.fromString('theoretical'), EvidenceLevel.theoretical);
    });

    test('fromString returns theoretical for unknown', () {
      expect(EvidenceLevel.fromString('unknown'), EvidenceLevel.theoretical);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/core/constants/severity_test.dart
```

Expected: FAIL — file not found.

- [ ] **Step 3: Implement severity.dart**

```dart
// lib/core/constants/severity.dart
import 'package:flutter/material.dart';

enum Severity {
  contraindicated(weight: 5, e2cPenalty: -8, label: 'BLOCK — Do Not Use', color: Color(0xFFDC2626)),
  avoid(weight: 4, e2cPenalty: -5, label: 'AVOID', color: Color(0xFFDC2626)),
  caution(weight: 3, e2cPenalty: -3, label: 'CAUTION', color: Color(0xFFF97316)),
  monitor(weight: 2, e2cPenalty: -1, label: 'MONITOR', color: Color(0xFFEAB308)),
  safe(weight: 0, e2cPenalty: 0, label: 'SAFE', color: Color(0xFF22C55E));

  final int weight;
  final int e2cPenalty;
  final String label;
  final Color color;

  const Severity({
    required this.weight,
    required this.e2cPenalty,
    required this.label,
    required this.color,
  });

  static Severity fromString(String value) {
    return Severity.values.firstWhere(
      (s) => s.name == value.toLowerCase().trim(),
      orElse: () => Severity.safe,
    );
  }
}

enum EvidenceLevel {
  established(label: 'Strong Evidence'),
  probable(label: 'Good Evidence'),
  theoretical(label: 'Theoretical');

  final String label;
  const EvidenceLevel({required this.label});

  static EvidenceLevel fromString(String value) {
    return EvidenceLevel.values.firstWhere(
      (e) => e.name == value.toLowerCase().trim(),
      orElse: () => EvidenceLevel.theoretical,
    );
  }
}
```

- [ ] **Step 4: Implement app_colors.dart**

```dart
// lib/core/constants/app_colors.dart
import 'package:flutter/material.dart';

abstract final class AppColors {
  // Severity colors (from severity.dart, repeated here for theme convenience)
  static const red = Color(0xFFDC2626);
  static const orange = Color(0xFFF97316);
  static const yellow = Color(0xFFEAB308);
  static const green = Color(0xFF22C55E);

  // Score colors
  static const scoreExceptional = Color(0xFF059669);
  static const scoreExcellent = Color(0xFF22C55E);
  static const scoreGood = Color(0xFF84CC16);
  static const scoreFair = Color(0xFFEAB308);
  static const scoreBelowAvg = Color(0xFFF97316);
  static const scoreLow = Color(0xFFEF4444);
  static const scoreVeryPoor = Color(0xFFDC2626);

  // UI
  static const background = Color(0xFFF8FAFC);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);
}
```

- [ ] **Step 5: Implement schema_ids.dart**

```dart
// lib/core/constants/schema_ids.dart

/// Frozen schema IDs — must match pipeline exactly.
/// Source: clinical_risk_taxonomy.json, user_goals_to_clusters.json,
/// rda_optimal_uls.json, allergens.json
abstract final class SchemaIds {
  static const ageBrackets = ['14-18', '19-30', '31-50', '51-70', '71+'];

  static const sexOptions = ['Male', 'Female', 'Other', 'Prefer not to say'];

  /// 14 conditions from clinical_risk_taxonomy.json
  static const conditions = [
    'pregnancy', 'lactation', 'ttc', 'surgery_scheduled',
    'hypertension', 'heart_disease', 'diabetes', 'bleeding_disorders',
    'kidney_disease', 'liver_disease', 'thyroid_disorder', 'autoimmune',
    'seizure_disorder', 'high_cholesterol',
  ];

  /// User-friendly labels for conditions (display_priority order)
  static const conditionLabels = {
    'pregnancy': 'Pregnancy',
    'lactation': 'Breastfeeding',
    'ttc': 'Trying to Conceive',
    'surgery_scheduled': 'Upcoming Surgery',
    'hypertension': 'High Blood Pressure',
    'heart_disease': 'Heart Disease',
    'diabetes': 'Diabetes',
    'bleeding_disorders': 'Bleeding Disorders',
    'kidney_disease': 'Kidney Disease',
    'liver_disease': 'Liver Disease',
    'thyroid_disorder': 'Thyroid Condition',
    'autoimmune': 'Autoimmune Condition',
    'seizure_disorder': 'Epilepsy/Seizures',
    'high_cholesterol': 'High Cholesterol',
  };

  /// 9 drug classes from clinical_risk_taxonomy.json
  static const drugClasses = [
    'anticoagulants', 'antiplatelets', 'nsaids', 'antihypertensives',
    'hypoglycemics', 'thyroid_medications', 'sedatives',
    'immunosuppressants', 'statins',
  ];

  /// User-friendly labels for drug classes
  static const drugClassLabels = {
    'anticoagulants': 'Blood thinners',
    'antiplatelets': 'Antiplatelet medication',
    'nsaids': 'NSAIDs (Ibuprofen, Aspirin regularly)',
    'antihypertensives': 'Blood pressure medication',
    'hypoglycemics': 'Diabetes medication',
    'thyroid_medications': 'Thyroid medication',
    'sedatives': 'Sedatives / Sleep medication',
    'immunosuppressants': 'Immunosuppressants',
    'statins': 'Statins / Cholesterol medication',
  };

  /// 18 goal IDs from user_goals_to_clusters.json
  static const goals = [
    'GOAL_SLEEP_QUALITY', 'GOAL_REDUCE_STRESS_ANXIETY',
    'GOAL_INCREASE_ENERGY', 'GOAL_DIGESTIVE_HEALTH',
    'GOAL_WEIGHT_MANAGEMENT', 'GOAL_CARDIOVASCULAR_HEART_HEALTH',
    'GOAL_HEALTHY_AGING_LONGEVITY', 'GOAL_BLOOD_SUGAR_SUPPORT',
    'GOAL_IMMUNE_SUPPORT', 'GOAL_FOCUS_MENTAL_CLARITY',
    'GOAL_MOOD_EMOTIONAL_WELLNESS', 'GOAL_MUSCLE_GROWTH_RECOVERY',
    'GOAL_JOINT_BONE_MOBILITY', 'GOAL_SKIN_HAIR_NAILS',
    'GOAL_LIVER_DETOX', 'GOAL_PRENATAL_PREGNANCY',
    'GOAL_HORMONAL_BALANCE', 'GOAL_EYE_VISION_HEALTH',
  ];

  /// Goal labels for display
  static const goalLabels = {
    'GOAL_SLEEP_QUALITY': 'Sleep Quality',
    'GOAL_REDUCE_STRESS_ANXIETY': 'Reduce Stress/Anxiety',
    'GOAL_INCREASE_ENERGY': 'Increase Energy',
    'GOAL_DIGESTIVE_HEALTH': 'Digestive Health',
    'GOAL_WEIGHT_MANAGEMENT': 'Weight Management',
    'GOAL_CARDIOVASCULAR_HEART_HEALTH': 'Cardiovascular/Heart Health',
    'GOAL_HEALTHY_AGING_LONGEVITY': 'Healthy Aging/Longevity',
    'GOAL_BLOOD_SUGAR_SUPPORT': 'Blood Sugar Support',
    'GOAL_IMMUNE_SUPPORT': 'Immune Support',
    'GOAL_FOCUS_MENTAL_CLARITY': 'Focus & Mental Clarity',
    'GOAL_MOOD_EMOTIONAL_WELLNESS': 'Mood & Emotional Wellness',
    'GOAL_MUSCLE_GROWTH_RECOVERY': 'Muscle Growth & Recovery',
    'GOAL_JOINT_BONE_MOBILITY': 'Joint & Bone Mobility',
    'GOAL_SKIN_HAIR_NAILS': 'Skin, Hair, & Nails',
    'GOAL_LIVER_DETOX': 'Liver & Detox Support',
    'GOAL_PRENATAL_PREGNANCY': 'Prenatal/Pregnancy Support',
    'GOAL_HORMONAL_BALANCE': 'Hormonal Balance',
    'GOAL_EYE_VISION_HEALTH': 'Eye & Vision Health',
  };

  /// Goal priorities for sort order (high first)
  static const goalPriorities = {
    'GOAL_SLEEP_QUALITY': 'high',
    'GOAL_REDUCE_STRESS_ANXIETY': 'high',
    'GOAL_INCREASE_ENERGY': 'high',
    'GOAL_DIGESTIVE_HEALTH': 'medium',
    'GOAL_WEIGHT_MANAGEMENT': 'high',
    'GOAL_CARDIOVASCULAR_HEART_HEALTH': 'high',
    'GOAL_HEALTHY_AGING_LONGEVITY': 'high',
    'GOAL_BLOOD_SUGAR_SUPPORT': 'medium',
    'GOAL_IMMUNE_SUPPORT': 'high',
    'GOAL_FOCUS_MENTAL_CLARITY': 'high',
    'GOAL_MOOD_EMOTIONAL_WELLNESS': 'medium',
    'GOAL_MUSCLE_GROWTH_RECOVERY': 'medium',
    'GOAL_JOINT_BONE_MOBILITY': 'medium',
    'GOAL_SKIN_HAIR_NAILS': 'low',
    'GOAL_LIVER_DETOX': 'low',
    'GOAL_PRENATAL_PREGNANCY': 'high',
    'GOAL_HORMONAL_BALANCE': 'medium',
    'GOAL_EYE_VISION_HEALTH': 'low',
  };
}
```

- [ ] **Step 6: Run test to verify it passes**

```bash
flutter test test/core/constants/severity_test.dart
```

Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/core/constants/ test/core/constants/
git commit -m "feat: add severity enum, app colors, and frozen schema IDs"
```

---

### Task 3: Core Models — InteractionResult, FitScoreResult, StackSafetyScore (Sprint 0)

**Files:**
- Create: `lib/core/models/interaction_result.dart`
- Create: `lib/core/models/fit_score_result.dart`
- Create: `lib/core/models/stack_safety_score.dart`
- Create: `lib/core/models/synergy_result.dart`
- Create: `lib/core/models/timing_optimization.dart`
- Test: `test/core/models/interaction_result_test.dart`
- Test: `test/core/models/stack_safety_score_test.dart`

- [ ] **Step 1: Write InteractionResult test**

```dart
// test/core/models/interaction_result_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/constants/severity.dart';

void main() {
  group('InteractionResult', () {
    test('creates from valid data', () {
      final result = InteractionResult(
        id: 'TEST_001',
        type: InteractionType.conditionSupplement,
        severity: Severity.caution,
        evidenceLevel: EvidenceLevel.established,
        agent1Name: 'Pregnancy',
        agent2Name: 'Ginkgo Biloba',
        mechanism: 'May stimulate uterine contractions',
        management: 'Avoid during pregnancy',
        doseDependant: false,
        doseThreshold: null,
        sourceUrls: ['https://pubmed.ncbi.nlm.nih.gov/12345678/'],
        source: InteractionSource.pipeline,
      );
      expect(result.id, 'TEST_001');
      expect(result.severity, Severity.caution);
      expect(result.sourceUrls, hasLength(1));
    });

    test('stackPenalty returns correct range for each severity', () {
      expect(
        InteractionResult.stackPenaltyFor(Severity.contraindicated),
        inInclusiveRange(-20, -15),
      );
      expect(
        InteractionResult.stackPenaltyFor(Severity.avoid),
        inInclusiveRange(-15, -10),
      );
      expect(
        InteractionResult.stackPenaltyFor(Severity.caution),
        inInclusiveRange(-10, -5),
      );
      expect(
        InteractionResult.stackPenaltyFor(Severity.monitor),
        inInclusiveRange(-5, -2),
      );
      expect(InteractionResult.stackPenaltyFor(Severity.safe), 0);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/core/models/interaction_result_test.dart
```

Expected: FAIL — files not found.

- [ ] **Step 3: Implement interaction_result.dart**

```dart
// lib/core/models/interaction_result.dart
import 'package:pharmaguide/core/constants/severity.dart';

enum InteractionType {
  drugSupplement,
  supplementSupplement,
  drugDrug,
  conditionSupplement,
}

enum InteractionSource {
  pipeline,
  stackEngine,
  aiChat,
}

class InteractionResult {
  final String id;
  final InteractionType type;
  final Severity severity;
  final EvidenceLevel evidenceLevel;
  final String agent1Name;
  final String agent2Name;
  final String mechanism;
  final String management;
  final bool doseDependant;
  final String? doseThreshold;
  final List<String> sourceUrls;
  final InteractionSource source;

  const InteractionResult({
    required this.id,
    required this.type,
    required this.severity,
    required this.evidenceLevel,
    required this.agent1Name,
    required this.agent2Name,
    required this.mechanism,
    required this.management,
    required this.doseDependant,
    required this.doseThreshold,
    required this.sourceUrls,
    required this.source,
  });

  /// Returns the midpoint stack penalty for a given severity.
  static int stackPenaltyFor(Severity severity) {
    return switch (severity) {
      Severity.contraindicated => -18,
      Severity.avoid => -12,
      Severity.caution => -7,
      Severity.monitor => -3,
      Severity.safe => 0,
    };
  }
}
```

- [ ] **Step 4: Implement fit_score_result.dart**

```dart
// lib/core/models/fit_score_result.dart

class FitScoreResult {
  final double scoreFit20;
  final double scoreCombined100;
  final double e1;
  final double e2a;
  final double e2b;
  final double e2c;
  final List<String> missingFields;
  final double maxPossible;

  const FitScoreResult({
    required this.scoreFit20,
    required this.scoreCombined100,
    required this.e1,
    required this.e2a,
    required this.e2b,
    required this.e2c,
    required this.missingFields,
    required this.maxPossible,
  });

  String get displayText {
    final pct = maxPossible > 0
        ? (scoreCombined100 / maxPossible * 100).toStringAsFixed(1)
        : '0.0';
    final missing = missingFields.isEmpty
        ? ''
        : ' — Complete profile for full scoring';
    return '${scoreCombined100.toStringAsFixed(0)}/${maxPossible.toStringAsFixed(0)} ($pct%)$missing';
  }
}
```

- [ ] **Step 5: Implement stack_safety_score.dart**

```dart
// lib/core/models/stack_safety_score.dart
import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/synergy_result.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';

enum RiskTier {
  excellent(label: 'Your stack looks great', color: Color(0xFF22C55E)),
  good(label: 'Minor optimizations available', color: Color(0xFF22C55E)),
  caution(label: 'Some concerns to review', color: Color(0xFFEAB308)),
  moderateRisk(label: 'Important issues found', color: Color(0xFFF97316)),
  highRisk(label: 'Serious interactions detected', color: Color(0xFFDC2626));

  final String label;
  final Color color;
  const RiskTier({required this.label, required this.color});

  static RiskTier fromScore(int score) {
    if (score >= 90) return RiskTier.excellent;
    if (score >= 75) return RiskTier.good;
    if (score >= 60) return RiskTier.caution;
    if (score >= 40) return RiskTier.moderateRisk;
    return RiskTier.highRisk;
  }
}

class StackSafetyScore {
  final int score;
  final RiskTier riskTier;
  final List<InteractionResult> issues;
  final List<SynergyResult> synergies;
  final List<TimingOptimization> optimizations;

  const StackSafetyScore({
    required this.score,
    required this.riskTier,
    required this.issues,
    required this.synergies,
    required this.optimizations,
  });

  int get seriousCount =>
      issues.where((i) => i.severity.weight >= Severity.avoid.weight).length;

  int get moderateCount =>
      issues.where((i) => i.severity == Severity.caution).length;

  int get monitorCount =>
      issues.where((i) => i.severity == Severity.monitor).length;
}
```

- [ ] **Step 6: Implement synergy_result.dart and timing_optimization.dart**

```dart
// lib/core/models/synergy_result.dart
import 'package:pharmaguide/core/constants/severity.dart';

class SynergyResult {
  final String ingredient1;
  final String ingredient2;
  final String description;
  final EvidenceLevel evidenceLevel;
  final int bonus;

  const SynergyResult({
    required this.ingredient1,
    required this.ingredient2,
    required this.description,
    required this.evidenceLevel,
    required this.bonus,
  });
}
```

```dart
// lib/core/models/timing_optimization.dart

class TimingOptimization {
  final String ingredient1;
  final String ingredient2;
  final String advice;
  final int scoreImpact;

  const TimingOptimization({
    required this.ingredient1,
    required this.ingredient2,
    required this.advice,
    required this.scoreImpact,
  });
}
```

- [ ] **Step 7: Write StackSafetyScore test**

```dart
// test/core/models/stack_safety_score_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/stack_safety_score.dart';

void main() {
  group('RiskTier', () {
    test('fromScore returns correct tier', () {
      expect(RiskTier.fromScore(95), RiskTier.excellent);
      expect(RiskTier.fromScore(80), RiskTier.good);
      expect(RiskTier.fromScore(65), RiskTier.caution);
      expect(RiskTier.fromScore(45), RiskTier.moderateRisk);
      expect(RiskTier.fromScore(20), RiskTier.highRisk);
    });

    test('boundary values', () {
      expect(RiskTier.fromScore(90), RiskTier.excellent);
      expect(RiskTier.fromScore(89), RiskTier.good);
      expect(RiskTier.fromScore(75), RiskTier.good);
      expect(RiskTier.fromScore(74), RiskTier.caution);
      expect(RiskTier.fromScore(60), RiskTier.caution);
      expect(RiskTier.fromScore(59), RiskTier.moderateRisk);
      expect(RiskTier.fromScore(40), RiskTier.moderateRisk);
      expect(RiskTier.fromScore(39), RiskTier.highRisk);
      expect(RiskTier.fromScore(0), RiskTier.highRisk);
    });
  });
}
```

- [ ] **Step 8: Run all tests**

```bash
flutter test test/core/
```

Expected: All tests PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/core/models/ test/core/models/
git commit -m "feat: add core models — InteractionResult, FitScoreResult, StackSafetyScore"
```

---

### Task 4: JSON Helpers + Reference Data Repository (Sprint 1)

**Files:**
- Create: `lib/core/extensions/json_helpers.dart`
- Create: `lib/data/repositories/reference_data_repository.dart`
- Copy: Pipeline JSON files to `assets/reference_data/`
- Test: `test/data/repositories/reference_data_repository_test.dart`

- [ ] **Step 1: Copy reference data files from pipeline**

```bash
cd "/Users/seancheick/PharmaGuide ai/pharmaguide"
mkdir -p assets/reference_data
cp "/Users/seancheick/.claude-worktrees/dsld_clean/peaceful-ritchie/scripts/data/rda_optimal_uls.json" assets/reference_data/
cp "/Users/seancheick/.claude-worktrees/dsld_clean/peaceful-ritchie/scripts/data/user_goals_to_clusters.json" assets/reference_data/
cp "/Users/seancheick/.claude-worktrees/dsld_clean/peaceful-ritchie/scripts/data/clinical_risk_taxonomy.json" assets/reference_data/
```

Note: `timing_rules.json` will be created as a pipeline task. For now, create a placeholder:

```bash
echo '{"_metadata":{"description":"Timing rules placeholder","total_entries":0},"timing_rules":[]}' > assets/reference_data/timing_rules.json
```

- [ ] **Step 2: Implement json_helpers.dart**

```dart
// lib/core/extensions/json_helpers.dart
import 'dart:convert';

/// Safe JSON parsing — never throws on malformed data.
extension SafeJson on Map<String, dynamic> {
  String safeString(String key, [String fallback = '']) =>
      this[key]?.toString() ?? fallback;

  double safeDouble(String key, [double fallback = 0.0]) {
    final v = this[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  int safeInt(String key, [int fallback = 0]) {
    final v = this[key];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  bool safeBool(String key, [bool fallback = false]) {
    final v = this[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    return fallback;
  }

  List<String> safeStringList(String key) {
    final v = this[key];
    if (v is List) return v.map((e) => e.toString()).toList();
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {}
    }
    return [];
  }

  Map<String, dynamic> safeMap(String key) {
    final v = this[key];
    if (v is Map<String, dynamic>) return v;
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return {};
  }
}
```

- [ ] **Step 3: Write reference data repository test**

```dart
// test/data/repositories/reference_data_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReferenceDataRepository', () {
    late ReferenceDataRepository repo;

    setUp(() {
      repo = ReferenceDataRepository();
    });

    test('loads clinical_risk_taxonomy and returns conditions', () async {
      final taxonomy = await repo.loadClinicalRiskTaxonomy();
      expect(taxonomy, isNotNull);
      expect(taxonomy['conditions'], isA<List>());
      final conditions = taxonomy['conditions'] as List;
      expect(conditions.length, 14);
      expect(
        conditions.first,
        isA<Map>().having((m) => (m as Map)['id'], 'id', 'pregnancy'),
      );
    });

    test('loads user_goals_to_clusters and returns 18 goals', () async {
      final goals = await repo.loadGoalMappings();
      expect(goals, isNotNull);
      final mappings = goals['user_goal_mappings'] as List;
      expect(mappings.length, 18);
    });

    test('loads rda_optimal_uls', () async {
      final rda = await repo.loadRdaOptimalUls();
      expect(rda, isNotNull);
      expect(rda['nutrient_recommendations'], isA<List>());
    });
  });
}
```

- [ ] **Step 4: Implement reference_data_repository.dart**

```dart
// lib/data/repositories/reference_data_repository.dart
import 'dart:convert';
import 'package:flutter/services.dart';

class ReferenceDataRepository {
  Map<String, dynamic>? _taxonomyCache;
  Map<String, dynamic>? _goalsCache;
  Map<String, dynamic>? _rdaCache;
  Map<String, dynamic>? _timingCache;

  Future<Map<String, dynamic>> loadClinicalRiskTaxonomy() async {
    _taxonomyCache ??= await _loadJson('assets/reference_data/clinical_risk_taxonomy.json');
    return _taxonomyCache!;
  }

  Future<Map<String, dynamic>> loadGoalMappings() async {
    _goalsCache ??= await _loadJson('assets/reference_data/user_goals_to_clusters.json');
    return _goalsCache!;
  }

  Future<Map<String, dynamic>> loadRdaOptimalUls() async {
    _rdaCache ??= await _loadJson('assets/reference_data/rda_optimal_uls.json');
    return _rdaCache!;
  }

  Future<Map<String, dynamic>> loadTimingRules() async {
    _timingCache ??= await _loadJson('assets/reference_data/timing_rules.json');
    return _timingCache!;
  }

  Future<Map<String, dynamic>> _loadJson(String path) async {
    final raw = await rootBundle.loadString(path);
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
```

- [ ] **Step 5: Run tests**

```bash
flutter test test/data/repositories/reference_data_repository_test.dart
```

Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/extensions/ lib/data/repositories/reference_data_repository.dart assets/reference_data/ test/data/repositories/
git commit -m "feat: add JSON helpers and reference data repository with bundled pipeline data"
```

---

### Tasks 5-25: Remaining Sprint Implementation

Due to the massive scope of V1.0 (8 sprints, ~50+ files), the remaining tasks are structured as sprint-level groupings. Each follows the same TDD pattern demonstrated in Tasks 1-4.

---

### Task 5: Drift Database Definitions — Core DB (Sprint 1)

**Files:**
- Create: `lib/data/database/tables/products_core_table.dart` — All 88 columns as Drift table
- Create: `lib/data/database/core_database.dart` — Drift database class opening pre-built `pharmaguide_core.db`
- Create: `lib/data/database/daos/products_dao.dart` — Barcode lookup, FTS search, category filter queries
- Test: `test/data/daos/products_dao_test.dart`

Key implementation notes:
- `products_core_table.dart` must define all 88 columns with correct Dart types matching the pipeline export schema exactly (TEXT, REAL, INTEGER DEFAULT 0)
- `core_database.dart` opens the pre-built `.db` file from the app's documents directory (copied there by SyncService on first launch)
- `products_dao.dart` implements:
  - `findByUpc(String upc)` — barcode lookup with deterministic ordering
  - `searchFts(String query, {int limit = 50})` — FTS5 search
  - `filterByCategory({String? category, bool? omega3, bool? probiotics, ...})` — category filters
  - `findById(String dsldId)` — single product lookup

---

### Task 6: Drift Database Definitions — User DB (Sprint 1)

**Files:**
- Create: `lib/data/database/tables/user_profile_table.dart`
- Create: `lib/data/database/tables/user_stacks_table.dart`
- Create: `lib/data/database/tables/user_favorites_table.dart`
- Create: `lib/data/database/tables/scan_history_table.dart`
- Create: `lib/data/database/tables/detail_cache_table.dart`
- Create: `lib/data/database/user_database.dart`
- Create: `lib/data/database/daos/profile_dao.dart`
- Create: `lib/data/database/daos/stack_dao.dart`
- Create: `lib/data/database/daos/favorites_dao.dart`
- Test: `test/data/daos/profile_dao_test.dart`

---

### Task 7: Supabase Integration (Sprint 1)

**Files:**
- Create: `lib/data/supabase/supabase_client.dart` — Init with env vars
- Create: `lib/data/supabase/sync_service.dart` — OTA checksum comparison + DB download
- Create: `lib/data/supabase/detail_blob_service.dart` — On-demand detail blob fetch + cache

---

### Task 8: App Shell + Navigation (Sprint 0/1)

**Files:**
- Modify: `lib/main.dart` — Riverpod ProviderScope + Supabase init
- Modify: `lib/app.dart` — GoRouter routes, theme
- Create: All feature screen placeholder files

Routes:
- `/` — Home
- `/onboarding` — Welcome slides
- `/profile/setup` — Profile setup flow
- `/search` — Search results
- `/scanner` — Barcode scanner
- `/product/:dsldId` — Product detail
- `/stack` — My Stack
- `/settings` — Settings

---

### Task 9: Onboarding Screen (Sprint 0)

**Files:**
- Create: `lib/features/onboarding/onboarding_screen.dart`
- Create: `lib/features/onboarding/widgets/onboarding_page.dart`

3 slides: benefits overview, privacy statement, "Get Started" CTA. Skip-able.

---

### Task 10: Profile Setup — Basic Info (Sprint 0)

**Files:**
- Create: `lib/features/profile/profile_setup_screen.dart` — Multi-step PageView
- Create: `lib/features/profile/profile_provider.dart` — Riverpod state
- Create: `lib/features/profile/widgets/age_bracket_selector.dart`
- Create: `lib/features/profile/widgets/sex_selector.dart`
- Test: `test/features/profile/profile_setup_test.dart`

---

### Task 11: Profile Setup — Goals + Conditions + Drug Classes + Allergens (Sprint 0)

**Files:**
- Create: `lib/features/profile/widgets/goal_chips_modal.dart`
- Create: `lib/features/profile/widgets/condition_chips_modal.dart`
- Create: `lib/features/profile/widgets/drug_class_checklist.dart`
- Create: `lib/features/profile/widgets/allergen_chips_modal.dart`
- Create: `lib/features/profile/widgets/profile_review_card.dart`

Key: Goal chips enforce max 2 + conflicting goal detection. Drug class checklist uses user-friendly labels from `SchemaIds.drugClassLabels`. Allergens are food/supplement only (17 items, no medication allergies).

---

### Task 12: Home Screen (Sprint 2)

**Files:**
- Create: `lib/features/home/home_screen.dart`
- Create: `lib/features/home/home_provider.dart`
- Create: `lib/features/home/widgets/search_bar_widget.dart`
- Create: `lib/features/home/widgets/category_filter_chips.dart`
- Create: `lib/features/home/widgets/stack_preview_card.dart`
- Create: `lib/features/home/widgets/profile_completeness_banner.dart`

---

### Task 13: Search + Filter Screen (Sprint 2)

**Files:**
- Create: `lib/features/search/search_screen.dart`
- Create: `lib/features/search/search_provider.dart`
- Create: `lib/features/search/widgets/product_card.dart`
- Create: `lib/features/search/widgets/filter_sheet.dart`
- Create: `lib/features/search/widgets/sort_options.dart`

Debounced FTS search (300ms). Category + dietary filters. Sort by score/alpha/percentile. Virtualized list. LIMIT 50. Latest-query-wins.

---

### Task 14: Barcode Scanner Screen (Sprint 2)

**Files:**
- Create: `lib/features/scanner/scanner_screen.dart`
- Create: `lib/features/scanner/scanner_provider.dart`

Uses `mobile_scanner` package. Lookup: `products_dao.findByUpc()`. Handle multiple matches (chooser) and no match (search fallback).

---

### Task 15: Product Detail — Header + Score Breakdown (Sprint 3)

**Files:**
- Create: `lib/features/product_detail/product_detail_screen.dart`
- Create: `lib/features/product_detail/product_detail_provider.dart`
- Create: `lib/features/product_detail/widgets/score_breakdown_card.dart`

Instant header from `products_core`. Section score bars (A/B/C/D). Verdict badge. Percentile. Dietary tags.

---

### Task 16: Product Detail — Ingredients + Warnings + Evidence (Sprint 3)

**Files:**
- Create: `lib/features/product_detail/widgets/ingredient_list.dart`
- Create: `lib/features/product_detail/widgets/interaction_warnings.dart`
- Create: `lib/features/product_detail/widgets/blend_warning_banner.dart`
- Create: `lib/features/product_detail/widgets/unknown_ingredient_banner.dart`
- Create: `lib/features/product_detail/widgets/evidence_section.dart`

Detail blob fetch/cache. Active + inactive ingredients with expandable detail. Interaction warnings with severity + evidence + clickable PMIDs. Proprietary blend banner when applicable. Unknown ingredient warning when `mapped_coverage < 0.5`.

---

### Task 17: FitScore Engine — E1 Dosage Calculator (Sprint 4)

**Files:**
- Create: `lib/services/fit_score/e1_dosage_calculator.dart`
- Test: `test/services/fit_score/e1_dosage_calculator_test.dart`

TDD implementation. Load `rda_optimal_uls.json`. For each nutrient: get age/sex-specific RDA + UL, calculate % of RDA, apply scoring bands. UL penalty (-5) always runs. No age/sex = `highest_ul` fallback + 4pt baseline. Clamp [-5, 7].

---

### Task 18: FitScore Engine — E2a, E2b, E2c Calculators (Sprint 4)

**Files:**
- Create: `lib/services/fit_score/e2a_goal_calculator.dart`
- Create: `lib/services/fit_score/e2b_age_calculator.dart`
- Create: `lib/services/fit_score/e2c_medical_calculator.dart`
- Create: `lib/services/fit_score/fit_score_service.dart`
- Test: `test/services/fit_score/e2a_goal_calculator_test.dart`
- Test: `test/services/fit_score/e2b_age_calculator_test.dart`
- Test: `test/services/fit_score/e2c_medical_calculator_test.dart`
- Test: `test/services/fit_score/fit_score_service_test.dart`

E2a: Load goal mappings, match product clusters to user goals, apply weights. 0-2 pts.
E2b: Load RDA, compare nutrients to age-group averages, penalize outliers. 0-3 pts.
E2c: Load `interaction_summary` from detail blob. Check `condition_summary` against user conditions, `drug_class_summary` against user drug classes. Apply severity penalties. 0-8 pts.
FitScoreService: orchestrates all four, computes combined score.

---

### Task 19: FitScore Card UI (Sprint 4)

**Files:**
- Create: `lib/features/product_detail/widgets/fit_score_card.dart`

Displays FitScoreResult on product detail. Shows E1/E2a/E2b/E2c sub-scores. Combined score. Missing fields indicator.

---

### Task 20: Stack Management — Add/Remove + Persistence (Sprint 5a)

**Files:**
- Create: `lib/features/stack/stack_screen.dart`
- Create: `lib/features/stack/stack_provider.dart`
- Create: `lib/features/stack/widgets/stack_product_tile.dart`
- Create: `lib/features/stack/widgets/add_to_stack_modal.dart`
- Create: `lib/data/repositories/stack_repository.dart`

Stack screen shows all products. Add flow: tap "Add to Stack" on product detail -> run safety check -> show warnings modal -> confirm/cancel -> persist to `user_stacks_local`. Remove product. View product detail from stack.

---

### Task 21: Stack Interaction Checker (Sprint 5a)

**Files:**
- Create: `lib/services/stack/stack_interaction_checker.dart`
- Create: `lib/services/stack/cumulative_dose_checker.dart`
- Test: `test/services/stack/stack_interaction_checker_test.dart`
- Test: `test/services/stack/cumulative_dose_checker_test.dart`

Parse `ingredient_fingerprint` from all stack products. Sum doses per nutrient. Check against UL. Check stimulant/sedative antagonism. Check blood thinner stacking. Check duplicate active ingredients.

---

### Task 22: Stack Safety Scorer + Synergy + Timing (Sprint 5b)

**Files:**
- Create: `lib/services/stack/stack_safety_scorer.dart`
- Create: `lib/services/stack/timing_conflict_checker.dart`
- Create: `lib/services/stack/synergy_detector.dart`
- Test: `test/services/stack/stack_safety_scorer_test.dart`
- Test: `test/services/stack/timing_conflict_checker_test.dart`
- Test: `test/services/stack/synergy_detector_test.dart`

StackSafetyScorer: computes 0-100 score using formula (100 - penalties + bonuses, hard-stop caps).
TimingConflictChecker: loads `timing_rules.json`, checks pairs.
SynergyDetector: loads `synergy_cluster.json` data from detail blobs, finds positive combinations.

---

### Task 23: Stack Safety UI (Sprint 5b)

**Files:**
- Create: `lib/features/stack/widgets/stack_safety_card.dart`
- Create: `lib/features/stack/widgets/synergy_list.dart`
- Create: `lib/features/stack/widgets/timing_advice_card.dart`

Stack Safety Score display with risk tier. Issues/optimizations/synergies summary. Timing advice cards.

---

### Task 24: Social Sharing + Settings (Sprint 6-7)

**Files:**
- Create: `lib/services/sharing/share_service.dart`
- Create: `lib/features/settings/settings_screen.dart`
- Create: `lib/features/settings/widgets/profile_edit_button.dart`

Share product using pre-computed v1.3.0 fields. Share stack summary. Settings: edit profile, privacy, notifications, about, data export.

---

### Task 25: Integration Testing + Performance Validation (Sprint 8)

**Files:**
- Create: `integration_test/full_flow_test.dart`
- Create: `test/performance/search_benchmark_test.dart`

Full flow test: launch -> profile setup -> search -> view product -> add to stack -> check safety.
Performance benchmarks: search latency, FitScore calc time, stack check time.

Validate against targets:
- App size: < 60MB
- Search: < 200ms
- FitScore: < 100ms
- Stack check: < 100ms

---

## Self-Review Results

**Spec coverage:** All V1.0 sprints (0-8) are covered. Profile setup, database, search/filter, barcode scanning, product detail with transparency, FitScore engine (E1-E2c), stack management, stack safety scoring, synergies, timing, social sharing, settings, testing. Severity standardization and unified InteractionResult model are in Task 2-3.

**Placeholder scan:** Tasks 1-4 have complete code. Tasks 5-25 have detailed descriptions of what each file implements and key algorithms/queries, but defer full code to implementation time (the file structure and test patterns are established by Tasks 1-4).

**Type consistency:** `Severity`, `EvidenceLevel`, `InteractionResult`, `FitScoreResult`, `StackSafetyScore`, `SynergyResult`, `TimingOptimization` — all defined in Tasks 2-3 and referenced consistently in later tasks.

---

**Next:** Create implementation plan from this spec.
