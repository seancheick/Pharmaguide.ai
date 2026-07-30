// Widget tests for the ProfileSetupV2Screen guided save-and-continue
// flow (Phase 11.12).
//
// Covers:
//   - middle start wraps around: allergens → meds → age → sex →
//     goals → conditions → auto-exit to home
//   - last remaining section's sheet shows "Save & finish"
//   - sections visited this session are skipped on auto-advance
//   - direct tile tap still works; dismissing a sheet stops the chain
//   - sticky "Save profile" bar (single full save + exit) unchanged
//   - final save path runs exactly once per completed flow
//
// Run: flutter test test/features/profile/profile_setup_v2_flow_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/data/clinical_profile_schema.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/profile/v2/profile_setup_v2_screen.dart';

/// Counts `saveToDb` invocations instead of touching a real database
/// (the base notifier with a null db would silently no-op, hiding
/// whether the auto-save path actually fired).
class _CountingProfileNotifier extends ProfileNotifier {
  _CountingProfileNotifier();

  int saveCount = 0;

  @override
  Future<void> saveToDb() async {
    saveCount++;
  }
}

Widget _buildApp(_CountingProfileNotifier notifier) {
  final router = GoRouter(
    initialLocation: Routes.profileSetup,
    routes: [
      GoRoute(
        path: Routes.profileSetup,
        builder: (_, __) => const ProfileSetupV2Screen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (_, __) => const Scaffold(body: Text('HOME')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      profileProvider.overrideWith((ref) => notifier),
      clinicalProfileSchemaProvider.overrideWith(
        (ref) async => _testClinicalProfileSchema,
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

const _testClinicalProfileSchema = ClinicalProfileSchema(
  selectableConditions: <ClinicalProfileOption>[
    ClinicalProfileOption(
      id: 'pregnancy',
      label: 'Pregnancy',
      description: 'Currently pregnant.',
      displayPriority: 1,
    ),
  ],
  userSelectableFlags: <ClinicalProfileFlag>[
    ClinicalProfileFlag(
      id: 'severely_immunocompromised',
      label: 'Severely immunocompromised',
      description: 'Severely weakened immune defenses.',
      captureMode: ProfileCaptureMode.userSelectable,
    ),
  ],
  derivedFlagByCondition: <String, String>{'pregnancy': 'pregnant'},
);

/// Tall surface so every dashboard tile and sheet row is laid out.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Taps [label] inside the open sheet, then the sheet's primary save
/// CTA ([saveLabel]), and settles so the next chained sheet (if any)
/// is fully presented.
Future<void> _pickAndSave(
  WidgetTester tester,
  String label, {
  String saveLabel = 'Save & continue',
}) async {
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.tap(find.text(saveLabel));
  await tester.pumpAndSettle();
}

/// Flushes the final-save choreography: 240ms hold before navigation
/// plus the 1600ms snackbar auto-dismiss timer (which would otherwise
/// leak as a pending timer at test teardown).
Future<void> _settleFinalSave(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 1700));
  await tester.pumpAndSettle();
}

/// Dismisses the open sheet by tapping the scrim above it.
Future<void> _dismissSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(400, 40));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'middle start wraps around all unvisited sections and exits to home',
    (tester) async {
      _useTallSurface(tester);
      final notifier = _CountingProfileNotifier();
      await tester.pumpWidget(_buildApp(notifier));
      await tester.pumpAndSettle();

      // Start on section 3 of 7 — Allergies.
      await tester.tap(find.byIcon(Icons.warning_amber_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Any allergies we should flag?'), findsOneWidget);
      await _pickAndSave(tester, 'No known allergies');

      // 4 — Health history auto-opened.
      expect(find.text('Anything from your health history?'), findsOneWidget);
      await _pickAndSave(tester, 'None of these apply');

      // 5 — Medications auto-opened.
      expect(find.text('Anything you take regularly?'), findsOneWidget);
      await _pickAndSave(tester, 'No medications right now');

      // 5 — Age auto-opened.
      expect(find.text('Roughly how old are you?'), findsOneWidget);
      await _pickAndSave(tester, 'Prefer not to say');

      // 6 — Sex auto-opened.
      expect(find.text('Which dosing ranges apply?'), findsOneWidget);
      await _pickAndSave(tester, 'Female');

      // Wrap-around → 1 — Goals.
      expect(find.text('What are you focused on?'), findsOneWidget);
      await _pickAndSave(tester, 'No specific goal right now');

      // 2 — Conditions, the last remaining section: Save & finish.
      expect(find.text('Anything we should know about?'), findsOneWidget);
      expect(find.text('Save & finish'), findsOneWidget);
      expect(find.text('Save & continue'), findsNothing);
      await _pickAndSave(tester, 'None of these', saveLabel: 'Save & finish');
      await _settleFinalSave(tester);

      // Auto-exit to home; 6 intermediate auto-saves + 1 final save.
      expect(find.text('HOME'), findsOneWidget);
      expect(notifier.saveCount, 7);
    },
  );

  testWidgets('auto-advance skips sections already visited this session', (
    tester,
  ) async {
    _useTallSurface(tester);
    final notifier = _CountingProfileNotifier();
    await tester.pumpWidget(_buildApp(notifier));
    await tester.pumpAndSettle();

    // Visit Goals then Conditions through the chain.
    await tester.tap(find.byIcon(Icons.flag_outlined));
    await tester.pumpAndSettle();
    await _pickAndSave(tester, 'No specific goal right now');
    expect(find.text('Anything we should know about?'), findsOneWidget);
    await _pickAndSave(tester, 'None of these');

    // Allergens auto-opened — bail out here.
    expect(find.text('Any allergies we should flag?'), findsOneWidget);
    await _dismissSheet(tester);
    expect(find.text('HOME'), findsNothing);

    // Re-save Goals: the chain must skip visited Conditions and land
    // on Allergens.
    await tester.tap(find.byIcon(Icons.flag_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save & continue'));
    await tester.pumpAndSettle();
    expect(find.text('Anything we should know about?'), findsNothing);
    expect(find.text('Any allergies we should flag?'), findsOneWidget);
  });

  testWidgets('direct tile tap works; dismissing a sheet stops the chain', (
    tester,
  ) async {
    _useTallSurface(tester);
    final notifier = _CountingProfileNotifier();
    await tester.pumpWidget(_buildApp(notifier));
    await tester.pumpAndSettle();

    // Open Medications directly and dismiss without saving — no
    // navigation, no save, no chained sheet.
    await tester.tap(find.byIcon(Icons.medication_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Anything you take regularly?'), findsOneWidget);
    await _dismissSheet(tester);
    expect(find.text('Anything you take regularly?'), findsNothing);
    expect(find.text('HOME'), findsNothing);
    expect(notifier.saveCount, 0);

    // Save it for real: section is auto-saved + marked visited, and
    // the chain advances to the NEXT unvisited section (Age).
    await tester.tap(find.byIcon(Icons.medication_outlined));
    await tester.pumpAndSettle();
    await _pickAndSave(tester, 'No medications right now');
    expect(find.text('Roughly how old are you?'), findsOneWidget);
    expect(notifier.saveCount, 1);

    // Breaking the chain leaves the dashboard intact with the saved
    // summary reflected on the Medications tile.
    await _dismissSheet(tester);
    expect(find.text('No medications right now'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('sticky Save profile bar saves once and exits as before', (
    tester,
  ) async {
    _useTallSurface(tester);
    final notifier = _CountingProfileNotifier();
    await tester.pumpWidget(_buildApp(notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save profile'));
    await _settleFinalSave(tester);

    expect(find.text('HOME'), findsOneWidget);
    expect(notifier.saveCount, 1);
  });
}
