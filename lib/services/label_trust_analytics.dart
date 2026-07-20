import 'package:pharmaguide/services/analytics_service.dart';
import 'package:pharmaguide/services/label_mismatch_report_service.dart';

enum LabelTrustFilter {
  label('label'),
  analysis('analysis');

  final String wireValue;
  const LabelTrustFilter(this.wireValue);
}

enum LabelTrustFormState {
  assessed('assessed'),
  notDisclosed('not_disclosed'),
  listedNotAssessed('listed_not_assessed'),
  notApplicable('not_applicable'),
  needsReview('needs_review');

  final String wireValue;
  const LabelTrustFormState(this.wireValue);
}

enum LabelTrustReviewState {
  needsReview('needs_review'),
  identityConflict('identity_conflict'),
  missingDisplayLabel('missing_display_label'),
  unsupportedSourceStructure('unsupported_source_structure');

  final String wireValue;
  const LabelTrustReviewState(this.wireValue);
}

enum LabelTrustMismatchOutcome {
  submitted('submitted'),
  authenticationRequired('authentication_required'),
  photoUploadFailed('photo_upload_failed'),
  reportInsertFailed('report_insert_failed'),
  cancelled('cancelled');

  final String wireValue;
  const LabelTrustMismatchOutcome(this.wireValue);
}

/// Privacy-allowlisted, aggregate-only telemetry for the label-trust surfaces.
///
/// There is intentionally no product context parameter. Product identifiers,
/// label strings, photo data, free text, and profile/health state cannot be
/// represented by the typed methods. [recordEvent] remains fail-closed for any
/// future adapter that starts from an untyped event map.
class LabelTrustAnalytics {
  static const sourceOpenEvent = 'label_trust_source_open';
  static const filterUseEvent = 'label_trust_filter_use';
  static const formStateEvent = 'label_trust_form_state';
  static const reviewStateEvent = 'label_trust_review_state';
  static const mismatchOutcomeEvent = 'label_trust_mismatch_outcome';
  static const mismatchCategoryEvent = 'label_trust_mismatch_category';

  static const maxAggregateCount = 1000;
  static const mismatchCategoryWireValues = <String>{
    'product_identity',
    'ingredient_missing',
    'ingredient_extra',
    'amount_or_unit',
    'form_or_parenthetical',
    'serving_size_or_directions',
    'other_ingredients',
    'catalog_version_or_status',
  };

  static const eventPropertyKeys = <String, Set<String>>{
    sourceOpenEvent: <String>{},
    filterUseEvent: {'state'},
    formStateEvent: {'state', 'count'},
    reviewStateEvent: {'state', 'count'},
    mismatchOutcomeEvent: {'state', 'category_count', 'photo_count', 'count'},
    mismatchCategoryEvent: {'category', 'count'},
  };

  final AnalyticsService _analytics;

  LabelTrustAnalytics({AnalyticsService? analytics})
    : _analytics = analytics ?? AnalyticsService();

  void recordSourceLabelOpen() {
    recordEvent(sourceOpenEvent, const {});
  }

  void recordFilterUse(LabelTrustFilter filter) {
    recordEvent(filterUseEvent, {'state': filter.wireValue});
  }

  void recordFormState(LabelTrustFormState state, {int count = 1}) {
    recordEvent(formStateEvent, {'state': state.wireValue, 'count': count});
  }

  void recordReviewState(LabelTrustReviewState state, {int count = 1}) {
    recordEvent(reviewStateEvent, {'state': state.wireValue, 'count': count});
  }

  void recordMismatchOutcome(
    LabelTrustMismatchOutcome outcome, {
    required int categoryCount,
    required int photoCount,
    int count = 1,
  }) {
    recordEvent(mismatchOutcomeEvent, {
      'state': outcome.wireValue,
      'category_count': categoryCount,
      'photo_count': photoCount,
      'count': count,
    });
  }

  void recordMismatchCategory(LabelMismatchCategory category, {int count = 1}) {
    recordEvent(mismatchCategoryEvent, {
      'category': category.wireValue,
      'count': count,
    });
  }

  /// Strict raw boundary used by adapters and tests.
  ///
  /// Exact names, exact key sets, closed string values, and bounded integer
  /// counts are checked before [AnalyticsService] evaluates consent.
  void recordEvent(String eventName, Map<String, Object> properties) {
    _analytics.trackAllowlistedEvent(
      name: eventName,
      properties: properties,
      eventPropertyKeys: eventPropertyKeys,
      isAllowedValue: _isAllowedValue,
    );
  }

  static bool _isAllowedValue(
    String eventName,
    String propertyName,
    Object value,
  ) {
    return switch (eventName) {
      sourceOpenEvent => false,
      filterUseEvent =>
        propertyName == 'state' &&
            _containsWireValue(
              LabelTrustFilter.values,
              value,
              (candidate) => candidate.wireValue,
            ),
      formStateEvent => switch (propertyName) {
        'state' => _containsWireValue(
          LabelTrustFormState.values,
          value,
          (candidate) => candidate.wireValue,
        ),
        'count' => _isAggregateCount(value),
        _ => false,
      },
      reviewStateEvent => switch (propertyName) {
        'state' => _containsWireValue(
          LabelTrustReviewState.values,
          value,
          (candidate) => candidate.wireValue,
        ),
        'count' => _isAggregateCount(value),
        _ => false,
      },
      mismatchOutcomeEvent => switch (propertyName) {
        'state' => _containsWireValue(
          LabelTrustMismatchOutcome.values,
          value,
          (candidate) => candidate.wireValue,
        ),
        'category_count' =>
          value is int &&
              value >= 0 &&
              value <= mismatchCategoryWireValues.length,
        'photo_count' => value is int && value >= 0 && value <= 3,
        'count' => _isAggregateCount(value),
        _ => false,
      },
      mismatchCategoryEvent => switch (propertyName) {
        'category' =>
          value is String && mismatchCategoryWireValues.contains(value),
        'count' => _isAggregateCount(value),
        _ => false,
      },
      _ => false,
    };
  }

  static bool _containsWireValue<T>(
    Iterable<T> values,
    Object value,
    String Function(T candidate) readWireValue,
  ) {
    if (value is! String) return false;
    return values.any((candidate) => readWireValue(candidate) == value);
  }

  static bool _isAggregateCount(Object value) {
    return value is int && value >= 0 && value <= maxAggregateCount;
  }
}
