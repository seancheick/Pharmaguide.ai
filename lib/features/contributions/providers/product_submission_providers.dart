import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/services/product_submission_draft_store.dart';
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
/// An unfinished upload for a barcode that also has an open, reviewable
/// submission is an abandoned duplicate attempt (historically minted when
/// the duplicate check only fired at finalize). It is noise, not a task —
/// its retry would still conflict — so it is hidden here, where both the
/// list and the badge count read from. A rejected sibling does not hide a
/// genuinely interrupted retry. An approved sibling keeps hiding historical
/// shells after promotion because the accepted product already owns that UPC.
final productSubmissionsProvider =
    FutureProvider.autoDispose<List<ProductSubmissionSummary>>((ref) async {
      final all = await ref
          .watch(productSubmissionServiceProvider)
          .listOwnSubmissions();
      final openBarcodes = {
        for (final submission in all)
          if (submission.uploadReady &&
              submission.kind != null &&
              submission.canonicalGtin14 != null &&
              (submission.reviewStatus ==
                      ProductSubmissionReviewStatus.submitted ||
                  submission.reviewStatus ==
                      ProductSubmissionReviewStatus.underReview ||
                  submission.reviewStatus ==
                      ProductSubmissionReviewStatus.approved))
            (submission.kind, submission.canonicalGtin14),
      };
      return [
        for (final submission in all)
          if (submission.dismissedAt == null &&
              (submission.uploadReady ||
                  submission.kind == null ||
                  submission.canonicalGtin14 == null ||
                  !openBarcodes.contains((
                    submission.kind,
                    submission.canonicalGtin14,
                  ))))
            submission,
      ];
    });

/// Display-only impact score derived from catalog outcomes: 10 points for
/// each contribution that has shipped in the catalog.
///
/// Deliberately NOT a stored ledger — derived means no backend, no drift,
/// and transparent math. The hard rule: before points become redeemable
/// for anything, this must convert to an append-only server ledger,
/// because a derived formula can retroactively re-price history.
int contributionPoints(List<ProductSubmissionSummary> submissions) {
  return submissions.where((submission) => submission.isComplete).length * 10;
}

/// Count shown as the Settings-row badge: submissions still awaiting an
/// outcome.
final pendingSubmissionCountProvider = Provider.autoDispose<int>((ref) {
  final submissions =
      ref.watch(productSubmissionsProvider).value ??
      const <ProductSubmissionSummary>[];
  return submissions
      .where(
        (ProductSubmissionSummary submission) =>
            submission.uploadReady &&
            (submission.reviewStatus ==
                    ProductSubmissionReviewStatus.submitted ||
                submission.reviewStatus ==
                    ProductSubmissionReviewStatus.underReview),
      )
      .length;
});


/// Where unfinished captures are kept. Overridden in tests with an in-memory
/// implementation so no widget pump waits on the file system.
final productSubmissionDraftStorageProvider =
    FutureProvider<ProductSubmissionDraftStorage?>((ref) async {
      try {
        return await ProductSubmissionDraftStore.open();
      } on Object {
        // A device without usable private storage still submits; it just
        // cannot recover an interrupted capture.
        return null;
      }
    });

/// Captures this device holds that were never accepted by the server.
///
/// These are the only submissions the user can act on without the network, and
/// without this list the sole route back to them is rescanning the same
/// barcode — which a user who force-quit mid-upload has no reason to guess.
final pendingProductSubmissionDraftsProvider =
    FutureProvider.autoDispose<List<PendingProductSubmission>>((ref) async {
      final storage = await ref.watch(
        productSubmissionDraftStorageProvider.future,
      );
      if (storage == null) return const [];
      try {
        return await storage.list();
      } on Object {
        return const [];
      }
    });
