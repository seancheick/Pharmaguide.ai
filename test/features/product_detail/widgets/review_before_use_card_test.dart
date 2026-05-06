// Sprint: docs/sprints/product_detail_page_sprint.md — T2A.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/allergen_match.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/product_detail/widgets/review_before_use_card.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

class _StubProfileNotifier extends ProfileNotifier {
  _StubProfileNotifier(ProfileState initial) : super() {
    state = initial;
  }
}

InteractionWarning _w({
  Severity severity = Severity.caution,
  String title = 'Interaction',
  String mechanism = '',
  String management = '',
}) {
  return InteractionWarning(
    severity: severity,
    evidenceLevel: EvidenceLevel.established,
    title: title,
    mechanism: mechanism,
    management: management,
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
  ProfileState profile = const ProfileState(),
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileProvider.overrideWith((_) => _StubProfileNotifier(profile)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ReviewBeforeUseCard(
            warnings: warnings,
            interactionHint: interactionHint,
            interactionSummary: interactionSummary,
            matchedAllergens: matchedAllergens,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ReviewBeforeUseCard — visibility', () {
    testWidgets('all empty → renders nothing', (tester) async {
      await _pump(tester);
      expect(find.text('Review before use'), findsNothing);
    });

    testWidgets(
      'no profile + interactionHint.has_any → neutral nudge with CTA',
      (tester) async {
        await _pump(
          tester,
          interactionHint: '{"has_any": true, "highest_severity": "caution",'
              ' "condition_ids": ["diabetes"], "drug_class_ids": []}',
        );
        expect(find.text('This product has known interactions'), findsOneWidget);
        expect(find.text('Complete profile'), findsOneWidget);
      },
    );

    testWidgets(
      'profile populated, no warnings, no allergens, no match → hidden',
      (tester) async {
        await _pump(
          tester,
          profile: const ProfileState(conditions: ['hypertension']),
          interactionHint: '{"has_any": true, "highest_severity": "caution",'
              ' "condition_ids": ["diabetes"], "drug_class_ids": []}',
        );
        expect(find.text('Review before use'), findsNothing);
      },
    );
  });

  group('ReviewBeforeUseCard — warnings', () {
    testWidgets('monitor warning → collapsed by default', (tester) async {
      await _pump(
        tester,
        warnings: [_w(severity: Severity.monitor, title: 'M-row')],
        profile: const ProfileState(conditions: ['anything']),
      );
      expect(find.text('Review before use'), findsOneWidget);
      expect(find.text('1 thing to review before use'), findsOneWidget);
      // Body hidden until tap.
      expect(find.text('M-row'), findsNothing);
    });

    testWidgets('caution warning → collapsed by default', (tester) async {
      await _pump(
        tester,
        warnings: [_w(severity: Severity.caution, title: 'C-row')],
        profile: const ProfileState(conditions: ['anything']),
      );
      expect(find.text('Review before use'), findsOneWidget);
      expect(find.text('C-row'), findsNothing);
    });

    testWidgets('avoid warning → auto-expanded', (tester) async {
      await _pump(
        tester,
        warnings: [
          _w(severity: Severity.avoid, title: 'A-row', mechanism: 'A-mech'),
        ],
        profile: const ProfileState(conditions: ['anything']),
      );
      await tester.pumpAndSettle();
      expect(find.text('A-row'), findsOneWidget);
      expect(find.text('A-mech'), findsOneWidget);
    });

    testWidgets('contraindicated warning → auto-expanded', (tester) async {
      await _pump(
        tester,
        warnings: [_w(severity: Severity.contraindicated, title: 'X-row')],
        profile: const ProfileState(conditions: ['anything']),
      );
      await tester.pumpAndSettle();
      expect(find.text('X-row'), findsOneWidget);
    });

    testWidgets('tap header toggles expand/collapse', (tester) async {
      await _pump(
        tester,
        warnings: [_w(severity: Severity.caution, title: 'C-row')],
        profile: const ProfileState(conditions: ['anything']),
      );
      expect(find.text('C-row'), findsNothing);
      await tester.tap(find.text('Review before use'));
      await tester.pumpAndSettle();
      expect(find.text('C-row'), findsOneWidget);
      await tester.tap(find.text('Review before use'));
      await tester.pumpAndSettle();
      expect(find.text('C-row'), findsNothing);
    });
  });

  group('ReviewBeforeUseCard — allergen rows', () {
    testWidgets(
      'allergen-only contains match → auto-expanded danger row',
      (tester) async {
        await _pump(
          tester,
          matchedAllergens: [_allergen(presenceType: 'contains')],
          profile: const ProfileState(allergens: ['ALLERGEN_SOY']),
        );
        await tester.pumpAndSettle();
        expect(find.text('Review before use'), findsOneWidget);
        expect(find.text('Contains'), findsOneWidget);
        expect(find.text('Soy'), findsOneWidget);
        expect(
          find.text('Soy is listed in your allergy profile.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'allergen-only may_contain → caution row, collapsed',
      (tester) async {
        await _pump(
          tester,
          matchedAllergens: [
            _allergen(
              displayName: 'Tree nuts',
              presenceType: 'may_contain',
            ),
          ],
          profile: const ProfileState(allergens: ['ALLERGEN_TREE_NUTS']),
        );
        await tester.pumpAndSettle();
        // Header rendered; body hidden until tap.
        expect(find.text('Review before use'), findsOneWidget);
        expect(find.text('May contain'), findsNothing);
        await tester.tap(find.text('Review before use'));
        await tester.pumpAndSettle();
        expect(find.text('May contain'), findsOneWidget);
        expect(
          find.text(
              'This product includes a precautionary allergen statement.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'allergen-only manufactured_in_facility → info row, collapsed',
      (tester) async {
        await _pump(
          tester,
          matchedAllergens: [
            _allergen(
              displayName: 'Milk',
              presenceType: 'manufactured_in_facility',
            ),
          ],
          profile: const ProfileState(allergens: ['ALLERGEN_MILK']),
        );
        await tester.tap(find.text('Review before use'));
        await tester.pumpAndSettle();
        expect(find.text('Facility'), findsOneWidget);
        expect(find.text('May matter for highly sensitive users.'),
            findsOneWidget);
      },
    );

    testWidgets(
      'severe contains → severe badge appears',
      (tester) async {
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
        expect(find.text('severe'), findsOneWidget);
      },
    );

    testWidgets(
      'caution warning + contains allergen → tone bumps to danger (auto-expanded)',
      (tester) async {
        await _pump(
          tester,
          warnings: [_w(severity: Severity.caution, title: 'C-row')],
          matchedAllergens: [_allergen(presenceType: 'contains')],
          profile: const ProfileState(
            conditions: ['anything'],
            allergens: ['ALLERGEN_SOY'],
          ),
        );
        await tester.pumpAndSettle();
        // Both rows visible without tapping → confirms auto-expand on
        // danger tone driven by `contains` allergen.
        expect(find.text('Contains'), findsOneWidget);
        expect(find.text('C-row'), findsOneWidget);
        // Allergen row precedes warning row (top-to-bottom).
        final allergenRect = tester.getRect(find.text('Soy'));
        final warningRect = tester.getRect(find.text('C-row'));
        expect(allergenRect.top, lessThan(warningRect.top));
      },
    );
  });

  group('ReviewBeforeUseCard — count copy', () {
    testWidgets('singular 1 thing', (tester) async {
      await _pump(
        tester,
        warnings: [_w(severity: Severity.caution, title: 'X')],
        profile: const ProfileState(conditions: ['anything']),
      );
      expect(find.text('1 thing to review before use'), findsOneWidget);
    });

    testWidgets('plural 3 things (mix of warning + allergens)', (tester) async {
      await _pump(
        tester,
        warnings: [
          _w(severity: Severity.caution, title: 'C1'),
          _w(severity: Severity.monitor, title: 'M1'),
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
}
