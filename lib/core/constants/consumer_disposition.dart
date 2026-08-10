/// Consumer placement for a clinical signal.
///
/// This is deliberately independent from clinical severity: severity ranks
/// safety significance, while disposition decides where the signal appears.
enum ConsumerDisposition { block, review, goodToKnow, suppress }

extension ConsumerDispositionPolicy on ConsumerDisposition {
  /// Stable pipeline spelling for this disposition.
  String get wireValue => switch (this) {
    ConsumerDisposition.block => 'block',
    ConsumerDisposition.review => 'review',
    ConsumerDisposition.goodToKnow => 'good_to_know',
    ConsumerDisposition.suppress => 'suppress',
  };

  /// Higher values receive more prominent consumer placement.
  int get rank => switch (this) {
    ConsumerDisposition.block => 3,
    ConsumerDisposition.review => 2,
    ConsumerDisposition.goodToKnow => 1,
    ConsumerDisposition.suppress => 0,
  };

  bool get isVisible => this != ConsumerDisposition.suppress;

  /// Only block/review findings participate in the Stack Health safety gates.
  bool get requiresReview =>
      this == ConsumerDisposition.block || this == ConsumerDisposition.review;
}

/// Parses pipeline-authored placement without allowing schema drift to hide a
/// finding. Missing or unknown values fail visibly to [ConsumerDisposition.review].
ConsumerDisposition consumerDispositionFromWire(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'block' => ConsumerDisposition.block,
    'review' => ConsumerDisposition.review,
    'good_to_know' || 'goodtoknow' => ConsumerDisposition.goodToKnow,
    'suppress' => ConsumerDisposition.suppress,
    _ => ConsumerDisposition.review,
  };
}
