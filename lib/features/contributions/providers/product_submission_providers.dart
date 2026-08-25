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
///
/// An unfinished upload for a barcode that also has a COMPLETED submission
/// is an abandoned duplicate attempt (historically minted when the
/// duplicate check only fired at finalize). It is noise, not a task — its
/// "start a new submission" copy invited a retry that could only conflict —
/// so it is hidden here, where both the list and the badge count read from.
/// A standalone unfinished upload (a genuinely interrupted submission with
/// no completed sibling) still shows with its retry guidance.
final productSubmissionsProvider =
    FutureProvider.autoDispose<List<ProductSubmissionSummary>>((ref) async {
      final all = await ref
          .watch(productSubmissionServiceProvider)
          .listOwnSubmissions();
      final completedBarcodes = {
        for (final submission in all)
          if (submission.uploadReady && submission.upc != null)
            (submission.kind, submission.upc),
      };
      return [
        for (final submission in all)
          if (submission.uploadReady ||
              submission.upc == null ||
              !completedBarcodes.contains((submission.kind, submission.upc)))
            submission,
      ];
    });

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
