import 'dart:async';
import 'dart:math' as math;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/features/contributions/product_submission_consent_copy.dart';
import 'package:pharmaguide/features/contributions/product_submission_resolution_copy.dart';
import 'package:pharmaguide/features/scanner/submission_panel_example.dart';
import 'package:pharmaguide/services/gtin.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/photo_panel_hints.dart';
import 'package:pharmaguide/services/photo_quality_gate.dart';
import 'package:pharmaguide/services/product_submission_draft_store.dart';
import 'package:pharmaguide/services/product_submission_photo_service.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

typedef PickMissingProductPhoto =
    Future<ProductSubmissionPhoto?> Function(
      Set<ProductSubmissionEvidenceCategory> categories,
    );

typedef EvaluatePhotoQuality =
    Future<PhotoQualityResult> Function(ProductSubmissionPhoto photo);

/// Several library photos at once, at most [limit]; `unreadable` counts the
/// files that could not be prepared.
typedef PickMissingProductPhotos =
    Future<({List<ProductSubmissionPhoto> photos, int unreadable})> Function(
      int limit,
    );

/// Opens the one production intake flow used by camera and manual barcode
/// misses. Authentication remains a caller decision so the helper never
/// guesses whether to redirect or silently drop a submission attempt.
///
/// Capture is camera-first: Start opens the system camera for the first
/// panel (its native confirm is the per-shot confirm), each passing shot
/// moves on by itself, and every step offers the photo library second.
Future<bool> showMissingProductSubmissionSheet(
  BuildContext context, {
  required String upc,
  bool preferLibrary = false,
  ProductSubmissionService? service,
  PickMissingProductPhoto? pickPhoto,
  PickMissingProductPhoto? pickPhotoFromLibrary,
  EvaluatePhotoQuality? qualityGate,
  String Function()? submissionIdFactory,
  String? resubmissionOf,
  ProductSubmissionRetake? retake,
  ReadSubmissionPhotoText? readPhotoText,
  PickMissingProductPhotos? pickPhotosFromLibrary,
}) async {
  late final GtinIdentity identity;
  try {
    identity = GtinIdentity.parse(upc);
  } on FormatException {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(invalidGtinMessage)));
    return false;
  }
  final picker = ImagePicker();
  final submitted = await PGModal.bottomSheet<bool>(
    context: context,
    builder: (sheetContext) => MissingProductSubmissionSheet(
      upc: identity.submissionIdentity,
      preferLibrary: preferLibrary,
      service: service ?? ProductSubmissionService.production(),
      submissionIdFactory: submissionIdFactory,
      resubmissionOf: resubmissionOf,
      retake: retake,
      onViewContributions: () {
        Navigator.of(sheetContext).pop(false);
        context.push(Routes.productSubmissions);
      },
      qualityGate:
          qualityGate ?? (photo) => PhotoQualityGate.evaluate(photo.bytes),
      readPhotoText: readPhotoText ?? readSubmissionPhotoText,
      pickPhotosFromLibrary:
          pickPhotosFromLibrary ??
          (limit) => pickProductSubmissionPhotos(picker: picker, limit: limit),
      pickPhoto:
          pickPhoto ??
          (categories) => pickProductSubmissionPhoto(
            picker: picker,
            categories: categories,
            source: ImageSource.camera,
          ),
      pickPhotoFromLibrary:
          pickPhotoFromLibrary ??
          (categories) => pickProductSubmissionPhoto(
            picker: picker,
            categories: categories,
            source: ImageSource.gallery,
          ),
    ),
  );
  return submitted == true;
}

/// One guided capture step. `categories` is what a photo taken on this step
/// is tagged with; the ingredients step disappears when the facts capture
/// already carries the ingredient list (asked as a one-tap question right
/// under the facts photo — never a checkbox that could invalidate work).
/// Optional panels (directions, lot) are offered on review, not as a step
/// every contributor has to pass through.
enum _CaptureStep { intro, front, facts, ingredients, barcode, review }

/// The answers to a question about what a photo shows.
enum _HintChoice { keep, retake, move }

/// A photo source the OS will not open for us until the user changes a
/// setting. Retrying cannot help, so capture says how to fix it instead.
enum _BlockedSource { camera, photos }

/// image_picker's error codes for a permission the user turned off (or that
/// is restricted on this device), on both iOS and Android.
_BlockedSource? _blockedSourceFor(String code) => switch (code) {
  'camera_access_denied' || 'camera_access_restricted' => _BlockedSource.camera,
  'photo_access_denied' || 'photo_access_restricted' => _BlockedSource.photos,
  _ => null,
};

/// Private, structured evidence intake for a barcode the catalog cannot
/// match. There is deliberately no narrative field: the photos, barcode, and
/// one closed "no separate ingredient panel" assertion are the entire user
/// payload.
class MissingProductSubmissionSheet extends StatefulWidget {
  const MissingProductSubmissionSheet({
    super.key,
    required this.upc,
    required this.service,
    required this.pickPhoto,
    required this.qualityGate,
    this.preferLibrary = false,
    this.pickPhotoFromLibrary,
    this.submissionIdFactory,
    this.resubmissionOf,
    this.retake,
    this.onViewContributions,
    this.draftStore,
    this.readPhotoText,
    this.pickPhotosFromLibrary,
  });

  final String upc;
  final ProductSubmissionService service;
  final bool preferLibrary;
  final PickMissingProductPhoto pickPhoto;
  final PickMissingProductPhoto? pickPhotoFromLibrary;
  final EvaluatePhotoQuality qualityGate;
  final String Function()? submissionIdFactory;
  final String? resubmissionOf;

  /// A reviewer asked for new photos of this existing submission. The same
  /// capture runs, but the photos being kept already count as taken, so it
  /// only asks for the panels that are missing.
  final ProductSubmissionRetake? retake;
  final VoidCallback? onViewContributions;

  /// Where an unfinished capture is kept so a crash, the OS reclaiming the app
  /// behind the camera, or a dead connection does not discard the user's
  /// photos. Injected in tests; resolved from app-private storage otherwise.
  final ProductSubmissionDraftStorage? draftStore;

  /// Reads each photo's printed text on the phone so capture can say "that
  /// looks like the directions" or "the barcode is in this one". Null turns
  /// the suggestions off; they never block a photo either way.
  final ReadSubmissionPhotoText? readPhotoText;

  /// Starting from the library picks several photos in one go and sorts
  /// them by panel. Null keeps the one-photo-per-panel library path.
  final PickMissingProductPhotos? pickPhotosFromLibrary;

  @override
  State<MissingProductSubmissionSheet> createState() =>
      _MissingProductSubmissionSheetState();
}

