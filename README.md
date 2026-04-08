<div align="center">

# 🛡️ PharmaGuide

### Know What You Take.

*The supplement safety app that scores, checks, and protects — powered by clinical data, not marketing claims.*

[![Flutter](https://img.shields.io/badge/Flutter_3.8-02569B?logo=flutter&logoColor=white&style=flat-square)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart_3.8-0175C2?logo=dart&logoColor=white&style=flat-square)](https://dart.dev)
[![Tests](https://img.shields.io/badge/tests-97_passing-22C55E?style=flat-square)](test/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)

</div>

---

## The Problem

The supplement industry is a **$60B market** with almost no transparency. Consumers face:

- **No safety scoring** — products are marketed by hype, not evidence
- **Hidden interactions** — supplements can dangerously interact with medications
- **Proprietary blends** — dosages hidden behind marketing labels
- **No personalization** — a product safe for one person can be harmful for another

**PharmaGuide changes this.** Every product gets a transparent, evidence-based safety score tailored to *your* health profile.

---

## How It Works

```
📱 Scan barcode → ⚡ Instant safety score → 🔍 Full transparency → 📋 Build safe stack
```

| Step | What Happens |
|------|-------------|
| **1. Scan or Search** | Point your camera at any supplement barcode, or search by name |
| **2. Instant Verdict** | Get a 0-100 FitScore with color-coded verdict in < 500ms |
| **3. Understand Why** | See the 4-pillar breakdown: Ingredients, Safety, Evidence, Brand Trust |
| **4. Check Interactions** | Severity-ranked warnings based on your conditions and medications |
| **5. Build Your Stack** | Add products to your stack with real-time safety analysis |

---

## Features

### 🎯 Personalized Safety Scoring

- **FitScore Engine** — 0-100 score computed fresh from your health profile (never cached)
- **4-Pillar Breakdown** — Ingredient Quality, Safety & Purity, Evidence & Research, Brand Trust
- **Condition-Aware** — Scores adjust based on 14 health conditions and 9 medication classes
- **Goal Matching** — Products scored against your personal health goals

### 🔬 Interaction Intelligence

- **Drug-Supplement Interactions** — Severity-ranked warnings (contraindicated → safe)
- **Evidence Levels** — Every warning tagged with clinical evidence strength
- **Clinical Citations** — Tap to view source studies and FDA links
- **Stack Safety Checker** — Detects stimulant stacking, blood thinner conflicts, duplicate nutrients

### 📊 Full Transparency

- **Score Education** — "What does this score mean?" overlay explains every component
- **BLOCKED Products** — FDA-recalled or banned products shown with hard-stop warnings
- **Proprietary Blend Alerts** — Flagged when dosages are hidden behind blend labels
- **Coverage Indicators** — Shows when ingredient data is incomplete

### 📱 Offline-First Architecture

- **180K+ Products** — Full database stored locally, zero network needed for scanning
- **Privacy-First** — Health data never leaves your device
- **OTA Updates** — Database refreshed from Supabase Storage with atomic swap + rollback
- **24h Detail Cache** — Rich product details cached locally after first fetch

### 🔒 Privacy by Design

- **Health data stays on-device** — Conditions, medications, allergens never sent to servers
- **No tracking of health choices** — Anonymous analytics only (scan counts, not what you scanned)
- **Transparent data dashboard** — See exactly what lives on your device vs. cloud

---

## Tech Stack

**Mobile App**

![Flutter](https://img.shields.io/badge/Flutter_3.8-02569B?logo=flutter&logoColor=white&style=flat-square)
![Dart](https://img.shields.io/badge/Dart_3.8-0175C2?logo=dart&logoColor=white&style=flat-square)
![Riverpod](https://img.shields.io/badge/Riverpod-blue?style=flat-square)
![GoRouter](https://img.shields.io/badge/GoRouter-purple?style=flat-square)
![Drift](https://img.shields.io/badge/Drift_SQLite-orange?style=flat-square)

**Backend & Data**

![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?logo=supabase&logoColor=white&style=flat-square)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL_17-4169E1?logo=postgresql&logoColor=white&style=flat-square)
![SQLite](https://img.shields.io/badge/SQLite-003B57?logo=sqlite&logoColor=white&style=flat-square)

**Data Pipeline**

![Python](https://img.shields.io/badge/Python_3.12-3776AB?logo=python&logoColor=white&style=flat-square)
![DSLD](https://img.shields.io/badge/NIH_DSLD-darkgreen?style=flat-square)
![FDA](https://img.shields.io/badge/FDA_Data-blue?style=flat-square)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    PharmaGuide App                       │
│                                                         │
│  ┌─────────┐  ┌──────────┐  ┌────────┐  ┌───────────┐ │
│  │  Scan   │  │  Search  │  │ Stack  │  │  Profile  │ │
│  └────┬────┘  └────┬─────┘  └───┬────┘  └─────┬─────┘ │
│       │            │            │              │       │
│  ┌────▼────────────▼────────────▼──────────────▼─────┐ │
│  │              Riverpod State Layer                  │ │
│  └────────────────────┬──────────────────────────────┘ │
│                       │                                 │
│  ┌────────────────────▼──────────────────────────────┐ │
│  │    ┌──────────────┐    ┌────────────────────┐     │ │
│  │    │ Core DB      │    │ User DB            │     │ │
│  │    │ (read-only)  │    │ (read-write)       │     │ │
│  │    │ 180K products│    │ profile, stack,    │     │ │
│  │    │ 88 columns   │    │ cache, favorites   │     │ │
│  │    └──────────────┘    └────────────────────┘     │ │
│  │              Drift ORM (SQLite)                    │ │
│  └───────────────────────────────────────────────────┘ │
│                       │                                 │
│  ┌────────────────────▼──────────────────────────────┐ │
│  │         Supabase (Auth + Detail Blobs + OTA)      │ │
│  └───────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

**Dual-database design:**
- `pharmaguide_core.db` — Read-only, 180K+ products, replaced via OTA download
- `user_data.db` — Read-write, user profile/stack/cache, never touched by OTA

---

## Project Structure

```
pharmaguide/
├── lib/
│   ├── core/
│   │   ├── constants/       # AppColors, Severity, Routes, SchemaIds, ScoreColors
│   │   ├── theme/           # AppTheme (WCAG AA, light + dark)
│   │   ├── widgets/         # VerdictBadge, OfflineBanner, ProductListItem
│   │   └── extensions/      # SafeJson helpers
│   ├── data/
│   │   ├── database/        # Drift schemas (core 88-col, user 5-table)
│   │   ├── providers/       # Riverpod DB providers
│   │   └── supabase/        # Client, DetailBlobService, SyncService
│   ├── features/
│   │   ├── home/            # Home screen with modular widgets
│   │   ├── scanner/         # Barcode scanner with verdict flash
│   │   ├── search/          # Debounced search with list/grid toggle
│   │   ├── product_detail/  # Score ring, breakdown, interactions, alternatives
│   │   ├── stack/           # My Stack + Wishlist tabs
│   │   ├── profile/         # 5-step setup, ProfileNotifier + persistence
│   │   ├── settings/        # 6-section settings with privacy dashboard
│   │   └── onboarding/      # 3-slide intro
│   └── services/            # Analytics, CrashReporting, Connectivity, ScanLimit
├── test/                    # 97 tests (unit + widget)
├── knowledge/               # ADRs, lessons learned, patterns, debugging playbook
└── assets/
    ├── reference_data/      # Bundled JSON (RDA, goals, taxonomy, timing)
    └── images/              # App icon, splash logo
```

---

## Safety Rules (Non-Negotiable)

These rules are enforced in code and code review:

| Rule | Enforcement |
|------|-------------|
| Health data never leaves device | Supabase gets auth tokens only, never conditions/meds/allergens |
| Never display "safe" when `mapped_coverage < 0.3` | UnknownIngredientBanner renders automatically |
| Severity order: `contraindicated > avoid > caution > monitor > safe` | Severity enum with weights, sorted in every display |
| Always show `evidence_level` on interaction warnings | InteractionWarningsList enforces badge display |
| FitScore never persisted | Computed fresh from current profile every time |
| All JSON parsing handles null/missing fields | SafeJson extensions with graceful fallbacks |

---

## Getting Started

### Prerequisites

- Flutter SDK 3.8+
- Xcode 16+ (iOS) / Android Studio (Android)
- A Supabase project with the PharmaGuide pipeline data

### Setup

```bash
# Clone
git clone https://github.com/seancheick/Pharmaguide.ai.git
cd Pharmaguide.ai

# Install dependencies
flutter pub get

# Generate Drift database code
dart run build_runner build --delete-conflicting-outputs

# Create .env file (see docs/SETUP.md for details)
cp .env.example .env
# Fill in SUPABASE_URL, SUPABASE_ANON_KEY

# Run
make run          # iOS/Android with secrets injected
make test         # Run all 97 tests
make check        # Analyze + test (CI gate)
```

---

## Scoring System

Every product receives a **FitScore** from 0 to 100 based on four evidence-based pillars:

| Pillar | Weight | What It Measures |
|--------|--------|-----------------|
| 🧪 **Ingredient Quality** | 30 pts | Dosage accuracy, bioavailability, form quality |
| 🛡️ **Safety & Purity** | 25 pts | Third-party testing, contaminant risk, interactions |
| 📚 **Evidence & Research** | 25 pts | Clinical studies, evidence strength, claim support |
| 🏭 **Brand Trust** | 20 pts | Manufacturing standards, transparency, track record |

### Verdicts

| Verdict | Score Range | Color |
|---------|------------|-------|
| **RECOMMENDED** | 85-100 | 🟢 |
| **GOOD** | 70-84 | 🟢 |
| **MODERATE** | 55-69 | 🟡 |
| **REVIEW** | 40-54 | 🟠 |
| **BLOCKED / UNSAFE** | N/A | 🔴 |

---

## Roadmap

| Version | Codename | Key Features |
|---------|----------|-------------|
| **V1.0** | Core Product | Scan, score, FitScore, stack safety, social sharing |
| **V1.1** | Medication Intelligence | RxNorm medication stack, depletion checker, comparison |
| **V2.0** | AI Intelligence | AI pharmacist chat, alternative suggestions, nutrient gaps |
| **V2.1** | Engagement | Dose reminders, reorder alerts, FDA notifications |
| **V3.0** | Platform | B2B API, white-label SDK, practitioner portal |

---

## Contributing

PharmaGuide is currently in active development. If you're interested in contributing, please open an issue to discuss your idea before submitting a PR.

---

## Disclaimer

PharmaGuide provides educational information only and is not a substitute for professional medical advice. Always consult with healthcare professionals before making decisions about supplements or medications.

---

<div align="center">

**Built with evidence. Designed for trust.**

*PharmaGuide — Because you deserve to know what you're taking.*

</div>
