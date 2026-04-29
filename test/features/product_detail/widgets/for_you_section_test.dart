// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.2.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/features/product_detail/widgets/for_you_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

/// Test fixture builder — keeps every test's setup short.
/// [scoreFit20] drives the tier banding (0..20); state defaults to goodFit.
FitScoreResult _fit({
  required double scoreFit20,
  FitAssessmentState state = FitAssessmentState.goodFit,
  List<String> reasons = const [],
}) {
  return FitScoreResult(
    scoreFit20: scoreFit20,
    e1: 0,
    e2a: 0,
    e2b: 0,
    e2c: 0,
    missingFields: const [],
    maxPossible: 100,
    state: state,
    reasons: reasons,
  );
}

InteractionWarning _warning({
  required Severity severity,
  String title = 'Test alert',
  String? alertHeadline,
}) {
  return InteractionWarning(
    severity: severity,
    evidenceLevel: EvidenceLevel.theoretical,
    title: title,
    mechanism: 'mech',
    management: 'mgmt',
    alertHeadline: alertHeadline,
  );
}

/// Pumps the section inside a real ProviderScope + MaterialApp with a
/// profile override. Returns the BuildContext for any post-pump
/// inspection.
Future<void> _pumpSection(
  WidgetTester tester, {
  required ProfileState profile,
  FitScoreResult? fitResult,
  List<InteractionWarning> warnings = const [],
  Severity maxSeverity = Severity.safe,
  String? topGoalLabel,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileProvider.overrideWith((ref) => _StubProfileNotifier(profile)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ForYouSection(
                fitResult: fitResult,
                warnings: warnings,
                maxSeverity: maxSeverity,
                topGoalLabel: topGoalLabel,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // Profile load + alert filter rebuild.
  await tester.pump();
}

/// Riverpod stub that returns a specific profile state without going
/// through the user-database storage layer. ProfileNotifier extends
/// StateNotifier (not Notifier), so we set state via the constructor
/// body rather than overriding `build()`.
class _StubProfileNotifier extends ProfileNotifier {
  _StubProfileNotifier(ProfileState initial) {
    state = initial;
  }
}

void main() {
  group('ForYouSection — empty profile', () {
    testWidgets('renders the affordance + tap routes to profile setup',
        (tester) async {
      await _pumpSection(
        tester,
        profile: const ProfileState(),
      );
      expect(find.text('For You'), findsOneWidget);
      expect(find.text('Add your profile to personalize'), findsOneWidget);
      // The verdict row + chips do NOT render in empty state.
      expect(find.text('Strong match for your profile'), findsNothing);
      expect(find.byType(Wrap), findsNothing);
    });

    testWidgets('treats profile with only a nickname as empty', (tester) async {
      // A profile that has a nickname but no goals/conditions/drug
      // classes/allergens still has nothing to personalize on. Render
      // the affordance.
      await _pumpSection(
        tester,
        profile: const ProfileState(nickname: 'Sean'),
      );
      expect(find.text('Add your profile to personalize'), findsOneWidget);
    });

    testWidgets(
      'allergens-only profile DOES render the section (no longer empty-state)',
      (tester) async {
        // Audit fix 2026-04-29: an allergens-only profile is enough
        // signal to render the alerts list — without this branch a
        // peanut-allergic user looking at a peanut-containing
        // supplement would miss the warning entirely.
        await _pumpSection(
          tester,
          profile: const ProfileState(allergens: ['peanut']),
          fitResult: _fit(scoreFit20: 16),
          maxSeverity: Severity.safe,
        );
        // Empty-state CTA must NOT render.
        expect(find.text('Add your profile to personalize'), findsNothing);
        // Section header IS visible (proves we entered the populated
        // path, not the empty-state path).
        expect(find.text('For You'), findsOneWidget);
      },
    );
  });

  group('ForYouSection — verdict copy + risk-gating', () {
    testWidgets(
      'Safe + good fit + topGoalLabel "sleep" → '
      '"Strong match for your sleep goal"',
      (tester) async {
        await _pumpSection(
          tester,
          profile: const ProfileState(goals: ['sleep_quality']),
          fitResult: _fit(scoreFit20: 18.4),
          maxSeverity: Severity.safe,
          topGoalLabel: 'sleep',
        );
        expect(find.text('Strong match for your sleep goal'), findsOneWidget);
      },
    );

    testWidgets('Avoid → "Not recommended for your profile" AND no fit number',
        (tester) async {
      // Risk-gate test: even with a high underlying score, Avoid
      // hides the fit pill entirely. T1.3's core invariant.
      await _pumpSection(
        tester,
        profile: const ProfileState(goals: ['sleep_quality']),
        fitResult: _fit(scoreFit20: 17.6),
        maxSeverity: Severity.avoid,
        topGoalLabel: 'sleep',
      );
      expect(find.text('Not recommended for your profile'), findsOneWidget);
      // The headline must not name the goal — degrades to "your profile".
      expect(find.textContaining('sleep goal'), findsNothing);
    });

    testWidgets('Contraindicated → "Not recommended" + no fit number',
        (tester) async {
      await _pumpSection(
        tester,
        profile: const ProfileState(goals: ['sleep_quality']),
        fitResult: _fit(scoreFit20: 19),
        maxSeverity: Severity.contraindicated,
        topGoalLabel: 'sleep',
      );
      expect(find.text('Not recommended for your profile'), findsOneWidget);
    });

    testWidgets('Caution + fit 80 → "Good match for your profile" — fit shown',
        (tester) async {
      // Caution doesn't gate the fit pill; the alert renders below.
      await _pumpSection(
        tester,
        profile: const ProfileState(goals: ['sleep_quality']),
        fitResult: _fit(scoreFit20: 16),
        warnings: [_warning(severity: Severity.caution)],
        maxSeverity: Severity.caution,
      );
      expect(find.text('Good match for your profile'), findsOneWidget);
      // Caution alert IS rendered.
      expect(find.text('CAUTION'), findsOneWidget);
    });

    testWidgets('Safe + fit 35 → "Limited fit for your profile" + 🟡 emoji',
        (tester) async {
      await _pumpSection(
        tester,
        profile: const ProfileState(goals: ['sleep_quality']),
        fitResult: _fit(scoreFit20: 7.0),
        maxSeverity: Severity.safe,
      );
      expect(find.text('Limited fit for your profile'), findsOneWidget);
      expect(find.text('🟡'), findsOneWidget);
    });

    testWidgets(
      'Safe + fit 25 → "Not recommended for your profile" '
      '(low fit even when safe)',
      (tester) async {
        await _pumpSection(
          tester,
          profile: const ProfileState(goals: ['sleep_quality']),
          fitResult: _fit(scoreFit20: 5),
          maxSeverity: Severity.safe,
        );
        expect(find.text('Not recommended for your profile'), findsOneWidget);
      },
    );

    testWidgets('null fitResult → "Add more details to personalize"',
        (tester) async {
      // Profile populated, but FitScore math hasn't produced a result
      // yet (e.g., still loading or upstream error). Render the
      // incomplete-fit incomplete state, NOT the empty-profile one.
      await _pumpSection(
        tester,
        profile: const ProfileState(goals: ['sleep_quality']),
        fitResult: null,
      );
      expect(find.text('Add more details to personalize'), findsOneWidget);
      expect(find.text('ℹ️'), findsOneWidget);
    });
  });

  group('ForYouSection — alert priority + filtering', () {
    testWidgets('multiple alerts render in severity order: contra > avoid > '
        'caution', (tester) async {
      await _pumpSection(
        tester,
        profile: const ProfileState(drugClasses: ['anticoagulants']),
        fitResult: _fit(scoreFit20: 14),
        warnings: [
          _warning(
            severity: Severity.caution,
            alertHeadline: 'Caution alert',
          ),
          _warning(
            severity: Severity.contraindicated,
            alertHeadline: 'Contra alert',
          ),
          _warning(
            severity: Severity.avoid,
            alertHeadline: 'Avoid alert',
          ),
        ],
        maxSeverity: Severity.contraindicated,
      );
      // Pull the rendered text in document order.
      final contraPos = tester
          .getTopLeft(find.text('Contra alert'))
          .dy;
      final avoidPos = tester
          .getTopLeft(find.text('Avoid alert'))
          .dy;
      final cautionPos = tester
          .getTopLeft(find.text('Caution alert'))
          .dy;
      // Higher severity renders first → smaller y-coordinate.
      expect(contraPos, lessThan(avoidPos));
      expect(avoidPos, lessThan(cautionPos));
    });

    testWidgets('monitor + safe + informational warnings are filtered out',
        (tester) async {
      // Per spec: Section 2 only shows contra/avoid/caution. Lower
      // severities live elsewhere (Section 7 Interactions, etc.).
      await _pumpSection(
        tester,
        profile: const ProfileState(drugClasses: ['anticoagulants']),
        fitResult: _fit(scoreFit20: 14),
        warnings: [
          _warning(severity: Severity.monitor, alertHeadline: 'Monitor row'),
          _warning(severity: Severity.informational, alertHeadline: 'Info row'),
          _warning(severity: Severity.safe, alertHeadline: 'Safe row'),
        ],
        maxSeverity: Severity.monitor,
      );
      expect(find.text('Monitor row'), findsNothing);
      expect(find.text('Info row'), findsNothing);
      expect(find.text('Safe row'), findsNothing);
      // Severity LABELs from those tiers should also be absent.
      expect(find.text('MONITOR'), findsNothing);
      expect(find.text('INFO'), findsNothing);
    });

    testWidgets('empty warnings list → no alerts row rendered', (tester) async {
      await _pumpSection(
        tester,
        profile: const ProfileState(goals: ['sleep_quality']),
        fitResult: _fit(scoreFit20: 18),
        warnings: const [],
        maxSeverity: Severity.safe,
      );
      // No severity labels.
      expect(find.text('CAUTION'), findsNothing);
      expect(find.text('AVOID'), findsNothing);
      expect(find.text('BLOCK — Do Not Use'), findsNothing);
    });
  });

  group('ForYouSection — Why this fits expander', () {
    testWidgets(
      'expander shows "Why this fits you" header + collapses bullets by default',
      (tester) async {
        await _pumpSection(
          tester,
          profile: const ProfileState(goals: ['sleep_quality']),
          fitResult: _fit(
            scoreFit20: 17.6,
            reasons: const [
              'Matches your sleep_quality goal',
              'Effective magnesium dose for sleep',
              'No conditions on file conflict',
              'Brand has third-party testing',
              'Does not interact with any of your meds',
            ],
          ),
          maxSeverity: Severity.safe,
        );
        expect(find.text('Why this fits you'), findsOneWidget);
        // Bullets are not visible until tapped.
        expect(find.text('Matches your sleep_quality goal'), findsNothing);
      },
    );

    testWidgets(
      'tapping the expander reveals up to 4 deterministic bullets '
      '(takes the first 4 reasons)',
      (tester) async {
        await _pumpSection(
          tester,
          profile: const ProfileState(goals: ['sleep_quality']),
          fitResult: _fit(
            scoreFit20: 17.6,
            reasons: const [
              'Reason one',
              'Reason two',
              'Reason three',
              'Reason four',
              'Reason five — should NOT render (cap at 4)',
            ],
          ),
          maxSeverity: Severity.safe,
        );
        await tester.tap(find.text('Why this fits you'));
        await tester.pumpAndSettle();
        expect(find.text('Reason one'), findsOneWidget);
        expect(find.text('Reason four'), findsOneWidget);
        expect(
          find.text('Reason five — should NOT render (cap at 4)'),
          findsNothing,
        );
      },
    );

    testWidgets('expander hidden when reasons list is empty', (tester) async {
      await _pumpSection(
        tester,
        profile: const ProfileState(goals: ['sleep_quality']),
        fitResult: _fit(scoreFit20: 18, reasons: const []),
        maxSeverity: Severity.safe,
      );
      expect(find.text('Why this fits you'), findsNothing);
    });
  });

  group('ForYouSection — context chips', () {
    testWidgets(
      'profile signals render as up-to-4 outline chips (humanized)',
      (tester) async {
        await _pumpSection(
          tester,
          profile: const ProfileState(
            goals: ['sleep_quality', 'energy_focus'],
            conditions: ['hypertension'],
            drugClasses: ['anticoagulants'],
          ),
          fitResult: _fit(scoreFit20: 16),
          maxSeverity: Severity.safe,
        );
        // snake_case → "Snake Case" humanizer.
        expect(find.text('Sleep Quality'), findsOneWidget);
        expect(find.text('Energy Focus'), findsOneWidget);
        expect(find.text('Hypertension'), findsOneWidget);
        expect(find.text('Anticoagulants'), findsOneWidget);
      },
    );

    testWidgets(
      'profile with 5+ signals caps the chip render at 4 to keep the row '
      'scannable',
      (tester) async {
        await _pumpSection(
          tester,
          profile: const ProfileState(
            goals: ['a_one', 'a_two'],
            conditions: ['c_one', 'c_two'],
            drugClasses: ['d_one', 'd_two'],
          ),
          fitResult: _fit(scoreFit20: 16),
          maxSeverity: Severity.safe,
        );
        // Cap is 4: 2 goals + 2 conditions = 4. d_one / d_two should
        // not render even though they're in the profile.
        expect(find.text('A One'), findsOneWidget);
        expect(find.text('A Two'), findsOneWidget);
        expect(find.text('C One'), findsOneWidget);
        expect(find.text('C Two'), findsOneWidget);
        expect(find.text('D One'), findsNothing);
        expect(find.text('D Two'), findsNothing);
      },
    );
  });
}