class _MissingProductSubmissionSheetState
    extends State<MissingProductSubmissionSheet> {
  final List<ProductSubmissionPhoto> _photos = [];
  _CaptureStep _step = _CaptureStep.intro;
  bool _factsCarriesIngredients = false;
  bool _factsPanelLocationConfirmed = false;
  bool _consent = false;
  bool _submitting = false;
  bool _submitted = false;
  bool _adding = false;
  bool _checkingIntake = false;
  bool _intakeCheckFailed = false;
  bool _intakeCheckBypassed = false;
  bool _captureFromLibrary = false;

  /// Which start button was pressed, so retrying a failed history check
  /// keeps the user's choice of camera or library.
  bool _startFromLibrary = false;

  /// A photo came back and is being checked (size, blur, printed text).
  /// Takes a second or two; the primary button says so instead of going
  /// quietly grey.
  bool _processing = false;
  String? _chosenResubmissionOf;
  String? _stepError;

  /// Sources the OS refused this session. Remembered, so capture never
  /// falls back onto a source it already knows is off; one leaves the set
  /// as soon as it opens again (after a trip to Settings).
  final Set<_BlockedSource> _blockedSources = {};

  /// Whether the blocked-source card is raised for the latest attempt.
  bool _showBlockedCard = false;

  /// A neutral note about what the last photo covered ("the barcode is in
  /// this one"). Survives an automatic advance so the user sees it.
  String? _stepNotice;

  /// "Front photo saved." — the confirmation a shot gets when capture moves
  /// straight on to the next panel, so the step change reads as success.
  String? _savedNote;

  /// Which optional panel is being added, so only its row shows progress.
  ProductSubmissionEvidenceCategory? _addingOptional;
  ProductSubmissionPhase? _phase;
  ProductSubmissionFailure? _failure;
  MissingProductSubmissionDraft? _draft;

  /// One downsized decode per photo. `photo.bytes` is a fresh copy on every
  /// read, so building `Image.memory(photo.bytes)` made a new cache key —
  /// and a new full-size decode — on every rebuild of the sheet.
  final Map<String, ImageProvider> _thumbnails = {};

  ImageProvider _thumbnailFor(ProductSubmissionPhoto photo) =>
      _thumbnails.putIfAbsent(
        photo.photoId,
        () => ResizeImage(MemoryImage(photo.bytes), width: 360),
      );

  @override
  void initState() {
    super.initState();
    _chosenResubmissionOf = widget.resubmissionOf;
    // A retake's submission already exists; there is no earlier attempt to
    // look up.
    _intakeCheckBypassed = widget.retake != null;
    // Opening app-private storage crosses a platform channel. Resolve it off
    // the capture path and offer recovery when it lands, so no step transition
    // ever waits on the file system.
    final injected = widget.draftStore;
    if (injected != null) {
      _store = injected;
      WidgetsBinding.instance.addPostFrameCallback((_) => _offerRecovery());
    } else {
      ProductSubmissionDraftStore.open()
          .then((store) {
            if (!mounted) return;
            _store = store;
            _offerRecovery();
          })
          .catchError((Object _) {
            // No durable storage: capture still works, recovery does not.
          });
    }
  }

  ProductSubmissionDraftStorage? _store;

  /// Minted once, before any photo is stored, so every save and the eventual
  /// submit describe the same contribution. Recovering a saved capture adopts
  /// that capture's id instead: submitting under a fresh one would open a
  /// second contribution for photos the server may already have seen.
  late String _draftSubmissionId =
      widget.retake?.submissionId ??
      widget.submissionIdFactory?.call() ??
      newProductSubmissionId();

  /// Photos a retake keeps occupy slots of the eight-photo limit.
  int get _photoCapacity =>
      widget.retake?.newPhotoCapacity ??
      ProductSubmissionPhoto.maxPerSubmission;

  /// Same bytes as a photo already sent (a retake's earlier photos too).
  bool _alreadySent(ProductSubmissionPhoto photo) =>
      _photos.any((p) => p.contentSha256 == photo.contentSha256) ||
      (widget.retake?.earlierPhotoDigests.contains(photo.contentSha256) ??
          false);

  /// Taken now, or kept from the photos a reviewer already has.
  bool _covered(ProductSubmissionEvidenceCategory category) =>
      _photosTagged(category).isNotEmpty ||
      (widget.retake?.keptCategories.contains(category) ?? false);

  /// Whether the ingredient list shares the facts panel only decides what to
  /// photograph when neither of the two is already kept.
  bool get _factsPanelLocationSettled =>
      _factsPanelLocationConfirmed ||
      (widget.retake?.keptCategories.any(
            (category) =>
                category == ProductSubmissionEvidenceCategory.supplementFacts ||
                category ==
                    ProductSubmissionEvidenceCategory.ingredientDisclosure,
          ) ??
          false);

  List<_CaptureStep> get _visibleSteps => [
    _CaptureStep.intro,
    _CaptureStep.front,
    _CaptureStep.facts,
    if (!_factsCarriesIngredients) _CaptureStep.ingredients,
    _CaptureStep.barcode,
    _CaptureStep.review,
  ];

  List<ProductSubmissionPhoto> _photosTagged(
    ProductSubmissionEvidenceCategory category,
  ) => [
    for (final photo in _photos)
      if (photo.categories.contains(category)) photo,
  ];

  Set<ProductSubmissionEvidenceCategory> _stepCategories(_CaptureStep step) =>
      switch (step) {
        _CaptureStep.front => const {
          ProductSubmissionEvidenceCategory.frontIdentity,
        },
        _CaptureStep.facts =>
          _factsCarriesIngredients
              ? const {
                  ProductSubmissionEvidenceCategory.supplementFacts,
                  ProductSubmissionEvidenceCategory.ingredientDisclosure,
                }
              : const {ProductSubmissionEvidenceCategory.supplementFacts},
        _CaptureStep.ingredients => const {
          ProductSubmissionEvidenceCategory.ingredientDisclosure,
        },
        _CaptureStep.barcode => const {
          ProductSubmissionEvidenceCategory.barcode,
        },
        _CaptureStep.intro ||
        _CaptureStep.review => const <ProductSubmissionEvidenceCategory>{},
      };

  bool _satisfies(_CaptureStep step) => switch (step) {
    _CaptureStep.front => _covered(
      ProductSubmissionEvidenceCategory.frontIdentity,
    ),
    _CaptureStep.facts => _covered(
      ProductSubmissionEvidenceCategory.supplementFacts,
    ),
    _CaptureStep.ingredients => _covered(
      ProductSubmissionEvidenceCategory.ingredientDisclosure,
    ),
    _CaptureStep.barcode => _covered(ProductSubmissionEvidenceCategory.barcode),
    _CaptureStep.intro || _CaptureStep.review => true,
  };

  bool get _stepSatisfied => _satisfies(_step);

  /// A required panel already covered — by its own photo, a reused one, or
  /// one whose printed text showed it — is not asked for again. Facts also
  /// needs its one question answered (is the ingredient list on it?), so it
  /// is only passed over once that is settled.
  bool _alreadyCovered(_CaptureStep step) => switch (step) {
    _CaptureStep.front ||
    _CaptureStep.ingredients ||
    _CaptureStep.barcode => _satisfies(step),
    _CaptureStep.facts => _satisfies(step) && _factsPanelLocationSettled,
    _CaptureStep.intro || _CaptureStep.review => false,
  };

  /// The earliest capture step this set does not yet satisfy, or review when
  /// every required panel is present.
  _CaptureStep _firstUnsatisfiedStep() {
    for (final step in _visibleSteps) {
      if (step == _CaptureStep.intro) continue;
      if (!_satisfies(step)) return step;
    }
    return _CaptureStep.review;
  }

  bool get _canSubmit => _consent && !_submitting && _coverageComplete;

  bool get _coverageComplete =>
      _photos.isNotEmpty &&
      MissingProductSubmissionDraft.requiredCategories.every(_covered);

  /// Camera-first capture. Simple required steps advance after a passing
  /// shot. Facts deliberately stays open so a wrapped panel can receive
  /// more than one angle before the user continues.
  Future<void> _addPhoto(
    Set<ProductSubmissionEvidenceCategory> categories, {
    bool fromLibrary = false,
    bool autoAdvance = false,
  }) async {
    if (_submitting || _adding) return;
    if (_photos.length >= _photoCapacity) {
      setState(
        () => _stepError =
            'Up to ${ProductSubmissionPhoto.maxPerSubmission} photos per '
            'submission. Remove one to add another.',
      );
      return;
    }
    final pick = fromLibrary
        ? (widget.pickPhotoFromLibrary ?? widget.pickPhoto)
        : widget.pickPhoto;
    final capturedStep = _step;
    setState(() {
      _adding = true;
      _stepError = null;
      _stepNotice = null;
      _savedNote = null;
      _failure = null;
      _showBlockedCard = false;
    });
    try {
      final photo = await pick(categories);
      if (!mounted || photo == null) return;
      // A photo came back, so this source is open (again).
      _blockedSources.remove(
        fromLibrary ? _BlockedSource.photos : _BlockedSource.camera,
      );
      setState(() => _processing = true);
      if (_alreadySent(photo)) {
        setState(
          () => _stepError = 'That exact photo is already in this submission.',
        );
        return;
      }

      final quality = await widget.qualityGate(photo);
      if (!mounted) return;
      if (quality.isHardBlock) {
        setState(
          () => _stepError =
              'That photo is too small to read the label. Move closer and '
              'retake it.',
        );
        return;
      }
      if (quality.isSoftWarning) {
        // Waiting on the user's answer, not on the phone: no "checking".
        setState(() => _processing = false);
        final useAnyway = await _confirmBlurryPhoto();
        if (!mounted || !useAnyway) return;
        setState(() => _processing = true);
      }

      final hints = await _readHints(photo);
      if (!mounted) return;
      // Placement may ask the user about the photo; checking is done.
      setState(() => _processing = false);
      final placed = await _placeByHints(photo, hints);
      if (!mounted || placed == null) return;

      setState(() {
        _photos.add(placed.photo);
        _draft = null;
        _stepNotice = placed.notice;
      });
      // The photo itself answers "is the ingredient list on this panel?".
      // The answer stays correctable on the review step.
      if (!_factsPanelLocationConfirmed &&
          placed.photo.categories.contains(
            ProductSubmissionEvidenceCategory.supplementFacts,
          )) {
        if (hints.showsOtherIngredients) {
          _setFactsCoversIngredients(true, reason: 'ocr_found_oi');
        } else if (hints.showsFactsPanel) {
          // The panel itself was legible enough to detect, and no "Other
          // Ingredients" heading turned up on it. Most supplements have no
          // separate list at all — treating a miss as that common case,
          // not as a question, is the fix. A genuinely cropped or
          // wraparound photo still reaches a human reviewer with the
          // image in hand, who can ask for another photo; it never
          // reaches the catalog on this assumption alone.
          _setFactsCoversIngredients(
            true,
            reason: 'facts_no_oi_assumed_absent',
          );
        }
      }
      // Persist as the set grows: an abandoned capture is recoverable from the
      // first shot, not only once it is complete.
      await _persistCapture();
      if (!mounted) return;
      // A shot moved to another panel leaves this one still unanswered.
      if (autoAdvance && !placed.moved) {
        // The panel this shot was for scrolls away with the advance; say it
        // landed so the next screen reads as progress, not a reset.
        setState(() => _savedNote = '${_panelName(capturedStep)} photo saved.');
        await _goForward(keepNotice: true);
      }
    } on ProductSubmissionValidationException {
      if (!mounted) return;
      setState(
        () => _stepError =
            'That photo could not be prepared. Choose a clear JPG, PNG, '
            'HEIC, or WebP image under 15 MB.',
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      final blocked = _blockedSourceFor(error.code);
      setState(() {
        if (blocked != null) {
          _raiseBlocked(blocked);
        } else if (error.code == 'no_available_camera') {
          _captureFromLibrary = true;
          _stepError =
              'No camera is available here. Choose a photo from your '
              'library instead.';
        } else {
          _stepError = 'We couldn’t open that photo. Try again.';
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() => _stepError = 'We couldn’t open that photo. Try again.');
    } finally {
      if (mounted) {
        setState(() {
          _adding = false;
          _processing = false;
        });
      }
    }
  }

  /// Records a refused source, raises the card, and moves the primary
  /// button to a source that still works — never back onto one this session
  /// already knows is off. (Call inside setState.)
  void _raiseBlocked(_BlockedSource blocked) {
    _blockedSources.add(blocked);
    _showBlockedCard = true;
    final cameraOff = _blockedSources.contains(_BlockedSource.camera);
    final photosOff = _blockedSources.contains(_BlockedSource.photos);
    if (cameraOff != photosOff) _captureFromLibrary = cameraOff;
  }

  Future<void> _openSystemSettings() async {
    try {
      await AppSettings.openAppSettings();
    } on Object {
      // No settings page to open (tests, unsupported platform): the card's
      // words still say where the switch is.
    }
  }

  /// Reuses one already-selected image for another evidence role. A single
  /// photo can legitimately show both the front/UPC or Facts/Other Ingredients
  /// (for example, a store listing screenshot). Retagging preserves one photo
  /// id and one byte hash, so the duplicate-content guard still catches real
  /// duplicate uploads.
  Future<void> _reusePhotoForCategory(
    ProductSubmissionEvidenceCategory category, {
    bool autoAdvance = false,
  }) async {
    if (_submitting || _adding) return;
    final candidates = _photos
        .where((photo) => !photo.categories.contains(category))
        .toList(growable: false);
    if (candidates.isEmpty) {
      setState(() => _stepError = 'Add a different photo before reusing one.');
      return;
    }
    final selected = await showModalBottomSheet<ProductSubmissionPhoto>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: V2Spacing.space16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V2Spacing.space16,
                V2Spacing.space4,
                V2Spacing.space16,
                V2Spacing.space8,
              ),
              child: Text(
                'Use a photo already added',
                style: V2Typography.title(color: sheetContext.v2.fg),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space16,
              ),
              child: Text(
                'Choose the image that also shows this panel. It will receive '
                'the new evidence tag without uploading a duplicate.',
                style: V2Typography.bodySm(color: sheetContext.v2.fgMuted),
              ),
            ),
            const SizedBox(height: V2Spacing.space8),
            for (final photo in candidates)
              ListTile(
                key: Key('missing-product-reuse-photo-${photo.photoId}'),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                  child: Image.memory(
                    photo.bytes,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 56,
                      height: 56,
                      color: sheetContext.v2.surfaceLow,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
                title: Text('Photo ${_photos.indexOf(photo) + 1}'),
                subtitle: Text(_photoLabel(photo)),
                onTap: () => Navigator.of(sheetContext).pop(photo),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final index = _photos.indexOf(selected);
    if (index < 0) return;
    setState(() {
      _photos[index] = selected.withCategories({
        ...selected.categories,
        category,
      });
      _draft = null;
      _stepError = null;
      _failure = null;
    });
    await _persistCapture();
    if (mounted && autoAdvance) await _goForward();
  }

  Future<bool> _confirmBlurryPhoto() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('That photo looks blurry'),
        content: const Text(
          'Can you read the smallest line? A reviewer needs to. Retake it '
          'with steadier hands or better light, or keep it if it’s '
          'readable.',
        ),
        actions: [
          TextButton(
            key: const Key('missing-product-blur-retake'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Retake'),
          ),
          FilledButton(
            key: const Key('missing-product-blur-use-anyway'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('It’s readable — keep it'),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Picks several library photos, drops the ones that cannot be used, and
  /// lets the user confirm which panel each shows. True when photos were
  /// added; capture then lands on the first panel still missing.
  Future<bool> _addSeveralFromLibrary() async {
    final room = _photoCapacity - _photos.length;
    if (room <= 0 || _adding) return false;
    setState(() {
      _adding = true;
      _stepError = null;
      _stepNotice = null;
      _showBlockedCard = false;
    });
    try {
      final picked = await widget.pickPhotosFromLibrary!(room);
      if (!mounted) return false;
      _blockedSources.remove(_BlockedSource.photos);
      if (picked.photos.isNotEmpty) setState(() => _processing = true);
      // A picker that ignores the limit still never overfills a submission,
      // and what it dropped is counted, not silently lost.
      final overflow = picked.photos.length - room;
      var skipped = picked.unreadable + (overflow > 0 ? overflow : 0);
      final seen = {
        for (final photo in _photos) photo.contentSha256,
        ...?widget.retake?.earlierPhotoDigests,
      };
      final usable = <({ProductSubmissionPhoto photo, bool blurry})>[];
      for (final photo in picked.photos.take(room)) {
        if (!seen.add(photo.contentSha256)) {
          skipped += 1;
          continue;
        }
        final quality = await widget.qualityGate(photo);
        if (!mounted) return false;
        if (quality.isHardBlock) {
          skipped += 1;
          continue;
        }
        usable.add((photo: photo, blurry: quality.isSoftWarning));
      }
      if (usable.isEmpty) {
        if (skipped > 0) setState(() => _stepError = _skippedCopy(skipped));
        return false;
      }
      // One at a time: eight full-size recognizers at once is a memory spike
      // on an older phone, for a few seconds saved.
      final hints = <PanelHints>[];
      for (final item in usable) {
        hints.add(await _readHints(item.photo));
        if (!mounted) return false;
      }
      setState(() => _processing = false);
      final sorted = await _sortLibraryPhotos([
        for (var i = 0; i < usable.length; i++)
          (photo: usable[i].photo, blurry: usable[i].blurry, hints: hints[i]),
      ]);
      if (!mounted || sorted == null || sorted.isEmpty) return false;

      setState(() {
        _photos.addAll(sorted);
        _draft = null;
        final combined = sorted.any(
          (photo) => photo.categories.containsAll(const {
            ProductSubmissionEvidenceCategory.supplementFacts,
            ProductSubmissionEvidenceCategory.ingredientDisclosure,
          }),
        );
        if (combined) {
          _factsCarriesIngredients = true;
          _factsPanelLocationConfirmed = true;
        } else if (_photosTagged(
              ProductSubmissionEvidenceCategory.ingredientDisclosure,
            ).isNotEmpty &&
            _photosTagged(
              ProductSubmissionEvidenceCategory.supplementFacts,
            ).isNotEmpty) {
          // Named on separate photos: the user has said where the list is.
          _factsPanelLocationConfirmed = true;
        }
        _stepNotice = skipped > 0 ? _skippedCopy(skipped) : null;
        _step = _firstUnsatisfiedStep();
      });
      await _persistCapture();
      return true;
    } on PlatformException catch (error) {
      if (mounted) {
        final blocked = _blockedSourceFor(error.code);
        setState(() {
          if (blocked != null) {
            _raiseBlocked(blocked);
          } else {
            _stepError = 'We couldn’t open those photos. Try again.';
          }
        });
      }
      return false;
    } on Object {
      if (mounted) {
        setState(
          () => _stepError = 'We couldn’t open those photos. Try again.',
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _adding = false;
          _processing = false;
        });
      }
    }
  }

  String _skippedCopy(int count) =>
      '$count ${count == 1 ? 'photo' : 'photos'} couldn’t be used — too '
      'small, already added, unreadable, or over the photo limit.';

  Set<ProductSubmissionEvidenceCategory> _suggestedCategories(PanelHints h) => {
    if (h.showsFactsPanel) ProductSubmissionEvidenceCategory.supplementFacts,
    if (h.showsOtherIngredients)
      ProductSubmissionEvidenceCategory.ingredientDisclosure,
    if (!h.showsFactsPanel &&
        !h.showsOtherIngredients &&
        h.showsDirectionsOrWarnings)
      ProductSubmissionEvidenceCategory.directionsWarnings,
    if (h.showsSubmissionBarcode) ProductSubmissionEvidenceCategory.barcode,
  };

  /// The user names the panel(s) each photo shows, starting from what its
  /// printed text suggested. Nothing is added until every kept photo has a
  /// name; null means cancelled.
  Future<List<ProductSubmissionPhoto>?> _sortLibraryPhotos(
    List<({ProductSubmissionPhoto photo, bool blurry, PanelHints hints})> items,
  ) {
    final choices = [
      for (final item in items) _suggestedCategories(item.hints),
    ];
    final kept = List<bool>.filled(items.length, true);
    const panels = <(ProductSubmissionEvidenceCategory, String)>[
      (ProductSubmissionEvidenceCategory.frontIdentity, 'Front'),
      (ProductSubmissionEvidenceCategory.supplementFacts, 'Facts'),
      (ProductSubmissionEvidenceCategory.ingredientDisclosure, 'Ingredients'),
      (ProductSubmissionEvidenceCategory.barcode, 'Barcode'),
      (ProductSubmissionEvidenceCategory.directionsWarnings, 'Directions'),
      (ProductSubmissionEvidenceCategory.lotExpiry, 'Lot & expiry'),
    ];
    return showModalBottomSheet<List<ProductSubmissionPhoto>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final ready = [
            for (var i = 0; i < items.length; i++)
              if (kept[i]) i,
          ];
          final canAdd =
              ready.isNotEmpty && ready.every((i) => choices[i].isNotEmpty);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      V2Spacing.space16,
                      0,
                      V2Spacing.space16,
                      V2Spacing.space4,
                    ),
                    child: Text(
                      'Which panel is each photo?',
                      style: V2Typography.title(color: sheetContext.v2.fg),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: V2Spacing.space16,
                    ),
                    child: Text(
                      'We marked what we could read. Tap to change — one '
                      'photo can show more than one panel.',
                      style: V2Typography.bodySm(
                        color: sheetContext.v2.fgMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: V2Spacing.space8),
                  Flexible(
                    child: ListView(
                      key: const Key('missing-product-sort-sheet'),
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: V2Spacing.space16,
                      ),
                      children: [
                        for (final i in ready)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: V2Spacing.space12,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    V2Spacing.radiusCard,
                                  ),
                                  child: Image.memory(
                                    items[i].photo.bytes,
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      width: 64,
                                      height: 64,
                                      color: sheetContext.v2.surfaceLow,
                                      child: const Icon(
                                        Icons.broken_image_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: V2Spacing.space8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: V2Spacing.space4,
                                        runSpacing: V2Spacing.space4,
                                        children: [
                                          for (final (category, label)
                                              in panels)
                                            FilterChip(
                                              key: Key(
                                                'missing-product-sort-$i-'
                                                '${category.wireValue}',
                                              ),
                                              label: Text(label),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              selected: choices[i].contains(
                                                category,
                                              ),
                                              onSelected: (on) => setSheet(
                                                () => on
                                                    ? choices[i].add(category)
                                                    : choices[i].remove(
                                                        category,
                                                      ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (items[i].hints.conflictingBarcode
                                          case final other?)
                                        _sortWarning(
                                          sheetContext,
                                          'Shows barcode ${other.rawDigits}, '
                                          'not the one you scanned.',
                                        ),
                                      if (items[i].blurry)
                                        _sortWarning(
                                          sheetContext,
                                          'Looks blurry. Keep it only if the '
                                          'smallest line is readable.',
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  key: Key('missing-product-sort-$i-remove'),
                                  tooltip: 'Leave this photo out',
                                  onPressed: () =>
                                      setSheet(() => kept[i] = false),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      V2Spacing.space16,
                      V2Spacing.space8,
                      V2Spacing.space16,
                      V2Spacing.space16,
                    ),
                    child: Row(
                      children: [
                        TextButton(
                          key: const Key('missing-product-sort-cancel'),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        FilledButton(
                          key: const Key('missing-product-sort-done'),
                          onPressed: canAdd
                              ? () => Navigator.of(sheetContext).pop([
                                  for (final i in ready)
                                    items[i].photo.withCategories(choices[i]),
                                ])
                              : null,
                          child: Text(
                            'Add ${ready.length} '
                            '${ready.length == 1 ? 'photo' : 'photos'}',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sortWarning(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: V2Spacing.space4),
    child: Text(text, style: V2Typography.caption(color: context.v2.caution)),
  );

  Future<PanelHints> _readHints(ProductSubmissionPhoto photo) async {
    final read = widget.readPhotoText;
    if (read == null) return PanelHints.none;
    try {
      final text = await read(photo).timeout(const Duration(seconds: 5));
      return readPanelHints(text, submission: GtinIdentity.parse(widget.upc));
    } on Object {
      // Text that cannot be read gives no hint. The person and the reviewer
      // judge the photo, as they always did.
      return PanelHints.none;
    }
  }

  /// Where a photo belongs, going by what is printed in it. Null means the
  /// user chose to retake it. Every question can be answered "keep it".
  Future<({ProductSubmissionPhoto photo, String? notice, bool moved})?>
  _placeByHints(ProductSubmissionPhoto photo, PanelHints hints) async {
    final conflict = hints.conflictingBarcode;
    if (conflict != null) {
      final choice = await _askAboutPhoto(
        title: 'A different barcode?',
        body:
            'This photo shows barcode ${conflict.rawDigits}, but you scanned '
            '${widget.upc.replaceAll(RegExp(r'[^0-9]'), '')}. Check it is '
            'the same product before keeping it.',
        keepLabel: 'Same product — keep it',
      );
      if (choice != _HintChoice.keep) return null;
    }

    var tagged = photo;
    var moved = false;
    String? notice;
    final categories = photo.categories;
    if (categories.contains(
          ProductSubmissionEvidenceCategory.supplementFacts,
        ) &&
        !hints.showsFactsPanel &&
        (hints.showsDirectionsOrWarnings || hints.showsOtherIngredients)) {
      final choice = await _askAboutPhoto(
        title: 'Is this the Supplement Facts panel?',
        body:
            '${hints.showsDirectionsOrWarnings ? 'It looks like the directions or warnings.' : 'It looks like the Other Ingredients list.'} '
            'The Supplement Facts panel is the box that lists each ingredient '
            'with its amount.',
        keepLabel: 'It’s the right panel — keep it',
      );
      if (choice != _HintChoice.keep) return null;
    } else if (categories.contains(
          ProductSubmissionEvidenceCategory.frontIdentity,
        ) &&
        hints.showsFactsHeading) {
      final choice = await _askAboutPhoto(
        title: 'This looks like the Supplement Facts panel',
        body:
            'Use it as your Supplement Facts photo? You can take the front of '
            'the package next.',
        keepLabel: 'Keep it as the front',
        moveLabel: 'Use it for Supplement Facts',
      );
      if (choice == _HintChoice.move) {
        tagged = photo.withCategories(_stepCategories(_CaptureStep.facts));
        moved = true;
        notice =
            'Saved as your Supplement Facts photo. Now the front of the '
            'package.';
      } else if (choice != _HintChoice.keep) {
        return null;
      }
    }

    // Only news when the photo was taken for another panel: on the barcode
    // step, finding the barcode is the point of the photo.
    if (hints.showsSubmissionBarcode &&
        !tagged.categories.contains(
          ProductSubmissionEvidenceCategory.barcode,
        ) &&
        !_covered(ProductSubmissionEvidenceCategory.barcode)) {
      tagged = tagged.withCategories({
        ...tagged.categories,
        ProductSubmissionEvidenceCategory.barcode,
      });
      const found =
          'Barcode found in this photo, so no separate barcode photo is '
          'needed.';
      notice = notice == null ? found : '$notice $found';
    }
    return (photo: tagged, notice: notice, moved: moved);
  }

  Future<_HintChoice?> _askAboutPhoto({
    required String title,
    required String body,
    required String keepLabel,
    String? moveLabel,
  }) => showDialog<_HintChoice>(
    context: context,
    // A tap outside must not silently discard or keep a photo.
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Text(body),
      actions: [
        if (moveLabel == null)
          TextButton(
            key: const Key('missing-product-hint-retake'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_HintChoice.retake),
            child: const Text('Retake'),
          )
        else
          TextButton(
            key: const Key('missing-product-hint-move-facts'),
            onPressed: () => Navigator.of(dialogContext).pop(_HintChoice.move),
            child: Text(moveLabel),
          ),
        FilledButton(
          key: const Key('missing-product-hint-keep'),
          onPressed: () => Navigator.of(dialogContext).pop(_HintChoice.keep),
          child: Text(keepLabel),
        ),
      ],
    ),
  );

  void _removePhoto(ProductSubmissionPhoto photo) {
    if (_submitting) return;
    // A photo the user deleted must not survive on disk.
    unawaited(_persistAfterFrame());
    // Its thumbnail holds the photo's bytes; let both go with the photo.
    unawaited(_thumbnails.remove(photo.photoId)?.evict());
    setState(() {
      _photos.remove(photo);
      if (_photosTagged(
        ProductSubmissionEvidenceCategory.supplementFacts,
      ).isEmpty) {
        _factsCarriesIngredients = false;
        _factsPanelLocationConfirmed = false;
      }
      _draft = null;
      _stepError = null;
      _failure = null;
    });
  }

  /// Applies the combined-panel answer by re-tagging facts captures in
  /// place. Existing shots gain or lose the ingredient tag; standalone
  /// ingredient-step captures are left untouched. Nothing is ever deleted
  /// by answering a question.
  /// [reason] is a short fixed tag for why this was decided — never PII,
  /// never label content — logged so Phase B's OCR work can be prioritized
  /// against real hit rates instead of guesswork.
  void _setFactsCoversIngredients(
    bool value, {
    _CaptureStep? nextStep,
    String? reason,
  }) {
    if (_submitting) return;
    if (reason != null) {
      CrashReportingService().log(
        'facts_ingredients_decision: $reason -> '
        '${value ? 'combined' : 'separate'}',
      );
    }
    setState(() {
      _factsCarriesIngredients = value;
      _factsPanelLocationConfirmed = true;
      for (var i = 0; i < _photos.length; i++) {
        final photo = _photos[i];
        if (!photo.categories.contains(
          ProductSubmissionEvidenceCategory.supplementFacts,
        )) {
          continue;
        }
        final next = {...photo.categories};
        if (_factsCarriesIngredients) {
          next.add(ProductSubmissionEvidenceCategory.ingredientDisclosure);
        } else {
          next.remove(ProductSubmissionEvidenceCategory.ingredientDisclosure);
        }
        _photos[i] = photo.withCategories(next);
      }
      _draft = null;
      _stepError = null;
      _failure = null;
      if (nextStep != null) _step = nextStep;
    });
  }

  Future<void> _showNoFactsPanelDeadEnd() async {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('No Supplement Facts panel?'),
        content: const Text(
          'PharmaGuide can only review supplements with a Supplement Facts '
          'panel — it is how reviewers verify what is inside.\n\n'
          'Check the outer box first: the panel is sometimes printed there '
          'instead of on the bottle.',
        ),
        actions: [
          FilledButton(
            key: const Key('missing-product-no-facts-keep-looking'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('It’s on the box — keep going'),
          ),
          TextButton(
            key: const Key('missing-product-no-facts-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('There isn’t one — cancel'),
          ),
        ],
      ),
    );
    if (!mounted || cancel != true) return;
    Navigator.of(context).pop(false);
  }

  /// The intro's start buttons. Camera-first means the button that says
  /// "Start with the front" opens the camera for the front — not a page that
  /// asks the same thing again. Cancelling the camera leaves the user on that
  /// panel's step, with its example and the same button.
  Future<void> _start({required bool fromLibrary}) async {
    if (_checkingIntake || _adding) return;
    _startFromLibrary = fromLibrary;
    await _goForward(fromLibrary: fromLibrary);
    if (!mounted || fromLibrary || _step == _CaptureStep.intro) return;
    if (_step == _CaptureStep.review || _stepSatisfied) return;
    await _addPhoto(
      _stepCategories(_step),
      autoAdvance: _step != _CaptureStep.facts,
    );
  }

  /// The facts step's one question, answered right under the photo. The
  /// answer re-tags the facts shots in place (it can never delete a photo)
  /// and is also the step's "continue".
  Future<void> _answerFactsQuestion({required bool combined}) async {
    if (_submitting || _adding) return;
    _setFactsCoversIngredients(
      combined,
      reason: combined ? 'user_said_combined' : 'user_said_separate',
    );
    await _goForward();
  }

  Future<void> _goForward({bool? fromLibrary, bool keepNotice = false}) async {
    if (_checkingIntake) return;
    // A library-first start that the OS refused raises its card on the way
    // out of the intro; the first capture step is where it belongs.
    final fromIntro = _step == _CaptureStep.intro;
    if (_step == _CaptureStep.intro) {
      if (!_intakeCheckBypassed && !await _checkPreviousSubmission()) {
        return;
      }
      if (!mounted) return;
      _captureFromLibrary = fromLibrary ?? widget.preferLibrary;
      if (_captureFromLibrary &&
          widget.pickPhotosFromLibrary != null &&
          await _addSeveralFromLibrary()) {
        return;
      }
      if (!mounted) return;
    }
    if (!mounted) return;
    if (!_stepSatisfied) {
      setState(() => _stepError = _requiredCopy(_step));
      return;
    }
    // Facts waits for its question (shown under the photo) to be answered;
    // the answer decides whether an ingredients step exists at all.
    if (_step == _CaptureStep.facts && !_factsPanelLocationSettled) return;

    final next = _nextStep();
    setState(() {
      _step = next;
      _stepError = null;
      if (!fromIntro) _showBlockedCard = false;
      if (!keepNotice) {
        _stepNotice = null;
        _savedNote = null;
      }
    });
  }

  /// Where moving on from the current step lands: the next step not already
  /// covered — except that review waits until every required panel is (the
  /// checklist lets a user skip ahead). The one answer both Continue's label
  /// and the move itself use.
  _CaptureStep _nextStep() {
    final steps = _visibleSteps;
    final at = steps.indexOf(_step);
    // A step that stopped existing (ingredients, once they are on the facts
    // photo) resumes wherever capture actually stands.
    if (at < 0) return _firstUnsatisfiedStep();
    var next = at + 1;
    while (next < steps.length - 1 && _alreadyCovered(steps[next])) {
      next++;
    }
    if (next >= steps.length) return _CaptureStep.review;
    final missing = _firstUnsatisfiedStep();
    if (missing != _CaptureStep.review &&
        steps.indexOf(missing) < next &&
        steps[next] == _CaptureStep.review) {
      return missing;
    }
    return steps[next];
  }

  /// The checklist's shortcut to any panel, done or not.
  void _jumpTo(_CaptureStep step) {
    if (_submitting || _adding) return;
    setState(() {
      _step = step;
      _stepError = null;
      _stepNotice = null;
      _savedNote = null;
      _showBlockedCard = false;
    });
  }

  Future<bool> _checkPreviousSubmission() async {
    setState(() {
      _checkingIntake = true;
      _stepError = null;
    });
    try {
      final intake = await widget.service.checkIntake(
        kind: ProductSubmissionKind.missingProduct,
        upc: widget.upc,
      );
      if (!mounted) return false;
      _intakeCheckFailed = false;
      if (intake.action == ProductSubmissionIntakeAction.startNew) return true;

      // The server revalidates explicitly supplied lineage at create time.
      // Never silently replace it with a different rejected attempt.
      if (intake.action == ProductSubmissionIntakeAction.retryRejected &&
          _chosenResubmissionOf == intake.submissionId) {
        return true;
      }
      final existing =
          intake.action == ProductSubmissionIntakeAction.openExisting;
      final retry =
          intake.action == ProductSubmissionIntakeAction.retryRejected;
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text(
            existing
                ? 'You’ve already sent this product'
                : retry
                ? 'Try this product again'
                : 'Your earlier upload was interrupted',
          ),
          content: Text(
            existing
                ? 'Check its progress in Your contributions. If it has already been added, '
                      'the product link appears when your catalog is updated.'
                : retry
                ? '${productSubmissionResolutionGuidance(intake.resolutionCode, detail: intake.resolutionDetail) ?? 'Your earlier submission needs new label photos.'}\n\n'
                      'Photograph the package with barcode ${widget.upc}. '
                      'These new photos will be linked to your earlier submission.'
                : 'The earlier photos weren’t fully uploaded. You can continue the '
                      'original attempt if it is still open on your other device, or take a fresh set here.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('cancel'),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('view'),
              child: const Text('View your contributions'),
            ),
            if (!existing)
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop('continue'),
                child: Text(
                  retry ? 'Try again with new photos' : 'Take new photos',
                ),
              ),
          ],
        ),
      );
      if (!mounted) return false;
      if (choice == 'view') {
        widget.onViewContributions?.call();
        return false;
      }
      if (choice != 'continue') return false;
      if (retry) {
        if (_chosenResubmissionOf != null &&
            _chosenResubmissionOf != intake.submissionId) {
          setState(
            () => _stepError =
                'Your submission history changed. Check Your contributions and try again.',
          );
          return false;
        }
        _chosenResubmissionOf = intake.submissionId;
      }
      return true;
    } on Object catch (error, stackTrace) {
      // Offline or a stalled connection is expected, and the user is offered
      // Try again / Continue below (Sentry PHARMAGUIDE-25 was the 10 s
      // timeout on offline phones). Anything else is a defect worth a report.
      if (CrashReportingService.isTransientNetworkError(error)) {
        CrashReportingService().log(
          'submission intake check unavailable: network',
        );
      } else {
        CrashReportingService().recordError(
          error,
          stackTrace,
          hint: 'submission:intake_check',
        );
      }
      if (mounted) {
        setState(() {
          _intakeCheckFailed = true;
          _stepError =
              'Couldn’t check your previous submissions. Try again, or '
              'continue and we’ll run the final duplicate check when you submit.';
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _checkingIntake = false);
    }
  }

  void _goBack() {
    final steps = _visibleSteps;
    final index = steps.indexOf(_step);
    if (index > 0) {
      setState(() {
        _step = steps[index - 1];
        _stepError = null;
        _stepNotice = null;
        _savedNote = null;
        _showBlockedCard = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _failure = null;
    });

    final retake = widget.retake;
    if (retake != null) {
      await _persistCapture();
      final result = await widget.service.submitRetake(
        retake,
        List.unmodifiable(_photos),
        onPhaseChanged: (phase) {
          if (mounted) setState(() => _phase = phase);
        },
      );
      await _finishSubmit(result);
      return;
    }

    late final MissingProductSubmissionDraft draft;
    try {
      draft =
          _draft ??
          MissingProductSubmissionDraft(
            // The id the saved capture already carries, so a recovered
            // submission replays instead of opening a second contribution.
            submissionId: _draftSubmissionId,
            upc: widget.upc,
            photos: List.unmodifiable(_photos),
            noSeparateIngredientPanel: _factsCarriesIngredients,
            resubmissionOf: _chosenResubmissionOf,
          );
      _draft = draft;
    } on ProductSubmissionValidationException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        if (error.reason == ProductSubmissionValidationFailure.invalidUpc) {
          _stepError = invalidGtinMessage;
          return;
        }
        _failure = const ProductSubmissionFailure(
          submissionId: '',
          kind: ProductSubmissionFailureKind.reportInsertFailed,
        );
      });
      return;
    }

    // Save before the network call, not after. Everything from here on can
    // fail halfway, and the photos are the part the user cannot cheaply redo.
    await _persistCapture();

    final result = await widget.service.submit(
      draft,
      onPhaseChanged: (phase) {
        if (mounted) setState(() => _phase = phase);
      },
    );
    await _finishSubmit(result);
  }

  Future<void> _finishSubmit(ProductSubmissionResult result) async {
    // The server's receipt is the only thing that retires a local draft.
    if (result is ProductSubmissionSuccess) {
      await _discardDraft(result.submissionId);
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (result is ProductSubmissionSuccess) {
        _submitted = true;
      } else {
        _failure = result as ProductSubmissionFailure;
      }
    });
  }

  /// Save on the next turn, once setState has applied the change the caller is
  /// making, so what lands on disk is what the user now sees.
  Future<void> _persistAfterFrame() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    if (_photos.isEmpty) {
      await _discardDraft(_draftSubmissionId);
      return;
    }
    await _persistCapture();
  }

  /// Keep what has been captured so far. Called as photos land, not only at
  /// submit, because a capture abandoned at three of four photos is still
  /// several minutes of the user's effort.
  Future<void> _persistCapture() async {
    final store = _store;
    final userId = widget.service.backend.authenticatedUserId;
    if (store == null || _photos.isEmpty || userId == null || userId.isEmpty) {
      return;
    }
    try {
      await store.save(
        userId: userId,
        submissionId: _draftSubmissionId,
        upc: widget.upc,
        photos: List.unmodifiable(_photos),
        consentVersion: productSubmissionConsentVersion,
        resubmissionOf: _chosenResubmissionOf,
        noSeparateIngredientPanel: _factsCarriesIngredients,
        evidenceRevision: (widget.retake?.fromRevision ?? 0) + 1,
      );
    } on Object {
      // Best effort by design: never fail capture over local bookkeeping.
    }
  }

  Future<void> _discardDraft(String submissionId) async {
    final store = _store;
    final userId = widget.service.backend.authenticatedUserId;
    if (store == null || userId == null || userId.isEmpty) return;
    try {
      await store.discard(userId, submissionId);
    } on Object {
      // A draft left behind is retried and discarded on the next launch.
    }
  }

  /// Offer an unfinished capture for this barcode instead of asking for the
  /// same four photos again. The recovered draft keeps its submission id, so
  /// finishing it replays the server's idempotent sequence.
  Future<void> _offerRecovery() async {
    final store = _store;
    final userId = widget.service.backend.authenticatedUserId;
    if (store == null || !mounted || userId == null || userId.isEmpty) return;
    if (_step != _CaptureStep.intro || _photos.isNotEmpty) return;
    final String savedId;
    final int photoCount;
    final retake = widget.retake;
    if (retake != null) {
      // A retake's capture is saved under its own submission, never found by
      // barcode, and only counts for the request it answered.
      final RestoredCapture? saved;
      try {
        saved = await store.restore(userId, retake.submissionId);
      } on Object {
        return;
      }
      if (saved == null || !mounted) return;
      if (saved.retakeOfRevision != retake.fromRevision) {
        await store.discard(userId, retake.submissionId);
        return;
      }
      savedId = retake.submissionId;
      photoCount = saved.photos.length;
    } else {
      final PendingProductSubmission? pending;
      try {
        pending = await store.findByUpc(userId, widget.upc);
      } on Object {
        return;
      }
      if (pending == null || !mounted) return;
      // A saved capture belonging to a different attempt for this same
      // barcode is not this one's evidence. Sending it would carry the wrong
      // lineage (or none), and the server's open-submission guard would
      // reject it. Leave it alone; Contributions still lists it under its own
      // attempt.
      if (pending.resubmissionOf != _chosenResubmissionOf) return;
      savedId = pending.submissionId;
      photoCount = pending.photoCount;
    }
    final resume = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Finish your photos?'),
        content: Text(
          'You already took $photoCount '
          '${photoCount == 1 ? 'photo' : 'photos'} of this product '
          'and they were never sent. You can pick up where you left off.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Start over'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Finish sending'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (resume != true) {
      await store.discard(userId, savedId);
      return;
    }
    final restored = await store.restore(userId, savedId);
    if (!mounted) return;
    if (restored == null) {
      // The kept bytes no longer match their manifest, so they are not the
      // user's evidence any more. Say so plainly rather than sending them.
      await store.discard(userId, savedId);
      setState(
        () => _stepError =
            'Those saved photos could not be reopened. Please take them again.',
      );
      return;
    }
    setState(() {
      _draftSubmissionId = restored.submissionId;
      _photos
        ..clear()
        ..addAll(restored.photos);
      _chosenResubmissionOf = restored.resubmissionOf;
      _factsCarriesIngredients = restored.noSeparateIngredientPanel;
      _factsPanelLocationConfirmed = restored.noSeparateIngredientPanel;
      // Land where the capture actually stands rather than assuming it was
      // finished: a half-taken set resumes at the first missing panel.
      _step = _firstUnsatisfiedStep();
      _stepError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // One fixed height for the whole flow: steps swap inside a stable frame
    // instead of the sheet jumping to each step's content height, and the
    // footer's primary button sits in the same place for every panel. A
    // guided capture should settle into a rhythm: tap, shoot, tap, shoot.
    final height = math.min(MediaQuery.sizeOf(context).height * 0.82, 720.0);
    if (_submitted) {
      return SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: _SubmissionComplete(
            onDone: () => Navigator.of(context).pop(true),
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            _header(context),
            Expanded(
              // A new step starts at its top: keyed by step, the list does
              // not carry the last step's scroll offset (e.g. from the
              // bottom of review into the ingredients step).
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: ListView(
                  key: const Key('missing-product-scroll'),
                  padding: const EdgeInsets.fromLTRB(
                    V2Spacing.space24,
                    V2Spacing.space8,
                    V2Spacing.space24,
                    V2Spacing.space24,
                  ),
                  children: [
                    ..._statusNotes(context),
                    ...switch (_step) {
                      _CaptureStep.intro => _introContent(context),
                      _CaptureStep.review => _reviewContent(context),
                      _ => _captureContent(context),
                    },
                  ],
                ),
              ),
            ),
            _footer(context, maxHeight: height * 0.55),
          ],
        ),
      ),
    );
  }

  Duration _motion(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

  /// Back and Close; once capture has started, the panel checklist
  /// underneath doubles as the progress bar.
  Widget _header(BuildContext context) {
    final canGoBack = _visibleSteps.indexOf(_step) > 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                if (canGoBack)
                  TextButton.icon(
                    key: const Key('missing-product-back'),
                    onPressed: _submitting ? null : _goBack,
                    icon: const Icon(Icons.chevron_left_rounded, size: 22),
                    label: const Text('Back'),
                  ),
                const Spacer(),
                IconButton(
                  key: const Key('missing-product-close'),
                  // Photos taken so far are kept on the phone; opening this
                  // barcode again offers to finish them.
                  tooltip: 'Close',
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(false),
                  icon: Icon(Icons.close_rounded, color: context.v2.fgMuted),
                ),
              ],
            ),
          ),
          if (_step != _CaptureStep.intro)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V2Spacing.space16,
                0,
                V2Spacing.space16,
                V2Spacing.space4,
              ),
              child: _coverageChecklist(context),
            ),
        ],
      ),
    );
  }

  /// What is covered so far, in the label's own order: a segmented progress
  /// bar whose segments fill as panels are covered — including the ones a
  /// single photo covers twice. Each segment jumps to its panel, so the order
  /// of photos is the user's, not the app's.
  Widget _coverageChecklist(BuildContext context) {
    final v2 = context.v2;
    Widget item(
      String label,
      ProductSubmissionEvidenceCategory category,
      _CaptureStep target, {
      required bool current,
    }) {
      final covered = _covered(category);
      final onTap = _submitting || _adding ? null : () => _jumpTo(target);
      final tone = covered || current ? v2.accentStrong : v2.fgMuted;
      return Expanded(
        child: Semantics(
          button: true,
          selected: current,
          label: '$label: ${covered ? 'done' : 'still needed'}',
          onTap: onTap,
          excludeSemantics: true,
          child: InkWell(
            key: Key('missing-product-checklist-${category.wireValue}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(V2Spacing.space8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 3,
                  vertical: V2Spacing.space8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: _motion(context, V2Motion.base),
                      curve: V2Motion.smooth,
                      height: 4,
                      decoration: BoxDecoration(
                        color: covered
                            ? v2.accentStrong
                            : current
                            ? v2.accentStrong.withValues(alpha: 0.35)
                            : v2.fg.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (covered) ...[
                            Icon(Icons.check_rounded, size: 14, color: tone),
                            const SizedBox(width: 2),
                          ],
                          Text(label, style: V2Typography.caption(color: tone)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        item(
          'Front',
          ProductSubmissionEvidenceCategory.frontIdentity,
          _CaptureStep.front,
          current: _step == _CaptureStep.front,
        ),
        item(
          'Facts',
          ProductSubmissionEvidenceCategory.supplementFacts,
          _CaptureStep.facts,
          current: _step == _CaptureStep.facts,
        ),
        item(
          'Ingredients',
          ProductSubmissionEvidenceCategory.ingredientDisclosure,
          _factsCarriesIngredients
              ? _CaptureStep.facts
              : _CaptureStep.ingredients,
          current: _step == _CaptureStep.ingredients,
        ),
        item(
          'Barcode',
          ProductSubmissionEvidenceCategory.barcode,
          _CaptureStep.barcode,
          current: _step == _CaptureStep.barcode,
        ),
      ],
    );
  }

  List<Widget> _statusNotes(BuildContext context) => [
    if (_savedNote case final saved?) ...[
      _StatusNote(
        key: const Key('missing-product-saved'),
        text: saved,
        icon: Icons.check_circle_rounded,
        tone: context.v2.safe,
        fill: context.v2.safeTint,
      ),
      const SizedBox(height: V2Spacing.space12),
    ],
    if (_stepNotice case final notice?) ...[
      _StatusNote(
        text: notice,
        icon: Icons.info_outline_rounded,
        tone: context.v2.accentStrong,
        fill: context.v2.accentTint,
      ),
      const SizedBox(height: V2Spacing.space12),
    ],
  ];

  Widget? _blockedCard() => _showBlockedCard && _blockedSources.isNotEmpty
      ? _BlockedSourceCard(
          sources: _blockedSources,
          onOpenSettings: () => unawaited(_openSystemSettings()),
        )
      : null;

  List<Widget> _introContent(BuildContext context) {
    final retake = widget.retake;
    final blocked = _blockedCard();
    return [
      const PGEyebrow('Catalog contribution'),
      const SizedBox(height: V2Spacing.space8),
      Text(
        _stepTitle(_CaptureStep.intro),
        key: const Key('missing-product-step-title'),
        style: V2Typography.title(color: context.v2.fg),
      ),
      const SizedBox(height: V2Spacing.space4),
      // Which barcode this is for, before anything else: the identity
      // anchor for "is this the product I scanned?".
      Text(
        'For barcode ${widget.upc.replaceAll(RegExp(r'[^0-9]'), '')}',
        style: V2Typography.monoData(color: context.v2.fgMuted),
      ),
      const SizedBox(height: V2Spacing.space12),
      if (retake != null) ...[
        Text(
          productSubmissionRetakeRequest(retake.reason, retake.requestedPanels),
          key: const Key('missing-product-retake-request'),
          style: V2Typography.body(color: context.v2.fg),
        ),
        if (retake.keptPhotoIds.isNotEmpty) ...[
          const SizedBox(height: V2Spacing.space8),
          Text(
            'Your other photos are kept, so you only need to take what’s '
            'missing.',
            style: V2Typography.bodySm(color: context.v2.fgMuted),
          ),
        ],
      ] else
        Text(
          'Take a few clear label photos and we’ll check whether it already '
          'exists or needs an updated label.',
          style: V2Typography.body(color: context.v2.fgMuted),
        ),
      const SizedBox(height: V2Spacing.space24),
      _PanelPlan(
        rows: [
          (
            label: 'Front label',
            hint: 'Brand and product name',
            kept: _covered(ProductSubmissionEvidenceCategory.frontIdentity),
          ),
          (
            label: 'Supplement Facts panel',
            hint: null,
            kept: _covered(ProductSubmissionEvidenceCategory.supplementFacts),
          ),
          (
            label: 'Other Ingredients',
            hint: 'Often part of the Supplement Facts panel',
            kept: _covered(
              ProductSubmissionEvidenceCategory.ingredientDisclosure,
            ),
          ),
          (
            label: 'Barcode',
            hint: null,
            kept: _covered(ProductSubmissionEvidenceCategory.barcode),
          ),
        ],
      ),
      const SizedBox(height: V2Spacing.space16),
      Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 16, color: context.v2.fgMuted),
          const SizedBox(width: V2Spacing.space8),
          Expanded(
            child: Text(
              'Photos are sent privately for review.',
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
          ),
        ],
      ),
      if (blocked != null) ...[
        const SizedBox(height: V2Spacing.space16),
        blocked,
      ],
    ];
  }

  /// The evidence category a capture step is about.
  ProductSubmissionEvidenceCategory _stepCategory(_CaptureStep step) =>
      switch (step) {
        _CaptureStep.facts => ProductSubmissionEvidenceCategory.supplementFacts,
        _CaptureStep.ingredients =>
          ProductSubmissionEvidenceCategory.ingredientDisclosure,
        _CaptureStep.barcode => ProductSubmissionEvidenceCategory.barcode,
        _CaptureStep.intro ||
        _CaptureStep.front ||
        _CaptureStep.review => ProductSubmissionEvidenceCategory.frontIdentity,
      };

  List<Widget> _captureContent(BuildContext context) {
    final category = _stepCategory(_step);
    final photos = _photosTagged(category);
    final busy = _submitting || _adding;
    final reusable = _photos.any(
      (photo) => !photo.categories.contains(category),
    );
    final blocked = _blockedCard();
    return [
      Text(
        _stepTitle(_step),
        key: const Key('missing-product-step-title'),
        style: V2Typography.title(color: context.v2.fg),
      ),
      const SizedBox(height: V2Spacing.space8),
      Text(
        _stepGuidance(_step),
        style: V2Typography.body(color: context.v2.fgMuted),
      ),
      const SizedBox(height: V2Spacing.space16),
      if (blocked != null) ...[
        blocked,
        const SizedBox(height: V2Spacing.space16),
      ],
      if (photos.isEmpty) ...[
        SubmissionPanelExample(category: category, barcodeDigits: widget.upc),
        if (_step == _CaptureStep.barcode) ...[
          const SizedBox(height: V2Spacing.space8),
          Text(
            'No bars on the package? A clear photo or screenshot of the '
            'printed number works too.',
            style: V2Typography.bodySm(color: context.v2.fgMuted),
          ),
        ],
      ] else ...[
        // "Add another" is the last tile of the row it adds to: no extra
        // height, so the question and Continue below stay in view.
        _PhotoThumbnailStrip(
          photos: photos,
          thumbnailFor: _thumbnailFor,
          enabled: !_submitting,
          onRemove: _removePhoto,
          addTile: _AddPhotoTile(
            key: Key('missing-product-add-${category.wireValue}'),
            label: _processing
                ? 'Checking photo…'
                : _step == _CaptureStep.facts
                ? 'Add another angle'
                : 'Add another photo',
            icon: _captureFromLibrary
                ? Icons.add_photo_alternate_outlined
                : Icons.add_a_photo_outlined,
            busy: _processing,
            onPressed: busy
                ? null
                : () => _addPhoto(
                    _stepCategories(_step),
                    fromLibrary: _captureFromLibrary,
                    autoAdvance: _step != _CaptureStep.facts,
                  ),
          ),
        ),
        if (_step == _CaptureStep.facts) ...[
          const SizedBox(height: V2Spacing.space8),
          Text(
            'Panel wraps around the bottle? Add another angle.',
            style: V2Typography.bodySm(color: context.v2.fgMuted),
          ),
        ],
      ],
      const SizedBox(height: V2Spacing.space8),
      if (_step == _CaptureStep.ingredients &&
          _photosTagged(
            ProductSubmissionEvidenceCategory.supplementFacts,
          ).isNotEmpty)
        _QuietLink(
          key: const Key('missing-product-ingredients-on-facts'),
          label: 'It’s on the Supplement Facts panel',
          onPressed: busy ? null : _ingredientsAreOnFacts,
        ),
      if (reusable)
        _QuietLink(
          key: Key('missing-product-reuse-${category.wireValue}'),
          label: 'Use a photo already added',
          icon: Icons.collections_bookmark_outlined,
          onPressed: busy
              ? null
              : () => _reusePhotoForCategory(
                  category,
                  autoAdvance: _step != _CaptureStep.facts,
                ),
        ),
      if (_step == _CaptureStep.facts)
        _QuietLink(
          key: const Key('missing-product-no-facts-link'),
          label: 'Can’t find a Supplement Facts panel?',
          onPressed: busy ? null : _showNoFactsPanelDeadEnd,
        ),
    ];
  }

  /// The user photographed the facts panel and then landed on "Other
  /// Ingredients" — which was on that panel after all. Re-tag the facts
  /// photos (never delete) and move on from there.
  Future<void> _ingredientsAreOnFacts() async {
    if (_submitting || _adding) return;
    _setFactsCoversIngredients(true, reason: 'user_corrected_to_combined');
    await _goForward();
  }

  List<Widget> _reviewContent(BuildContext context) {
    final busy = _submitting || _adding;
    final missing = [
      for (final step in _visibleSteps)
        if (step != _CaptureStep.intro &&
            step != _CaptureStep.review &&
            !_satisfies(step))
          step,
    ];
    final blocked = _blockedCard();
    return [
      Text(
        _stepTitle(_CaptureStep.review),
        key: const Key('missing-product-step-title'),
        style: V2Typography.title(color: context.v2.fg),
      ),
      const SizedBox(height: V2Spacing.space8),
      Text(
        '${_photos.length} photo${_photos.length == 1 ? '' : 's'} ready to '
        'send.',
        style: V2Typography.body(color: context.v2.fgMuted),
      ),
      const SizedBox(height: V2Spacing.space16),
      _ReviewPhotoGrid(
        photos: _photos,
        thumbnailFor: _thumbnailFor,
        labelFor: _photoLabel,
        enabled: !_submitting,
        onRemove: _removePhoto,
      ),
      if (missing.isNotEmpty) ...[
        const SizedBox(height: V2Spacing.space12),
        _MissingPanelsCard(
          names: [for (final step in missing) _panelName(step)],
          onAdd: busy ? null : () => _jumpTo(missing.first),
        ),
      ],
      if (_factsCarriesIngredients) ...[
        const SizedBox(height: V2Spacing.space12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space16,
            V2Spacing.space12,
            V2Spacing.space8,
            V2Spacing.space4,
          ),
          decoration: BoxDecoration(
            color: context.v2.surfaceLow,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Other Ingredients marked as visible in the Supplement Facts '
                'photo.',
                style: V2Typography.bodySm(color: context.v2.fg),
              ),
              TextButton(
                key: const Key('missing-product-facts-change-to-separate'),
                onPressed: _submitting
                    ? null
                    : () => _setFactsCoversIngredients(
                        false,
                        nextStep: _CaptureStep.ingredients,
                        reason: 'user_corrected_to_separate',
                      ),
                child: const Text('They’re on a separate panel'),
              ),
            ],
          ),
        ),
      ],
      _QuietLink(
        key: const Key('missing-product-wrong-barcode'),
        label: 'Not the product you scanned? Cancel and rescan.',
        onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
      ),
      const SizedBox(height: V2Spacing.space16),
      PGEyebrow('Optional', color: context.v2.fgMuted),
      const SizedBox(height: V2Spacing.space4),
      Text(
        'Directions and lot details help reviewers check dosing and '
        'freshness.',
        style: V2Typography.bodySm(color: context.v2.fgMuted),
      ),
      const SizedBox(height: V2Spacing.space12),
      for (final (category, label) in const [
        (
          ProductSubmissionEvidenceCategory.directionsWarnings,
          'Directions & warnings',
        ),
        (
          ProductSubmissionEvidenceCategory.lotExpiry,
          'Lot number & expiration',
        ),
      ])
        _OptionalCategoryTile(
          label: label,
          category: category,
          count: _photosTagged(category).length,
          enabled: !busy,
          busy: _processing && _addingOptional == category,
          onAdd: () => _addOptional(category),
          onAddFromLibrary: () => _addOptional(category, fromLibrary: true),
        ),
      if (blocked != null) ...[
        blocked,
        const SizedBox(height: V2Spacing.space12),
      ],
      ExpansionTile(
        key: const Key('missing-product-privacy'),
        tilePadding: EdgeInsets.zero,
        title: Text(
          'What we collect',
          style: V2Typography.bodyMedium(color: context.v2.fg),
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(V2Spacing.space16),
            decoration: BoxDecoration(
              color: context.v2.cautionTint,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            ),
            child: Text(
              missingProductPrivacyCopy,
              style: V2Typography.bodySm(color: context.v2.fg),
            ),
          ),
        ],
      ),
      CheckboxListTile(
        key: const Key('missing-product-consent'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        // Beside the first line of the consent, not the middle of it: at
        // large text sizes the paragraph outgrows the screen, and a centred
        // box would sit off-screen mid-paragraph.
        titleAlignment: ListTileTitleAlignment.top,
        value: _consent,
        onChanged: _submitting
            ? null
            : (value) => setState(() {
                _consent = value ?? false;
                _failure = null;
              }),
        title: Text(
          missingProductConsentCopy,
          style: V2Typography.bodySm(color: context.v2.fg),
        ),
      ),
    ];
  }

  Future<void> _addOptional(
    ProductSubmissionEvidenceCategory category, {
    bool fromLibrary = false,
  }) async {
    setState(() => _addingOptional = category);
    await _addPhoto({category}, fromLibrary: fromLibrary);
    if (mounted) setState(() => _addingOptional = null);
  }

  String _photoLabel(ProductSubmissionPhoto photo) => [
    for (final (category, name) in const [
      (ProductSubmissionEvidenceCategory.frontIdentity, 'Front'),
      (ProductSubmissionEvidenceCategory.supplementFacts, 'Facts'),
      (ProductSubmissionEvidenceCategory.ingredientDisclosure, 'Ingredients'),
      (ProductSubmissionEvidenceCategory.barcode, 'Barcode'),
      (ProductSubmissionEvidenceCategory.directionsWarnings, 'Directions'),
      (ProductSubmissionEvidenceCategory.lotExpiry, 'Lot & expiry'),
    ])
      if (photo.categories.contains(category)) name,
  ].join(' · ');

  /// The pinned action area. Errors sit here, right above the button they
  /// are about, so they are never scrolled out of sight. At the largest text
  /// sizes the area can outgrow the fixed frame, so it is capped and scrolls
  /// inside the cap, anchored to the bottom so the buttons stay in view.
  Widget _footer(BuildContext context, {required double maxHeight}) {
    final actions = switch (_step) {
      _CaptureStep.intro => _introActions(context),
      _CaptureStep.review => _reviewActions(context),
      _ => _captureActions(context),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).bottomSheetTheme.backgroundColor,
        border: Border(top: BorderSide(color: context.v2.outline)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space12,
            V2Spacing.space24,
            V2Spacing.space12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_stepError case final error?) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    textAlign: TextAlign.center,
                    style: V2Typography.bodySm(
                      color: context.v2.contraindicated,
                    ),
                  ),
                ),
                const SizedBox(height: V2Spacing.space8),
              ],
              ...actions,
            ],
          ),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required Key key,
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool busy = false,
  }) {
    final Widget? leading = busy
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.v2.fgMuted,
            ),
          )
        : icon == null
        ? null
        : Icon(icon, size: 20);
    return SizedBox(
      height: 52,
      child: leading == null
          ? FilledButton(key: key, onPressed: onPressed, child: Text(label))
          : FilledButton.icon(
              key: key,
              onPressed: onPressed,
              icon: leading,
              label: Text(label),
            ),
    );
  }

  Widget _secondaryButton({
    required Key key,
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
  }) => SizedBox(
    height: 44,
    child: icon == null
        ? TextButton(key: key, onPressed: onPressed, child: Text(label))
        : TextButton.icon(
            key: key,
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
  );

  List<Widget> _introActions(BuildContext context) {
    if (_intakeCheckFailed) {
      return [
        _primaryButton(
          key: const Key('missing-product-intake-retry'),
          label: _checkingIntake ? 'Checking your submissions…' : 'Try again',
          icon: Icons.refresh_rounded,
          onPressed: _checkingIntake
              ? null
              : () => _start(fromLibrary: _startFromLibrary),
        ),
        const SizedBox(height: V2Spacing.space4),
        _secondaryButton(
          key: const Key('missing-product-continue-without-history-check'),
          label: 'Continue anyway',
          onPressed: _checkingIntake
              ? null
              : () {
                  setState(() {
                    _intakeCheckBypassed = true;
                    _intakeCheckFailed = false;
                    _stepError = null;
                  });
                  unawaited(_start(fromLibrary: _startFromLibrary));
                },
        ),
      ];
    }
    // Also closed while library photos are being read and sorted.
    final busy = _checkingIntake || _adding;
    final cameraLabel = widget.preferLibrary
        ? 'Take photos instead'
        : _startLabel;
    final camera = widget.preferLibrary
        ? _secondaryButton(
            key: const Key('missing-product-start'),
            label: cameraLabel,
            icon: Icons.photo_camera_outlined,
            onPressed: busy ? null : () => _start(fromLibrary: false),
          )
        : _primaryButton(
            key: const Key('missing-product-start'),
            // Text, not a spinner: the check can end in a question, and a
            // spinner behind it would say the app is still working.
            label: _checkingIntake && !_startFromLibrary
                ? 'Checking your submissions…'
                : cameraLabel,
            icon: Icons.photo_camera_outlined,
            onPressed: busy ? null : () => _start(fromLibrary: false),
          );
    final library = widget.preferLibrary
        ? _primaryButton(
            key: const Key('missing-product-start-library'),
            label: _checkingIntake && _startFromLibrary
                ? 'Checking your submissions…'
                : 'Choose from your photos',
            icon: Icons.photo_library_outlined,
            onPressed: busy ? null : () => _start(fromLibrary: true),
          )
        : _secondaryButton(
            key: const Key('missing-product-start-library'),
            label: 'Choose from your photos',
            icon: Icons.photo_library_outlined,
            onPressed: busy ? null : () => _start(fromLibrary: true),
          );
    return widget.preferLibrary
        ? [library, const SizedBox(height: V2Spacing.space4), camera]
        : [camera, const SizedBox(height: V2Spacing.space4), library];
  }

  /// The first panel capture will ask for, named on the start button.
  String get _startLabel {
    for (final step in _visibleSteps) {
      if (step == _CaptureStep.intro || _alreadyCovered(step)) continue;
      return switch (step) {
        _CaptureStep.front => 'Start with the front',
        _CaptureStep.facts => 'Start with Supplement Facts',
        _CaptureStep.ingredients => 'Start with Other Ingredients',
        _CaptureStep.barcode => 'Start with the barcode',
        _CaptureStep.intro || _CaptureStep.review => 'Continue',
      };
    }
    return 'Continue';
  }

  List<Widget> _captureActions(BuildContext context) {
    final category = _stepCategory(_step);
    final hasPhotos = _photosTagged(category).isNotEmpty;
    final busy = _submitting || _adding;
    if (_step == _CaptureStep.facts &&
        hasPhotos &&
        !_factsPanelLocationSettled) {
      return [
        Text(
          'Is the “Other Ingredients” list on this panel too?',
          textAlign: TextAlign.center,
          style: V2Typography.bodyMedium(color: context.v2.fg),
        ),
        const SizedBox(height: V2Spacing.space12),
        _primaryButton(
          key: const Key('missing-product-facts-combined'),
          label: 'Yes, it’s on this panel',
          onPressed: busy ? null : () => _answerFactsQuestion(combined: true),
        ),
        const SizedBox(height: V2Spacing.space8),
        SizedBox(
          height: 48,
          child: OutlinedButton(
            key: const Key('missing-product-facts-separate'),
            onPressed: busy
                ? null
                : () => _answerFactsQuestion(combined: false),
            child: const Text('No, it’s separate'),
          ),
        ),
      ];
    }
    if (_stepSatisfied) {
      return [
        _primaryButton(
          key: const Key('missing-product-next'),
          label: _continueLabel,
          onPressed: busy ? null : _goForward,
        ),
      ];
    }
    final fromLibrary = _captureFromLibrary;
    return [
      _primaryButton(
        key: Key('missing-product-add-${category.wireValue}'),
        label: _processing
            ? 'Checking photo…'
            : fromLibrary
            ? 'Choose a photo'
            : 'Take photo',
        icon: fromLibrary
            ? Icons.photo_library_outlined
            : Icons.photo_camera_outlined,
        busy: _processing,
        onPressed: busy
            ? null
            : () => _addPhoto(
                _stepCategories(_step),
                fromLibrary: fromLibrary,
                autoAdvance: _step != _CaptureStep.facts,
              ),
      ),
      const SizedBox(height: V2Spacing.space4),
      _secondaryButton(
        key: Key('missing-product-library-${category.wireValue}'),
        // The link offers the OTHER source: the camera in library mode, the
        // library otherwise.
        label: fromLibrary ? 'Use camera instead' : 'Choose from your photos',
        icon: fromLibrary
            ? Icons.photo_camera_outlined
            : Icons.photo_library_outlined,
        onPressed: busy
            ? null
            : () => _addPhoto(
                _stepCategories(_step),
                fromLibrary: !fromLibrary,
                autoAdvance: _step != _CaptureStep.facts,
              ),
      ),
    ];
  }

  /// "Review photos" when the next stop is review, so the last Continue says
  /// where it goes.
  String get _continueLabel =>
      _nextStep() == _CaptureStep.review ? 'Review photos' : 'Continue';

  List<Widget> _reviewActions(BuildContext context) {
    final failure = _failure;
    final duplicate =
        failure?.cause?.toString().contains('user_open_upc') ?? false;
    final helper = _submitting
        ? switch (_phase) {
            ProductSubmissionPhase.savingReport => 'Saving your report…',
            ProductSubmissionPhase.uploadingPhotos =>
              'Uploading ${_photos.length} photo'
                  '${_photos.length == 1 ? '' : 's'}…',
            ProductSubmissionPhase.succeeded => 'Done',
            ProductSubmissionPhase.failed => 'Something went wrong',
            null => 'Sending…',
          }
        : !_coverageComplete
        ? 'Add the missing photo to submit.'
        : !_consent
        ? 'Check the consent box above to submit.'
        : 'A reviewer checks every label before it can enter the catalog.';
    return [
      if (failure != null) ...[
        Semantics(
          liveRegion: true,
          child: Text(
            _failureCopy(failure),
            textAlign: TextAlign.center,
            style: V2Typography.bodySm(color: context.v2.contraindicated),
          ),
        ),
        if (duplicate && widget.onViewContributions != null)
          _secondaryButton(
            key: const Key('missing-product-view-contributions'),
            label: 'View your contributions',
            onPressed: widget.onViewContributions,
          ),
        const SizedBox(height: V2Spacing.space8),
      ],
      _primaryButton(
        key: const Key('missing-product-submit'),
        label: _submitting
            ? 'Sending…'
            : failure != null
            ? 'Try again'
            : 'Submit for review',
        busy: _submitting,
        onPressed: _canSubmit ? _submit : null,
      ),
      const SizedBox(height: V2Spacing.space8),
      Text(
        helper,
        textAlign: TextAlign.center,
        style: V2Typography.caption(color: context.v2.fgMuted),
      ),
    ];
  }

  String _failureCopy(ProductSubmissionFailure failure) {
    if (failure.kind == ProductSubmissionFailureKind.authenticationRequired) {
      return 'Sign in before submitting product photos.';
    }
    final cause = failure.cause?.toString() ?? '';
    if (cause.contains('user_open_upc')) {
      return 'You already have an open submission for this barcode. '
          'Check its status under Settings → Product submissions.';
    }
    return 'Could not submit this product. Your photos remain here so you '
        'can try again.';
  }

  String _stepTitle(_CaptureStep step) => switch (step) {
    _CaptureStep.intro =>
      widget.retake == null ? 'Add this product' : 'New photos needed',
    _CaptureStep.front => 'Front of the package',
    _CaptureStep.facts => 'Supplement Facts',
    _CaptureStep.ingredients => 'Other Ingredients',
    _CaptureStep.barcode => 'Barcode',
    _CaptureStep.review => 'Review & submit',
  };

  /// One line: what to photograph and what makes it usable.
  String _stepGuidance(_CaptureStep step) => switch (step) {
    _CaptureStep.front =>
      'Fill the frame so the brand and product name are easy to read.',
    // Measured: a panel filling under about a third of the frame loses its
    // smallest dose lines before anyone can read them.
    _CaptureStep.facts =>
      'Fill the frame with the whole panel, straight on and without glare.',
    _CaptureStep.ingredients =>
      'Photograph the full list. Every ingredient matters for safety checks.',
    _CaptureStep.barcode =>
      'Photograph the barcode so a reviewer can match it to the one you '
          'scanned.',
    _CaptureStep.intro || _CaptureStep.review => '',
  };

  /// The panel a step photographs, as the confirmation names it.
  String _panelName(_CaptureStep step) => switch (step) {
    _CaptureStep.front => 'Front',
    _CaptureStep.facts => 'Supplement Facts',
    _CaptureStep.ingredients => 'Other Ingredients',
    _CaptureStep.barcode => 'Barcode',
    _CaptureStep.intro || _CaptureStep.review => 'Label',
  };

  String _requiredCopy(_CaptureStep step) => switch (step) {
    _CaptureStep.front => 'Add at least one photo of the front label.',
    _CaptureStep.facts =>
      'Add at least one photo of the Supplement Facts '
          'panel.',
    _CaptureStep.ingredients =>
      'Add at least one photo of the Other '
          'Ingredients list.',
    _CaptureStep.barcode =>
      'Add a clear photo or screenshot showing this package’s UPC digits.',
    _CaptureStep.intro || _CaptureStep.review => '',
  };
}

