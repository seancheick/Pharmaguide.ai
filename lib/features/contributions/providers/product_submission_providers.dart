import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

/// One overridable construction point so widgets and push handlers share a
/// single service instance (tests override this with a fake backend).
final productSubmissionServiceProvider = Provider<ProductSubmissionService>(
  (ref) => ProductSubmissionService.production(),
);

/// The signed-in user's own submissions, newest first (RLS-scoped
/// server-side). Invalidated by pull-to-refresh, app resume on the status
/// surface, and incoming `submission_update` pushes.
final productSubmissionsProvider =
    FutureProvider.autoDispose<List<ProductSubmissionSummary>>(
      (ref) => ref.watch(productSubmissionServiceProvider).listOwnSubmissions(),
    );

/// Count shown as the Settings-row badge: submissions still awaiting an
/// outcome.
final pendingSubmissionCountProvider = Provider.autoDispose<int>((ref) {
  final submissions =
      ref.watch(productSubmissionsProvider).value ??
      const <ProductSubmissionSummary>[];
  return submissions
      .where(
        (ProductSubmissionSummary submission) =>
            submission.reviewStatus ==
                ProductSubmissionReviewStatus.submitted ||
            submission.reviewStatus ==
                ProductSubmissionReviewStatus.underReview,
      )
      .length;
});
