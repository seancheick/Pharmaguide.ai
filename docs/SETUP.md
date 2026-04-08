# PharmaGuide Flutter App — Setup & Testing Guide

Complete instructions for running, testing, and deploying the PharmaGuide Flutter app on simulator, emulator, and physical devices.

---

## Prerequisites

### Required Software

- **Flutter SDK** — `3.24.0` or later
  - [Install Flutter](https://flutter.dev/docs/get-started/install)
  - Verify: `flutter --version`

- **Dart SDK** — included with Flutter
  - Verify: `dart --version`

- **iOS** (macOS only)
  - Xcode 15+ (via App Store)
  - CocoaPods: `sudo gem install cocoapods`
  - Verify: `pod repo update`

- **Android**
  - Android Studio + Android SDK
  - Min API Level: 21 (Android 5.0)
  - Target API Level: 35 (Android 15)

### Environment File

Create `.env` in the project root (`/Users/seancheick/PharmaGuide ai/`):

```bash
# Copy from .env.example or pipeline's final build
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
GEMINI_API_KEY=AIza...
```

**⚠️ CRITICAL:** 
- `.env` is in `.gitignore` — NEVER commit it
- The **same keys** used by the pipeline must be here
- Verify Supabase key is live: `make verify-supabase`

---

## Quick Start

### 1. Install Dependencies

```bash
cd "/Users/seancheick/PharmaGuide ai"

# Get Pub packages
flutter pub get

# Generate code (Riverpod, Drift, build_runner, freezed)
make gen
```

### 2. Run the App

**Simplest way (uses Makefile with .env secrets injected):**

```bash
make run
```

This automatically:
- Reads `.env` 
- Injects `--dart-define=SUPABASE_URL=...` and other secrets
- Runs on the default device (emulator or connected phone)

**Or run manually:**

```bash
flutter run \
  --dart-define=SUPABASE_URL=$(grep SUPABASE_URL .env | cut -d'=' -f2) \
  --dart-define=SUPABASE_ANON_KEY=$(grep SUPABASE_ANON_KEY .env | cut -d'=' -f2) \
  --dart-define=GEMINI_API_KEY=$(grep GEMINI_API_KEY .env | cut -d'=' -f2)
```

---

## iOS — Simulator & Physical Device

### iOS Simulator (macOS only)

**Start the simulator:**

```bash
open -a Simulator
```

Or use Xcode:
```bash
xcrun simctl list devices
xcrun simctl boot "iPhone 15"  # or your preferred device
open -a Simulator
```

**Run the app on simulator:**

```bash
make run
# or
flutter run
```

The app will start in the simulator. Use the back button to navigate; use pinch/two-finger scroll to zoom.

### iOS Physical Device

**Prerequisites:**
- iPhone 12 or later
- Xcode installed (for provisioning)
- Apple Developer account (free or paid)
- USB cable

**Connect the device:**

```bash
# List connected devices
flutter devices

# Verify your iPhone shows as "ios"
```

**Trust the developer on your iPhone:**
- Settings → General → Device Management → Trust [Your Developer Name]

**Run on device:**

```bash
make run
# Select your iPhone from the prompt (usually: "ios" or "All")
```

**Troubleshooting:**
- If Xcode complains about signing: `open ios/Runner.xcworkspace` and set your team in Xcode
- If app doesn't launch: Check device storage (needs ~500 MB free)
- If "No development team set": Run `flutter run` and answer the provisioning prompts

---

## Android — Emulator & Physical Device

### Android Emulator

**Check installed emulators:**

```bash
flutter emulators
```

**Start an emulator:**

```bash
flutter emulators --launch Pixel_7_API_35
# or use Android Studio: Tools → Device Manager
```

**Run the app on emulator:**

```bash
make run
```

The app will install and launch on the emulator.

### Android Physical Device

**Prerequisites:**
- Android phone with API 21+ (Android 5.0 or later)
- USB cable + USB debugging enabled
- USB driver installed (Windows: download from phone manufacturer)

**Enable USB Debugging:**

1. Settings → About Phone → tap "Build Number" 7 times
2. Settings → Developer Options → enable "USB Debugging"
3. Tap "Revoke USB Debugging Authorizations" (optional, for clean start)

**Connect the device:**

```bash
# List connected devices
adb devices

# Verify your phone shows as "device" (not "offline")
```

**Run on device:**

```bash
make run
```

**Troubleshooting:**
- If "offline": Reconnect USB, dismiss auth prompt on phone
- If "no devices": Install USB driver (Android Studio → SDK Manager → search "Google USB Driver")
- If app won't install: Run `flutter clean && flutter pub get` first

---

## Testing the App

### Run All Tests

```bash
make test
# or
flutter test
```

Expected output:
```
✓ 97 tests, 0 failures
Ran 97 tests in X.XXs
```

### Run Specific Test File

```bash
flutter test test/features/search/search_screen_test.dart
```

### Test Coverage

```bash
# Generate coverage report
flutter test --coverage

# View HTML report (requires `lcov` on macOS: `brew install lcov`)
genhtml coverage/lcov.info -o coverage/
open coverage/index.html
```

### Manual Testing Checklist

After running the app, test these flows:

**Search Flow:**
- [ ] Open app → see "Search Supplements" screen
- [ ] Type "aspirin" in search box → see results
- [ ] Tap a result → navigate to detail screen

**Barcode Scan Flow:**
- [ ] Tap barcode icon (QR code button)
- [ ] Point phone at a product barcode → scan and auto-search
- [ ] See product details appear

**Detail Screen:**
- [ ] View product info: name, dosage, manufacturer
- [ ] Scroll down → see interactions/warnings
- [ ] See "FitScore" (if user added profile)

**Profile Setup:**
- [ ] Tap profile icon → profile screen
- [ ] Enter age, gender, conditions → save
- [ ] Return to search → FitScore should now appear on products

**Recent Searches:**
- [ ] Do 3+ searches
- [ ] Return to search screen → see "Recently Viewed" list
- [ ] Tap a recent item → re-open detail

**Offline Mode:**
- [ ] Toggle airplane mode on
- [ ] Search for a product you've seen before → should still work (from local DB)
- [ ] Try searching for a new product → should show message (no internet)

---

## Build for Release

### iOS

```bash
make build-ios

# or manually:
flutter build ios --release

# Create an IPA for TestFlight or App Store
open ios/Runner.xcworkspace
# In Xcode: Product → Archive → Distribute App
```

### Android

```bash
make build-android

# or manually:
flutter build apk --release
flutter build appbundle --release

# APK: `build/app/outputs/flutter-apk/app-release.apk`
# AppBundle: `build/app/outputs/bundle/release/app-release.aab` (for Play Store)
```

---

## Makefile Commands Reference

```bash
make run                # Run on default device (iOS simulator or Android emulator)
make run-ios           # Run on iOS simulator
make run-android       # Run on Android emulator
make build-ios         # Build iOS release (IPA)
make build-android     # Build Android release (APK + AppBundle)
make test              # Run all tests (97 tests, ~30s)
make analyze           # Run linter (must pass 0 warnings)
make format            # Format code (dart format lib/ test/)
make check             # Run: analyze + test (CI gate)
make gen               # Generate code (build_runner, freezed, Drift)
make verify-supabase   # Test Supabase anon key (HTTP 200 auth endpoint)
make help              # Show all targets
```

---

## Debugging

### Enable Debug Logging

Set environment variable before running:

```bash
# Show all Flutter logs
flutter run -v

# or pipe to file
flutter run -v > /tmp/flutter.log 2>&1
```

### Flutter DevTools

```bash
# Start DevTools (interactive debugger + widget inspector)
flutter pub global activate devtools
devtools

# Then visit http://localhost:9100 in browser
```

### Common Issues

| Issue | Fix |
|-------|-----|
| **"No connected devices"** | Start emulator/simulator OR connect USB device + enable USB Debugging |
| **"SIGABRT in Drift"** | Run `make gen` to rebuild database schema |
| **"FitScore not showing"** | Add profile info (age/gender/conditions) in profile screen |
| **"Search returns no results"** | Verify `pharmaguide_core.db` exists in app bundle (dev build includes it) |
| **"Barcode scanner not working"** | Grant camera permission when prompted on first use |
| **Offline mode broken** | Check that `user_data.db` exists in app documents directory |

---

## Next Steps

Once the app runs locally:

1. **Test on your phone** — follow the "Manual Testing Checklist" above
2. **Check test output** — `make test` should show 97 passing tests
3. **Review logs** — `flutter run -v` for detailed output
4. **File issues** — Document any bugs with steps to reproduce

---

## Questions?

Refer to:
- Flutter docs: https://flutter.dev/docs
- PharmaGuide CLAUDE.md: Safety rules + architecture
- PharmaGuide knowledge/: architecture-decisions.md, debugging-playbook.md