/// The four panels the intro promises, numbered in the order capture asks
/// for them. A retake marks the ones a reviewer already has as kept.
class _PanelPlan extends StatelessWidget {
  const _PanelPlan({required this.rows});

  final List<({String label, String? hint, bool kept})> rows;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    return Container(
      decoration: BoxDecoration(
        color: v2.surfaceLow,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      ),
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.space4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space16,
                vertical: V2Spacing.space8,
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: rows[i].kept ? v2.accentStrong : v2.accentTint,
                      shape: BoxShape.circle,
                    ),
                    child: rows[i].kept
                        ? Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: v2.onAccent,
                          )
                        : Text(
                            '${i + 1}',
                            style: V2Typography.label(color: v2.accentStrong),
                          ),
                  ),
                  const SizedBox(width: V2Spacing.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].label,
                          style: V2Typography.bodyMedium(color: v2.fg),
                        ),
                        if (rows[i].hint case final hint?)
                          Text(
                            hint,
                            style: V2Typography.bodySm(color: v2.fgMuted),
                          ),
                      ],
                    ),
                  ),
                  if (rows[i].kept)
                    Text(
                      'Kept',
                      style: V2Typography.caption(color: v2.fgMuted),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusNote extends StatelessWidget {
  const _StatusNote({
    super.key,
    required this.text,
    required this.icon,
    required this.tone,
    required this.fill,
  });

  final String text;
  final IconData icon;
  final Color tone;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.space12,
          vertical: V2Spacing.space8,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: tone),
            ),
            const SizedBox(width: V2Spacing.space8),
            Expanded(
              child: Text(
                text,
                style: V2Typography.bodySm(color: context.v2.fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A centered tertiary action with a full 44-point tap target and readable
/// contrast — the old caption-grey links measured about 3.2:1.
class _QuietLink extends StatelessWidget {
  const _QuietLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      minimumSize: const Size(0, 44),
      foregroundColor: context.v2.accentStrong,
    );
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: V2Typography.bodySm(color: null),
    );
    return Center(
      child: icon == null
          ? TextButton(style: style, onPressed: onPressed, child: text)
          : TextButton.icon(
              style: style,
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: text,
            ),
    );
  }
}

