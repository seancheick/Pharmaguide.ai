import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/analytics_service.dart';
import 'package:pharmaguide/services/label_mismatch_report_service.dart';
import 'package:pharmaguide/services/label_trust_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AnalyticsService analytics;
  late LabelTrustAnalytics trust;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'settings.analyticsCollectionEnabled': false,
    });
    analytics = AnalyticsService()..resetForTest();
    await analytics.initialize();
    trust = LabelTrustAnalytics(analytics: analytics);
  });

  tearDown(() {
    analytics.resetForTest();
  });

  test('event names and exact property-key maps are closed', () {
    expect(LabelTrustAnalytics.eventPropertyKeys, const {
      'label_trust_source_open': <String>{},
      'label_trust_filter_use': {'state'},
      'label_trust_form_state': {'state', 'count'},
      'label_trust_review_state': {'state', 'count'},
      'label_trust_mismatch_outcome': {
        'state',
        'category_count',
        'photo_count',
        'count',
      },
      'label_trust_mismatch_category': {'category', 'count'},
    });
    expect(LabelTrustAnalytics.maxAggregateCount, 1000);
  });

  test('all state vocabularies use exact pipeline/report wire values', () {
    expect(LabelTrustFilter.values.map((value) => value.wireValue), const [
      'label',
      'analysis',
    ]);
    expect(LabelTrustFormState.values.map((value) => value.wireValue), const [
      'assessed',
      'not_disclosed',
      'listed_not_assessed',
      'not_applicable',
      'needs_review',
    ]);
    expect(LabelTrustReviewState.values.map((value) => value.wireValue), const [
      'needs_review',
      'identity_conflict',
      'missing_display_label',
      'unsupported_source_structure',
    ]);
    expect(
      LabelTrustMismatchOutcome.values.map((value) => value.wireValue),
      const [
        'submitted',
        'authentication_required',
        'photo_upload_failed',
        'report_insert_failed',
        'cancelled',
      ],
    );
    expect(LabelTrustAnalytics.mismatchCategoryWireValues, const {
      'product_identity',
      'ingredient_missing',
      'ingredient_extra',
      'amount_or_unit',
      'form_or_parenthetical',
      'serving_size_or_directions',
      'other_ingredients',
      'catalog_version_or_status',
    });
  });

  test('valid events remain consent-gated through AnalyticsService', () {
    trust.recordSourceLabelOpen();
    trust.recordFilterUse(LabelTrustFilter.analysis);
    trust.recordFormState(LabelTrustFormState.assessed, count: 4);
    trust.recordReviewState(LabelTrustReviewState.identityConflict, count: 2);
    trust.recordMismatchOutcome(
      LabelTrustMismatchOutcome.submitted,
      categoryCount: 2,
      photoCount: 1,
    );
    trust.recordMismatchCategory(LabelMismatchCategory.amountOrUnit);

    expect(analytics.collectionEnabled, isFalse);
    expect(analytics.bufferedEvents, isEmpty);
  });

  test('records exact event names, keys, and aggregate-only values', () async {
    await analytics.setCollectionEnabled(true);

    trust.recordSourceLabelOpen();
    trust.recordFilterUse(LabelTrustFilter.analysis);
    trust.recordFormState(LabelTrustFormState.listedNotAssessed, count: 4);
    trust.recordReviewState(
      LabelTrustReviewState.missingDisplayLabel,
      count: 2,
    );
    trust.recordMismatchOutcome(
      LabelTrustMismatchOutcome.photoUploadFailed,
      categoryCount: 3,
      photoCount: 2,
      count: 1,
    );
    trust.recordMismatchCategory(
      LabelMismatchCategory.formOrParenthetical,
      count: 2,
    );

    final events = analytics.bufferedEvents;
    expect(events.map((event) => event.name), const [
      'label_trust_source_open',
      'label_trust_filter_use',
      'label_trust_form_state',
      'label_trust_review_state',
      'label_trust_mismatch_outcome',
      'label_trust_mismatch_category',
    ]);
    expect(events[0].value, const <String, Object>{});
    expect(events[1].value, const <String, Object>{'state': 'analysis'});
    expect(events[2].value, const <String, Object>{
      'state': 'listed_not_assessed',
      'count': 4,
    });
    expect(events[3].value, const <String, Object>{
      'state': 'missing_display_label',
      'count': 2,
    });
    expect(events[4].value, const <String, Object>{
      'state': 'photo_upload_failed',
      'category_count': 3,
      'photo_count': 2,
      'count': 1,
    });
    expect(events[5].value, const <String, Object>{
      'category': 'form_or_parenthetical',
      'count': 2,
    });
  });

  test(
    'unknown event, missing/unknown key, and unknown value are rejected',
    () {
      expect(
        () => trust.recordEvent('label_trust_product_open', const {}),
        _violation(AnalyticsContractViolationReason.unknownEvent),
      );
      expect(
        () => trust.recordEvent(LabelTrustAnalytics.filterUseEvent, const {}),
        _violation(AnalyticsContractViolationReason.invalidPropertyKeys),
      );
      expect(
        () => trust.recordEvent(LabelTrustAnalytics.filterUseEvent, const {
          'state': 'analysis',
          'count': 1,
        }),
        _violation(AnalyticsContractViolationReason.invalidPropertyKeys),
      );
      expect(
        () => trust.recordEvent(LabelTrustAnalytics.filterUseEvent, const {
          'state': 'details',
        }),
        _violation(AnalyticsContractViolationReason.invalidPropertyValue),
      );
      expect(
        () => trust.recordEvent(
          LabelTrustAnalytics.mismatchCategoryEvent,
          const {'category': 'other', 'count': 1},
        ),
        _violation(AnalyticsContractViolationReason.invalidPropertyValue),
      );
    },
  );

  test('privacy-sensitive keys are rejected rather than redacted', () {
    const forbiddenKeys = [
      'upc',
      'dsld_id',
      'product_id',
      'product_name',
      'raw_label_text',
      'label_text',
      'photo_path',
      'photo_bytes',
      'free_text',
      'profile',
      'profile_id',
      'medication',
      'medications',
      'condition',
      'conditions',
      'allergy',
      'allergies',
      'stack',
      'health',
      'health_data',
    ];

    for (final key in forbiddenKeys) {
      expect(
        () => trust.recordEvent(LabelTrustAnalytics.mismatchCategoryEvent, {
          'category': 'amount_or_unit',
          'count': 1,
          key: 'private',
        }),
        _violation(AnalyticsContractViolationReason.invalidPropertyKeys),
        reason: '$key must not be silently removed',
      );
    }
  });

  test(
    'identifiers, label/photo/free text, and health values are rejected',
    () {
      final forbiddenValues = <Object>[
        '031604010206',
        'DSLD-12345',
        'Nature Made Fish Oil',
        'Folate 665 mcg DFE (400 mcg folic acid)',
        'user/report/front.jpg',
        'please fix this label',
        'pregnancy',
        'profile',
        'medication',
        'condition',
        'allergy',
        'stack',
        'health',
        Uint8List.fromList([1, 2, 3]),
      ];

      for (final value in forbiddenValues) {
        expect(
          () => trust.recordEvent(LabelTrustAnalytics.filterUseEvent, {
            'state': value,
          }),
          _violation(AnalyticsContractViolationReason.invalidPropertyValue),
        );
      }
    },
  );

  test('counts are integer, bounded, and nonnegative', () {
    for (final value in <Object>[-1, 1001, 1.5, '1', 031604010206]) {
      expect(
        () => trust.recordEvent(LabelTrustAnalytics.formStateEvent, {
          'state': 'assessed',
          'count': value,
        }),
        _violation(AnalyticsContractViolationReason.invalidPropertyValue),
      );
    }

    expect(
      () => trust.recordEvent(LabelTrustAnalytics.mismatchOutcomeEvent, const {
        'state': 'cancelled',
        'category_count': 0,
        'photo_count': 0,
        'count': 1,
      }),
      returnsNormally,
    );

    for (final categoryCount in [9]) {
      expect(
        () => trust.recordEvent(LabelTrustAnalytics.mismatchOutcomeEvent, {
          'state': 'submitted',
          'category_count': categoryCount,
          'photo_count': 0,
          'count': 1,
        }),
        _violation(AnalyticsContractViolationReason.invalidPropertyValue),
      );
    }
    for (final photoCount in [-1, 4]) {
      expect(
        () => trust.recordEvent(LabelTrustAnalytics.mismatchOutcomeEvent, {
          'state': 'submitted',
          'category_count': 1,
          'photo_count': photoCount,
          'count': 1,
        }),
        _violation(AnalyticsContractViolationReason.invalidPropertyValue),
      );
    }
  });

  test('strict validation runs before the disabled-consent no-op', () {
    expect(analytics.collectionEnabled, isFalse);

    expect(
      () => trust.recordEvent(LabelTrustAnalytics.filterUseEvent, const {
        'state': '031604010206',
      }),
      _violation(AnalyticsContractViolationReason.invalidPropertyValue),
    );
    expect(analytics.bufferedEvents, isEmpty);
  });

  test(
    'legacy AnalyticsService sanitization behavior remains unchanged',
    () async {
      await analytics.setCollectionEnabled(true);

      analytics.trackEvent('legacy_event', const {
        'conditions': 'must be dropped',
        'safe_count': 2,
      });

      expect(analytics.bufferedEvents.single.name, 'legacy_event');
      expect(analytics.bufferedEvents.single.value, const {'safe_count': 2});
    },
  );

  test(
    'validated event properties cannot be mutated after buffering',
    () async {
      await analytics.setCollectionEnabled(true);
      trust.recordMismatchCategory(LabelMismatchCategory.ingredientMissing);

      final value = analytics.bufferedEvents.single.value! as Map;

      expect(() => value['upc'] = '031604010206', throwsUnsupportedError);
      expect(value, const {'category': 'ingredient_missing', 'count': 1});
    },
  );

  test('local event buffer keeps only the newest 200 events', () async {
    await analytics.setCollectionEnabled(true);

    for (var index = 0; index <= 200; index++) {
      analytics.trackEvent('event_$index', {'count': index});
    }

    expect(analytics.bufferedEvents, hasLength(200));
    expect(analytics.bufferedEvents.first.name, 'event_1');
    expect(analytics.bufferedEvents.last.name, 'event_200');
  });
}

Matcher _violation(AnalyticsContractViolationReason reason) {
  return throwsA(
    isA<AnalyticsContractViolation>().having(
      (error) => error.reason,
      'reason',
      reason,
    ),
  );
}
