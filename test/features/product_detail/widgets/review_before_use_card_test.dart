import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/allergen_match.dart';
import 'package:pharmaguide/features/product_detail/free_from_match.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

class _StubProfileNotifier extends ProfileNotifier {
  _StubProfileNotifier(ProfileState initial) : super() {
    state = initial;
  }
}

InteractionWarning _warning({
  Severity severity = Severity.caution,
  String title = 'Interaction',
  String mechanism = '',
  String management = '',
  String? alertHeadline,
  String? alertBody,
}) {
  return InteractionWarning(
    severity: severity,
    evidenceLevel: EvidenceLevel.established,
    title: title,
    mechanism: mechanism,
    management: management,
    alertHeadline: alertHeadline,
    alertBody: alertBody,
  );
}

MatchedAllergen _allergen({
  String id = 'ALLERGEN_SOY',
  String displayName = 'Soy',
  String presenceType = 'contains',
  String severityLevel = 'moderate',
}) {
  return MatchedAllergen(
    id: id,
    displayName: displayName,
    presenceType: presenceType,
    severityLevel: severityLevel,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  List<InteractionWarning> warnings = const [],
  String interactionHint = '',
  Map<String, dynamic>? interactionSummary,
  List<MatchedAllergen> matchedAllergens = const [],
  List<FreeFromClaim> freeFromClaims = const [],
  List<String> freeFromConflicts = const [],
  ProfileState profile = const ProfileState(),
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileProvider.overrideWith((_) => _StubProfileNotifier(profile)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ReviewBeforeUseSection(
            warnings: warnings,
            interactionHint: interactionHint,
            interactionSummary: interactionSummary,
            matchedAllergens: matchedAllergens,
            freeFromClaims: freeFromClaims,
            freeFromConflicts: freeFromConflicts,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ReviewBeforeUseSection visibility', () {
    testWidgets('all empty renders nothing', (tester) async {
      await _pump(tester);

      expect(find.text('Review before use'), findsNothing);
    });

    testWidgets('no profile plus interaction hint renders calm nudge', (
      tester,
    ) async {
      await _pump(
        tester,
        interactionHint:
            '{"has_any": true, "highest_severity": "caution",'
            ' "condition_ids": ["diabetes"], "drug_class_ids": []}',
      );

      expect(find.text('This product has known interactions'), findsOneWidget);
      expect(find.text('Complete profile'), findsOneWidget);
    });

    testWidgets('profile populated but no matching warning hides card', (
      tester,
    ) async {
      await _pump(
        tester,
        profile: const ProfileState(conditions: ['hypertension']),
        interactionHint:
            '{"has_any": true, "highest_severity": "caution",'
            ' "condition_ids": ["diabetes"], "drug_class_ids": []}',
      );

      expect(find.text('Review before use'), findsNothing);
    });
  });

  group('ReviewBeforeUseSection warnings', () {
    testWidgets('caution warning is collapsed by default', (tester) async {
      await _pump(
        tester,
        warnings: [_warning(severity: Severity.caution, title: 'C-row')],
        profile: const ProfileState(conditions: ['anything']),
      );

      expect(find.text('Review before use'), findsOneWidget);
      expect(find.text('1 thing to review before use'), findsOneWidget);
      expect(find.text('C-row'), findsNothing);

      await tester.tap(find.text('Review before use'));
      await tester.pumpAndSettle();

      expect(find.text('C-row'), findsOneWidget);
    });

    testWidgets('avoid warning auto-expands', (tester) async {
      await _pump(
        tester,
        warnings: [
          _warning(
            severity: Severity.avoid,
            title: 'A-row',
            mechanism: 'A-mech',
          ),
        ],
        profile: const ProfileState(conditions: ['anything']),
      );
      await tester.pumpAndSettle();

      expect(find.text('A-row'), findsOneWidget);
      expect(find.textContaining('A-mech'), findsOneWidget);
    });

    testWidgets('uses authored warning copy instead of clinical rationale', (
      tester,
    ) async {
      const longMechanism =
          'Gastric acid and pepsin are required to cleave vitamin B12 from '
          'food proteins. Acid suppression impairs liberation and can reduce '
          'absorption from dietary sources over long-term use.';
      const longManagement =
          'Review serum B12, methylmalonic acid, homocysteine, duration of '
          'therapy, symptoms, dietary intake, and clinician-directed '
          'supplementation strategy.';

      await _pump(
        tester,
        warnings: [
          _warning(
            severity: Severity.avoid,
            title: 'Vitamin B12 / trying to conceive',
            mechanism: longMechanism,
            management: longManagement,
            alertHeadline: 'B12 is recommended preconception',
            alertBody:
                'B12 supports early pregnancy nutrition. If you are trying '
                'to conceive, make sure your prenatal plan covers it.',
          ),
        ],
        profile: const ProfileState(conditions: ['ttc']),
      );
      await tester.pumpAndSettle();

      expect(find.text('B12 is recommended preconception'), findsOneWidget);
      expect(find.textContaining('B12 supports early pregnancy'), findsOneWidget);
      expect(find.textContaining('Gastric acid and pepsin'), findsNothing);
      expect(find.textContaining('methylmalonic acid'), findsNothing);
    });

    testWidgets('contains allergen bumps tone to danger and auto-expands', (
      tester,
    ) async {
      await _pump(
        tester,
        warnings: [_warning(severity: Severity.caution, title: 'C-row')],
        matchedAllergens: [_allergen(presenceType: 'contains')],
        profile: const ProfileState(
          conditions: ['anything'],
          allergens: ['ALLERGEN_SOY'],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Soy'), findsOneWidget);
      expect(find.text('C-row'), findsOneWidget);

      final allergenRect = tester.getRect(find.text('Soy'));
      final warningRect = tester.getRect(find.text('C-row'));
      expect(allergenRect.top, lessThan(warningRect.top));
    });
  });

  group('ReviewBeforeUseSection allergens', () {
    testWidgets('may_contain allergen is collapsed until tapped', (
      tester,
    ) async {
      await _pump(
        tester,
        matchedAllergens: [
          _allergen(displayName: 'Tree nuts', presenceType: 'may_contain'),
        ],
        profile: const ProfileState(allergens: ['ALLERGEN_TREE_NUTS']),
      );

      expect(find.text('Review before use'), findsOneWidget);
      expect(find.text('Tree nuts'), findsNothing);

      await tester.tap(find.text('Review before use'));
      await tester.pumpAndSettle();

      expect(find.text('Tree nuts'), findsOneWidget);
      expect(find.textContaining('May contain'), findsOneWidget);
    });

    testWidgets('severe contains allergen keeps severe signal visible', (
      tester,
    ) async {
      await _pump(
        tester,
        matchedAllergens: [
          _allergen(
            displayName: 'Peanuts',
            presenceType: 'contains',
            severityLevel: 'high',
          ),
        ],
        profile: const ProfileState(allergens: ['ALLERGEN_PEANUTS']),
      );
      await tester.pumpAndSettle();

      expect(find.text('Peanuts'), findsOneWidget);
      expect(find.textContaining('severe'), findsOneWidget);
    });
  });

  group('ReviewBeforeUseSection count copy', () {
    testWidgets('singular and plural counts include warnings/allergens only', (
      tester,
    ) async {
      await _pump(
        tester,
        warnings: [_warning(severity: Severity.caution, title: 'X')],
        freeFromClaims: const [
          FreeFromClaim(
            label: 'Gluten-free',
            concern: 'gluten',
            status: FreeFromStatus.certified,
          ),
        ],
        profile: const ProfileState(
          conditions: ['anything'],
          allergens: ['ALLERGEN_WHEAT'],
        ),
      );
      expect(find.text('1 thing to review before use'), findsOneWidget);

      await _pump(
        tester,
        warnings: [
          _warning(severity: Severity.caution, title: 'C1'),
          _warning(severity: Severity.monitor, title: 'M1'),
        ],
        matchedAllergens: [_allergen(presenceType: 'manufactured_in_facility')],
        profile: const ProfileState(
          conditions: ['anything'],
          allergens: ['ALLERGEN_SOY'],
        ),
      );
      expect(find.text('3 things to review before use'), findsOneWidget);
    });
  });

  group('ReviewBeforeUseSection free-from claims', () {
    testWidgets('certified-only renders affirmative card and verified row', (
      tester,
    ) async {
      await _pump(
        tester,
        freeFromClaims: const [
          FreeFromClaim(
            label: 'Gluten-free',
            concern: 'gluten',
            status: FreeFromStatus.certified,
          ),
        ],
        profile: const ProfileState(allergens: ['ALLERGEN_WHEAT']),
      );
      await tester.pumpAndSettle();

      expect(find.text('Allergen check passed'), findsOneWidget);
      expect(find.text('1 allergen claim verified'), findsOneWidget);
      expect(find.text('Gluten-free'), findsOneWidget);
      expect(find.textContaining('Verified'), findsOneWidget);
    });

    testWidgets('unknown-only renders honest unknown row', (tester) async {
      await _pump(
        tester,
        freeFromClaims: const [
          FreeFromClaim(
            label: 'Gluten-free',
            concern: 'gluten',
            status: FreeFromStatus.unknown,
          ),
        ],
        profile: const ProfileState(allergens: ['ALLERGEN_WHEAT']),
      );
      await tester.pumpAndSettle();

      expect(find.text('Allergen check'), findsOneWidget);
      expect(find.text('Gluten-free'), findsOneWidget);
      expect(find.textContaining('Unverified'), findsOneWidget);
    });

    testWidgets('notClaimed status hides when it is the only signal', (
      tester,
    ) async {
      await _pump(
        tester,
        freeFromClaims: const [
          FreeFromClaim(
            label: 'Gluten-free',
            concern: 'gluten',
            status: FreeFromStatus.notClaimed,
          ),
        ],
        profile: const ProfileState(allergens: ['ALLERGEN_WHEAT']),
      );

      expect(find.text('Allergen check'), findsNothing);
      expect(find.text('Allergen check passed'), findsNothing);
    });

    testWidgets('mixed warning plus certified claim keeps action count', (
      tester,
    ) async {
      await _pump(
        tester,
        warnings: [
          _warning(severity: Severity.contraindicated, title: 'X-warn'),
        ],
        freeFromClaims: const [
          FreeFromClaim(
            label: 'Soy-free',
            concern: 'soy',
            status: FreeFromStatus.certified,
          ),
        ],
        profile: const ProfileState(
          conditions: ['anything'],
          allergens: ['ALLERGEN_SOY'],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Review before use'), findsOneWidget);
      expect(find.text('1 thing to review before use'), findsOneWidget);
      expect(find.text('X-warn'), findsOneWidget);
      expect(find.text('Soy-free'), findsOneWidget);
    });
  });

  group('ReviewBeforeUseSection conflict footer', () {
    testWidgets('free-from conflict footer renders below card', (tester) async {
      await _pump(
        tester,
        warnings: [_warning(severity: Severity.caution, title: 'C-warn')],
        freeFromConflicts: const ['gluten'],
        profile: const ProfileState(
          conditions: ['anything'],
          allergens: ['ALLERGEN_WHEAT'],
        ),
      );

      expect(find.text('C-warn'), findsNothing);
      expect(find.text('Conflicting label evidence'), findsOneWidget);
      expect(find.textContaining('Marked gluten-free'), findsOneWidget);
    });
  });
}