class _PhotoThumbnailStrip extends StatelessWidget {
  const _PhotoThumbnailStrip({
    required this.photos,
    required this.thumbnailFor,
    required this.enabled,
    required this.onRemove,
    this.addTile,
  });

  static const double size = 104;

  final List<ProductSubmissionPhoto> photos;
  final ImageProvider Function(ProductSubmissionPhoto photo) thumbnailFor;
  final bool enabled;
  final void Function(ProductSubmissionPhoto photo) onRemove;
  final Widget? addTile;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length + (addTile == null ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(width: V2Spacing.space12),
        itemBuilder: (context, index) => index == photos.length
            ? addTile!
            : _Thumbnail(
                photo: photos[index],
                image: thumbnailFor(photos[index]),
                size: size,
                semanticLabel: 'Captured label photo ${index + 1} preview',
                enabled: enabled,
                onRemove: onRemove,
              ),
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({
    super.key,
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    final tone = onPressed == null && !busy ? v2.fgMuted : v2.accentStrong;
    return SizedBox.square(
      dimension: _PhotoThumbnailStrip.size,
      child: Material(
        color: v2.accentTint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: Padding(
            padding: const EdgeInsets.all(V2Spacing.space8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(icon, size: 24, color: tone),
                const SizedBox(height: V2Spacing.space8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: V2Typography.caption(color: tone),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every photo, labelled with the panel(s) it counts for, so the user can
/// see at a glance that each required panel is there.
class _ReviewPhotoGrid extends StatelessWidget {
  const _ReviewPhotoGrid({
    required this.photos,
    required this.thumbnailFor,
    required this.labelFor,
    required this.enabled,
    required this.onRemove,
  });

  final List<ProductSubmissionPhoto> photos;
  final ImageProvider Function(ProductSubmissionPhoto photo) thumbnailFor;
  final String Function(ProductSubmissionPhoto photo) labelFor;
  final bool enabled;
  final void Function(ProductSubmissionPhoto photo) onRemove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = V2Spacing.space12;
        final tile = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: V2Spacing.space12,
          children: [
            for (var i = 0; i < photos.length; i++)
              SizedBox(
                width: tile,
                child: Column(
                  children: [
                    _Thumbnail(
                      photo: photos[i],
                      image: thumbnailFor(photos[i]),
                      size: tile,
                      semanticLabel: 'Photo ${i + 1}: ${labelFor(photos[i])}',
                      enabled: enabled,
                      onRemove: onRemove,
                    ),
                    const SizedBox(height: V2Spacing.space4),
                    Text(
                      labelFor(photos[i]),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: V2Typography.caption(color: context.v2.fgMuted),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.photo,
    required this.image,
    required this.size,
    required this.semanticLabel,
    required this.enabled,
    required this.onRemove,
  });

  final ProductSubmissionPhoto photo;
  final ImageProvider image;
  final double size;
  final String semanticLabel;
  final bool enabled;
  final void Function(ProductSubmissionPhoto photo) onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              container: true,
              image: true,
              excludeSemantics: true,
              label: semanticLabel,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                child: Image(
                  image: image,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: context.v2.surfaceLow,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            // A near-solid disc in the text colour, with the glyph in the
            // background colour, stays readable on any photo in either
            // appearance; the padded tap target keeps the full 48 points.
            child: IconButton(
              key: Key('missing-product-remove-${photo.photoId}'),
              tooltip: 'Remove photo',
              onPressed: enabled ? () => onRemove(photo) : null,
              style: IconButton.styleFrom(
                backgroundColor: context.v2.fg.withValues(alpha: 0.72),
                foregroundColor: context.v2.bg,
                disabledBackgroundColor: context.v2.fg.withValues(alpha: 0.3),
                fixedSize: const Size(30, 30),
                minimumSize: const Size(30, 30),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              iconSize: 18,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingPanelsCard extends StatelessWidget {
  const _MissingPanelsCard({required this.names, required this.onAdd});

  final List<String> names;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('missing-product-review-missing'),
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space16,
        V2Spacing.space8,
        V2Spacing.space8,
        V2Spacing.space8,
      ),
      decoration: BoxDecoration(
        color: context.v2.cautionTint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: context.v2.caution),
          const SizedBox(width: V2Spacing.space8),
          Expanded(
            child: Text(
              'Still needed: ${names.join(', ')}',
              style: V2Typography.bodySm(color: context.v2.fg),
            ),
          ),
          TextButton(onPressed: onAdd, child: const Text('Add')),
        ],
      ),
    );
  }
}

class _OptionalCategoryTile extends StatelessWidget {
  const _OptionalCategoryTile({
    required this.label,
    required this.category,
    required this.count,
    required this.enabled,
    required this.busy,
    required this.onAdd,
    required this.onAddFromLibrary,
  });

  final String label;
  final ProductSubmissionEvidenceCategory category;

  /// Photos already added for this panel; they show in the grid above.
  final int count;
  final bool enabled;
  final bool busy;
  final VoidCallback onAdd;

  /// Both sources are offered explicitly. These panels are exactly the ones a
  /// contributor photographs away from the bottle — a warning read off a
  /// listing, a lot number from an earlier picture — so inheriting the
  /// camera from an earlier step left them with no way to add it at all.
  final VoidCallback onAddFromLibrary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space16,
          V2Spacing.space4,
          V2Spacing.space4,
          V2Spacing.space4,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: context.v2.fg.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        ),
        child: Row(
          children: [
            if (count > 0) ...[
              Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: context.v2.accentStrong,
              ),
              const SizedBox(width: V2Spacing.space8),
            ],
            Expanded(
              child: Text(
                label,
                style: V2Typography.bodyMedium(color: context.v2.fg),
              ),
            ),
            IconButton(
              key: Key('missing-product-add-library-${category.wireValue}'),
              onPressed: enabled ? onAddFromLibrary : null,
              icon: const Icon(Icons.photo_library_outlined),
              tooltip: 'Choose from your photos',
            ),
            TextButton.icon(
              key: Key('missing-product-add-${category.wireValue}'),
              style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: enabled ? onAdd : null,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_camera_outlined, size: 18),
              label: Text(count == 0 ? 'Add' : 'Add another'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown in place of a dead-end "try again" when the OS will not open the
/// camera or the photo library for us.
class _BlockedSourceCard extends StatelessWidget {
  const _BlockedSourceCard({
    required this.sources,
    required this.onOpenSettings,
  });

  final Set<_BlockedSource> sources;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final camera = sources.contains(_BlockedSource.camera);
    final photos = sources.contains(_BlockedSource.photos);
    final (key, title, body) = switch ((camera, photos)) {
      (true, true) => (
        'both',
        'Camera and photo access are off',
        'Turn them on for PharmaGuide in Settings to add label photos.',
      ),
      (true, false) => (
        'camera',
        'Camera access is off',
        'Turn on camera access for PharmaGuide in Settings, or choose '
            'photos you already have.',
      ),
      _ => (
        'photos',
        'Photo access is off',
        'Turn on photo access for PharmaGuide in Settings, or take new '
            'photos with the camera.',
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        key: Key('missing-product-blocked-$key'),
        width: double.infinity,
        padding: const EdgeInsets.all(V2Spacing.space16),
        decoration: BoxDecoration(
          color: context.v2.cautionTint,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  camera
                      ? Icons.no_photography_outlined
                      : Icons.hide_image_outlined,
                  size: 20,
                  color: context.v2.caution,
                ),
                const SizedBox(width: V2Spacing.space8),
                Expanded(
                  child: Text(
                    title,
                    style: V2Typography.bodyMedium(color: context.v2.fg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: V2Spacing.space4),
            Text(body, style: V2Typography.bodySm(color: context.v2.fgMuted)),
            const SizedBox(height: V2Spacing.space12),
            OutlinedButton.icon(
              key: const Key('missing-product-open-settings'),
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmissionComplete extends StatelessWidget {
  const _SubmissionComplete({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(V2Spacing.space24),
            child: Column(
              children: [
                const SizedBox(height: V2Spacing.space32),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: v2.safeTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded, size: 44, color: v2.safe),
                ),
                const SizedBox(height: V2Spacing.space24),
                Text(
                  'Thanks — it’s in review',
                  textAlign: TextAlign.center,
                  style: V2Typography.title(color: v2.fg),
                ),
                const SizedBox(height: V2Spacing.space8),
                Text(
                  'A reviewer checks every label before it can enter the '
                  'catalog. Track progress under Settings → Product '
                  'submissions — we’ll also notify you.',
                  textAlign: TextAlign.center,
                  style: V2Typography.body(color: v2.fgMuted),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space12,
            V2Spacing.space24,
            V2Spacing.space12,
          ),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton(
              key: const Key('missing-product-done'),
              onPressed: onDone,
              child: const Text('Done'),
            ),
          ),
        ),
      ],
    );
  }
}
