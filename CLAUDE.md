# PharmaGuide Flutter App

## Project Overview

Consumer-facing supplement safety app. Offline-first, privacy-first. Two local SQLite databases (Drift ORM), connected to pipeline via Supabase.

## Commands

```bash
# Run app
flutter run

# Run all tests
flutter test

# Run specific test file
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
- Read files before editing them
- Run tests after every change
