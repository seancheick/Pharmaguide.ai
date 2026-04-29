// Tests for RefillReminderCard — the v1.3.1 refill-timing widget.
//
// Uses net_contents_quantity + dosing_summary + servingsPerContainer +
// the user-stack addedAt to estimate days remaining and surface a status
// tier (out / refill-soon / almost-out / plenty).
//
// TDD: contract first, implementation after.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/refill_reminder_card.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

DateTime _daysAgo(int n) => DateTime.now().subtract(Duration(days: n));

void main() {
  group('RefillReminderCard.estimateDailyServings', () {
    test('defaults to 1 when dosingSummary is null', () {
      expect(RefillReminderCard.estimateDailyServings(null), 1);
    });

    test('defaults to 1 when dosingSummary is empty', () {
      expect(RefillReminderCard.estimateDailyServings(''), 1);
    });

    test('returns 1 for "Take 1 capsule daily"', () {
      expect(
        RefillReminderCard.estimateDailyServings('Take 1 capsule daily'),
        1,
      );
    });

    test('returns 2 for "Chew 2 gummies twice daily"', () {
      expect(
        RefillReminderCard.estimateDailyServings('Chew 2 gummies twice daily'),
        2,
      );
    });

    test('returns 3 for "Take 1 capsule three times daily"', () {
      expect(
        RefillReminderCard.estimateDailyServings(
          'Take 1 capsule three times daily',
        ),
        3,
      );
    });

    test('returns 4 for "Take 1 capsule four times daily"', () {
      expect(
        RefillReminderCard.estimateDailyServings(
          'Take 1 capsule four times daily',
        ),
        4,
      );
    });

    test('returns N for "Take 1 capsule 5 times daily"', () {
      expect(
        RefillReminderCard.estimateDailyServings(
          'Take 1 capsule 5 times daily',
        ),
        5,
      );
    });

    test('falls back to 1 when frequency phrase is unrecognized', () {
      expect(RefillReminderCard.estimateDailyServings('Take as needed'), 1);
    });
  });

  group('RefillReminderCard.estimateDaysRemaining', () {
    test('returns null when servingsPerContainer is null', () {
      final result = RefillReminderCard.estimateDaysRemaining(
        servingsPerContainer: null,
        dailyServings: 1,
        addedAt: _daysAgo(0),
      );
      expect(result, isNull);
    });

    test('full bottle 60 servings, 1/day, just added → 60 days', () {
      final result = RefillReminderCard.estimateDaysRemaining(
        servingsPerContainer: 60,
        dailyServings: 1,
        addedAt: _daysAgo(0),
      );
      expect(result, 60);
    });

    test('60 servings, 2/day, just added → 30 days', () {
      final result = RefillReminderCard.estimateDaysRemaining(
        servingsPerContainer: 60,
        dailyServings: 2,
        addedAt: _daysAgo(0),
      );
      expect(result, 30);
    });

    test('60 servings, 1/day, added 50 days ago → 10 days remaining', () {
      final result = RefillReminderCard.estimateDaysRemaining(
        servingsPerContainer: 60,
        dailyServings: 1,
        addedAt: _daysAgo(50),
      );
      expect(result, 10);
    });

    test(
      '60 servings, 1/day, added 90 days ago → 0 (clamped, not negative)',
      () {
        final result = RefillReminderCard.estimateDaysRemaining(
          servingsPerContainer: 60,
          dailyServings: 1,
          addedAt: _daysAgo(90),
        );
        expect(result, 0);
      },
    );

    test('handles future addedAt (clock issue) by clamping to full bottle', () {
      final result = RefillReminderCard.estimateDaysRemaining(
        servingsPerContainer: 30,
        dailyServings: 1,
        addedAt: DateTime.now().add(const Duration(days: 5)),
      );
      // Future date means daysSinceStart < 0; we clamp to 0, so full bottle.
      expect(result, 30);
    });
  });

  group('RefillReminderCard widget', () {
    testWidgets('renders nothing when servingsPerContainer is null', (
      tester,
    ) async {
      await _pump(
        tester,
        RefillReminderCard(
          servingsPerContainer: null,
          netContentsQuantity: null,
          netContentsUnit: null,
          dosingSummary: 'Take 1 capsule daily',
          addedAt: _daysAgo(0),
        ),
      );
      expect(find.byKey(const Key('refill-reminder-card')), findsNothing);
    });

    testWidgets('renders nothing when addedAt is null', (tester) async {
      await _pump(
        tester,
        const RefillReminderCard(
          servingsPerContainer: 60,
          netContentsQuantity: 60.0,
          netContentsUnit: 'Capsule(s)',
          dosingSummary: 'Take 1 capsule daily',
          addedAt: null,
        ),
      );
      expect(find.byKey(const Key('refill-reminder-card')), findsNothing);
    });

    testWidgets('renders "Plenty left" tier for >14 days', (tester) async {
      await _pump(
        tester,
        RefillReminderCard(
          servingsPerContainer: 60,
          netContentsQuantity: 60.0,
          netContentsUnit: 'Capsule(s)',
          dosingSummary: 'Take 1 capsule daily',
          addedAt: _daysAgo(0),
        ),
      );
      expect(find.byKey(const Key('refill-reminder-card')), findsOneWidget);
      expect(find.byKey(const Key('refill-tier-plenty')), findsOneWidget);
      expect(find.textContaining('60 days'), findsOneWidget);
    });

    testWidgets('renders "Almost out" tier for 8-14 days', (tester) async {
      await _pump(
        tester,
        RefillReminderCard(
          servingsPerContainer: 60,
          netContentsQuantity: 60.0,
          netContentsUnit: 'Capsule(s)',
          dosingSummary: 'Take 1 capsule daily',
          addedAt: _daysAgo(50), // 10 days remaining
        ),
      );
      expect(find.byKey(const Key('refill-tier-almost-out')), findsOneWidget);
      expect(find.textContaining('10 days'), findsOneWidget);
    });

    testWidgets('renders "Refill soon" tier for 1-7 days', (tester) async {
      await _pump(
        tester,
        RefillReminderCard(
          servingsPerContainer: 60,
          netContentsQuantity: 60.0,
          netContentsUnit: 'Capsule(s)',
          dosingSummary: 'Take 1 capsule daily',
          addedAt: _daysAgo(57), // 3 days remaining
        ),
      );
      expect(find.byKey(const Key('refill-tier-refill-soon')), findsOneWidget);
      expect(find.textContaining('3 days'), findsOneWidget);
    });

    testWidgets('renders "Out" tier for 0 days', (tester) async {
      await _pump(
        tester,
        RefillReminderCard(
          servingsPerContainer: 60,
          netContentsQuantity: 60.0,
          netContentsUnit: 'Capsule(s)',
          dosingSummary: 'Take 1 capsule daily',
          addedAt: _daysAgo(120),
        ),
      );
      expect(find.byKey(const Key('refill-tier-out')), findsOneWidget);
      expect(find.textContaining('Out'), findsOneWidget);
    });

    testWidgets('shows net contents in card subtitle when available', (
      tester,
    ) async {
      await _pump(
        tester,
        RefillReminderCard(
          servingsPerContainer: 60,
          netContentsQuantity: 60.0,
          netContentsUnit: 'Capsule(s)',
          dosingSummary: 'Take 1 capsule daily',
          addedAt: _daysAgo(0),
        ),
      );
      expect(find.textContaining('60 Capsule(s)'), findsOneWidget);
    });

    testWidgets('halves estimate when dosing is "twice daily"', (tester) async {
      await _pump(
        tester,
        RefillReminderCard(
          servingsPerContainer: 60,
          netContentsQuantity: 60.0,
          netContentsUnit: 'Capsule(s)',
          dosingSummary: 'Chew 2 gummies twice daily',
          addedAt: _daysAgo(0),
        ),
      );
      // 60 servings / 2 daily = 30 days
      expect(find.textContaining('30 days'), findsOneWidget);
    });
  });
}
