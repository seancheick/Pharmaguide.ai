import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_progress_dots.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/services/photo_quality_gate.dart';
import 'package:pharmaguide/services/product_submission_photo_service.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

typedef PickMissingProductPhoto =
    Future<ProductSubmissionPhoto?> Function(
      Set<ProductSubmissionEvidenceCategory> categories,
    );

typedef EvaluatePhotoQuality =
    Future<PhotoQualityResult> Function(ProductSubmissionPhoto photo);

/// Opens the one production intake flow used by camera and manual barcode
/// misses. Authentication remains a caller decision so the helper never
/// guesses whether to redirect or silently drop a submission attempt.
Future<bool> showMissingProductSubmissionSheet(
  BuildContext context, {
  required String upc,
  ProductSubmissionService? service,
  PickMissingProductPhoto? pickPhoto,
  EvaluatePhotoQuality? qualityGate,
  String Function()? submissionIdFactory,
}) async {
  final picker = ImagePicker();
  final submitted = await PGModal.bottomSheet<bool>(
    context: context,
    builder: (sheetContext) => MissingProductSubmissionSheet(
      upc: upc,
      service: service ?? ProductSubmissionService.production(),
      submissionIdFactory: submissionIdFactory,
      qualityGate:
          qualityGate ?? (photo) => PhotoQualityGate.evaluate(photo.bytes),
      pickPhoto:
          pickPhoto ??
          (categories) async {
            final source = await PGModal.bottomSheet<ImageSource>(
              context: sheetContext,
              builder: (sourceContext) => _SubmissionPhotoSourceSheet(
                onCamera: () =>
                    Navigator.of(sourceContext).pop(ImageSource.camera),
                onLibrary: () =>
                    Navigator.of(sourceContext).pop(ImageSource.gallery),
              ),
            );
            if (source == null) return null;
            return pickProductSubmissionPhoto(
              picker: picker,
              categories: categories,
              source: source,
            );
          },
    ),
  );
  return submitted == true;
}

/// One guided capture step. `categories` is what a photo taken on this step
/// is tagged with; steps whose categories are already covered elsewhere
/// (facts photo dual-tagged with the ingredient list) skip automatically.
enum _CaptureStep { front, facts, ingredients, extras, review }

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
    this.submissionIdFactory,
  });

  final String upc;
  final ProductSubmissionService service;
  final PickMissingProductPhoto pickPhoto;
  final EvaluatePhotoQuality qualityGate;
  final String Function()? submissionIdFactory;

  @override
  State<MissingProductSubmissionSheet> createState() =>
      _MissingProductSubmissionSheetState();
}

class _MissingProductSubmissionSheetState
    extends State<MissingProductSubmissionSheet> {
  final List<ProductSubmissionPhoto> _photos = [];
  _CaptureStep _step = _CaptureStep.front;
  bool _factsCarriesIngredients = false;
  bool _consent = false;
  bool _submitting = false;
  bool _submitted = false;
  bool _adding = false;
  String? _stepError;
  ProductSubmissionPhase? _phase;
  ProductSubmissionFailure? _failure;
  MissingProductSubmissionDraft? _draft;

  List<_CaptureStep> get _visibleSteps => [
    _CaptureStep.front,
    _CaptureStep.facts,
    if (!_factsCarriesIngredients) _CaptureStep.ingredients,
    _CaptureStep.extras,
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
        _CaptureStep.extras || _CaptureStep.review =>
          const <ProductSubmissionEvidenceCategory>{},
      };

  bool get _stepSatisfied => switch (_step) {
    _CaptureStep.front =>
      _photosTagged(ProductSubmissionEvidenceCategory.frontIdentity).isNotEmpty,
    _CaptureStep.facts =>
      _photosTagged(
        ProductSubmissionEvidenceCategory.supplementFacts,
      ).isNotEmpty,
    _CaptureStep.ingredients =>
      _photosTagged(
        ProductSubmissionEvidenceCategory.ingredientDisclosure,
      ).isNotEmpty,
    _CaptureStep.extras || _CaptureStep.review => true,
  };

  bool get _canSubmit => _consent && !_submitting && _coverageComplete;

  bool get _coverageComplete {
    final covered = <ProductSubmissionEvidenceCategory>{
      for (final photo in _photos) ...photo.categories,
    };
    return covered.containsAll(
      MissingProductSubmissionDraft.requiredCategories,
    );
  }

  Future<void> _addPhoto(
    Set<ProductSubmissionEvidenceCategory> categories,
  ) async {
    if (_submitting || _adding) return;
    if (_photos.length >= ProductSubmissionPhoto.maxPerSubmission) {
      setState(
        () => _stepError =
            'Up to ${ProductSubmissionPhoto.maxPerSubmission} photos per '
            'submission. Remove one to add another.',
      );
      return;
    }
    setState(() {
      _adding = true;
      _stepError = null;
      _failure = null;
    });
    try {
      final photo = await widget.pickPhoto(categories);
      if (!mounted || photo == null) return;
      if (_photos.any((p) => p.contentSha256 == photo.contentSha256)) {
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
        final useAnyway = await _confirmBlurryPhoto();
        if (!mounted || !useAnyway) return;
      }

      setState(() {
        _photos.add(photo);
        _draft = null;
      });
    } on ProductSubmissionValidationException {
      if (!mounted) return;
      setState(
        () => _stepError =
            'That photo could not be prepared. Choose a clear JPG, PNG, '
            'HEIC, or WebP image under 15 MB.',
      );
    } on Object {
      if (!mounted) return;
      setState(() => _stepError = 'We couldn’t open that photo. Try again.');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<bool> _confirmBlurryPhoto() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('That photo looks blurry'),
        content: const Text(
          'A reviewer may not be able to read the label. Retake it with '
          'steadier hands or better light, or use it anyway.',
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
            child: const Text('Use anyway'),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _removePhoto(ProductSubmissionPhoto photo) {
    if (_submitting) return;
    setState(() {
      _photos.remove(photo);
      _draft = null;
      _stepError = null;
      _failure = null;
    });
  }

  void _setFactsCarriesIngredients(bool? value) {
    if (_submitting) return;
    setState(() {
      _factsCarriesIngredients = value ?? false;
      // The toggle states whether the facts panel carries the ingredient
      // list, so existing facts captures gain or lose that tag in place —
      // deleting them punished ticking the box after taking the shot.
      // Standalone ingredient-step captures are left untouched.
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
    });
  }

  void _goForward() {
    final steps = _visibleSteps;
    final index = steps.indexOf(_step);
    if (!_stepSatisfied) {
      setState(() => _stepError = _requiredCopy(_step));
      return;
    }
    if (index < steps.length - 1) {
      setState(() {
        _step = steps[index + 1];
        _stepError = null;
      });
    }
  }

  void _goBack() {
    final steps = _visibleSteps;
    final index = steps.indexOf(_step);
    if (index > 0) {
      setState(() {
        _step = steps[index - 1];
        _stepError = null;
      });
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _failure = null;
    });

    late final MissingProductSubmissionDraft draft;
    try {
      draft =
          _draft ??
          MissingProductSubmissionDraft.create(
            upc: widget.upc,
            photos: List.unmodifiable(_photos),
            noSeparateIngredientPanel: _factsCarriesIngredients,
            submissionIdFactory: widget.submissionIdFactory,
          );
      _draft = draft;
    } on ProductSubmissionValidationException {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _failure = const ProductSubmissionFailure(
          submissionId: '',
          kind: ProductSubmissionFailureKind.reportInsertFailed,
        );
      });
      return;
    }

    final result = await widget.service.submit(
      draft,
      onPhaseChanged: (phase) {
        if (mounted) setState(() => _phase = phase);
      },
    );
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

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return _SubmissionComplete(onDone: () => Navigator.of(context).pop(true));
    }
    final steps = _visibleSteps;
    final stepIndex = steps.indexOf(_step);

    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space24,
          V2Spacing.space8,
          V2Spacing.space24,
          V2Spacing.space24,
        ),
        children: [
          const PGEyebrow('Catalog contribution'),
          const SizedBox(height: V2Spacing.space8),
          Text(
            _stepTitle(_step),
            style: V2Typography.title(color: context.v2.fg),
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'UPC ${widget.upc.replaceAll(RegExp(r'[^0-9]'), '')}',
            style: V2Typography.monoData(color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space12),
          Center(
            child: PGProgressDots(total: steps.length, current: stepIndex),
          ),
          const SizedBox(height: V2Spacing.space16),
          ..._buildStep(context),
          if (_stepError != null) ...[
            const SizedBox(height: V2Spacing.space8),
            Semantics(
              liveRegion: true,
              child: Text(
                _stepError!,
                style: V2Typography.bodySm(color: context.v2.contraindicated),
              ),
            ),
          ],
          const SizedBox(height: V2Spacing.space16),
          Row(
            children: [
              if (stepIndex > 0)
                TextButton(
                  key: const Key('missing-product-back'),
                  onPressed: _submitting ? null : _goBack,
                  child: const Text('Back'),
                ),
              const Spacer(),
              if (_step != _CaptureStep.review)
                FilledButton(
                  key: const Key('missing-product-next'),
                  onPressed: _submitting || _adding ? null : _goForward,
                  child: const Text('Next'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStep(BuildContext context) => switch (_step) {
    _CaptureStep.front => _captureStepBody(
      context,
      guidance:
          'Fill the frame with the front of the package so the brand and '
          'product name are readable.',
      category: ProductSubmissionEvidenceCategory.frontIdentity,
    ),
    _CaptureStep.facts => [
      ..._captureStepBody(
        context,
        guidance:
            'Capture the whole Supplement Facts panel, straight on. On a '
            'curved bottle, add a second angle so no rows are cut off at '
            'the edges.',
        category: ProductSubmissionEvidenceCategory.supplementFacts,
      ),
      CheckboxListTile(
        key: const Key('missing-product-facts-carries-ingredients'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _factsCarriesIngredients,
        onChanged: _submitting ? null : _setFactsCarriesIngredients,
        title: Text(
          'The “Other Ingredients” list is part of this panel — there is no '
          'separate section on the label',
          style: V2Typography.bodySm(color: context.v2.fg),
        ),
      ),
    ],
    _CaptureStep.ingredients => _captureStepBody(
      context,
      guidance:
          'Capture the “Other Ingredients” list — usually right below the '
          'Supplement Facts panel. Every ingredient matters for safety '
          'checks.',
      category: ProductSubmissionEvidenceCategory.ingredientDisclosure,
    ),
    _CaptureStep.extras => [
      Text(
        'Optional — these panels help our reviewers verify dosing and '
        'freshness.',
        style: V2Typography.bodySm(color: context.v2.fgMuted),
      ),
      const SizedBox(height: V2Spacing.space12),
      _OptionalCategoryTile(
        label: 'Directions & warnings',
        category: ProductSubmissionEvidenceCategory.directionsWarnings,
        photos: _photosTagged(
          ProductSubmissionEvidenceCategory.directionsWarnings,
        ),
        enabled: !_submitting && !_adding,
        onAdd: () => _addPhoto(const {
          ProductSubmissionEvidenceCategory.directionsWarnings,
        }),
        onRemove: _removePhoto,
      ),
      _OptionalCategoryTile(
        label: 'Barcode close-up',
        category: ProductSubmissionEvidenceCategory.barcode,
        photos: _photosTagged(ProductSubmissionEvidenceCategory.barcode),
        enabled: !_submitting && !_adding,
        onAdd: () =>
            _addPhoto(const {ProductSubmissionEvidenceCategory.barcode}),
        onRemove: _removePhoto,
      ),
      _OptionalCategoryTile(
        label: 'Lot number & expiration',
        category: ProductSubmissionEvidenceCategory.lotExpiry,
        photos: _photosTagged(ProductSubmissionEvidenceCategory.lotExpiry),
        enabled: !_submitting && !_adding,
        onAdd: () =>
            _addPhoto(const {ProductSubmissionEvidenceCategory.lotExpiry}),
        onRemove: _removePhoto,
      ),
    ],
    _CaptureStep.review => _reviewStepBody(context),
  };

  List<Widget> _captureStepBody(
    BuildContext context, {
    required String guidance,
    required ProductSubmissionEvidenceCategory category,
  }) {
    final photos = _photosTagged(category);
    return [
      Text(guidance, style: V2Typography.bodySm(color: context.v2.fgMuted)),
      const SizedBox(height: V2Spacing.space12),
      _PhotoThumbnailStrip(
        photos: photos,
        enabled: !_submitting,
        onRemove: _removePhoto,
      ),
      const SizedBox(height: V2Spacing.space8),
      OutlinedButton.icon(
        key: Key('missing-product-add-${category.wireValue}'),
        onPressed: _submitting || _adding
            ? null
            : () => _addPhoto(_stepCategories(_step)),
        icon: const Icon(Icons.photo_camera_outlined, size: 18),
        label: Text(photos.isEmpty ? 'Add photo' : 'Add another angle'),
      ),
    ];
  }

  List<Widget> _reviewStepBody(BuildContext context) => [
    Text(
      '${_photos.length} photo${_photos.length == 1 ? '' : 's'} ready for '
      'review.',
      style: V2Typography.bodySm(color: context.v2.fgMuted),
    ),
    const SizedBox(height: V2Spacing.space8),
    _PhotoThumbnailStrip(
      photos: _photos,
      enabled: !_submitting,
      onRemove: _removePhoto,
    ),
    const SizedBox(height: V2Spacing.space16),
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
            'Your account identifier, this barcode, and the label photos '
            'you selected are sent privately to PharmaGuide for review. '
            'Embedded photo metadata is removed. Your health profile, '
            'medications, conditions, allergies, and stack stay on this '
            'device.\n\nPhotograph only the product package. Do not include '
            'pharmacy labels, names, prescription numbers, or other '
            'personal information visible in the photo.',
            style: V2Typography.bodySm(color: context.v2.fg),
          ),
        ),
      ],
    ),
    CheckboxListTile(
      key: const Key('missing-product-consent'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: _consent,
      onChanged: _submitting
          ? null
          : (value) => setState(() {
              _consent = value ?? false;
              _failure = null;
            }),
      title: Text(
        'I consent to send my account identifier, this barcode, and the '
        'selected product-label photos to PharmaGuide for review.',
        style: V2Typography.bodySm(color: context.v2.fg),
      ),
    ),
    if (_failure != null) ...[
      const SizedBox(height: V2Spacing.space8),
      Semantics(
        liveRegion: true,
        child: Text(
          _failureCopy(_failure!),
          style: V2Typography.bodySm(color: context.v2.contraindicated),
        ),
      ),
    ],
    const SizedBox(height: V2Spacing.space16),
    SizedBox(
      height: 48,
      child: FilledButton(
        key: const Key('missing-product-submit'),
        onPressed: _canSubmit ? _submit : null,
        child: _submitting
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Submit'),
      ),
    ),
    if (_submitting && _phase != null) ...[
      const SizedBox(height: V2Spacing.space8),
      Center(
        child: Text(
          switch (_phase!) {
            ProductSubmissionPhase.savingReport => 'Saving your report…',
            ProductSubmissionPhase.uploadingPhotos =>
              'Uploading ${_photos.length} photo'
                  '${_photos.length == 1 ? '' : 's'}…',
            ProductSubmissionPhase.succeeded => 'Done',
            ProductSubmissionPhase.failed => 'Something went wrong',
          },
          style: V2Typography.caption(color: context.v2.fgMuted),
        ),
      ),
    ],
    const SizedBox(height: V2Spacing.space12),
    Text(
      'A reviewer must verify the label before anything can enter the '
      'PharmaGuide catalog.',
      textAlign: TextAlign.center,
      style: V2Typography.caption(color: context.v2.fgMuted),
    ),
  ];

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
    _CaptureStep.front => 'Front of the package',
    _CaptureStep.facts => 'Supplement Facts',
    _CaptureStep.ingredients => 'Other Ingredients',
    _CaptureStep.extras => 'Anything else?',
    _CaptureStep.review => 'Review & submit',
  };

  String _requiredCopy(_CaptureStep step) => switch (step) {
    _CaptureStep.front => 'Add at least one photo of the front label.',
    _CaptureStep.facts => 'Add at least one photo of the Supplement Facts '
        'panel.',
    _CaptureStep.ingredients => 'Add at least one photo of the Other '
        'Ingredients list.',
    _CaptureStep.extras || _CaptureStep.review => '',
  };
}

class _PhotoThumbnailStrip extends StatelessWidget {
  const _PhotoThumbnailStrip({
    required this.photos,
    required this.enabled,
    required this.onRemove,
  });

  final List<ProductSubmissionPhoto> photos;
  final bool enabled;
  final void Function(ProductSubmissionPhoto photo) onRemove;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return Container(
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: context.v2.outline),
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        ),
        child: Text(
          'No photo yet',
          style: V2Typography.caption(color: context.v2.fgSubtle),
        ),
      );
    }
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: V2Spacing.space8),
        itemBuilder: (context, index) {
          final photo = photos[index];
          return Stack(
            children: [
              Semantics(
                container: true,
                image: true,
                excludeSemantics: true,
                label: 'Captured label photo ${index + 1} preview',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                  child: Image.memory(
                    photo.bytes,
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 88,
                      height: 88,
                      color: context.v2.surfaceLow,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  key: Key('missing-product-remove-${photo.photoId}'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove photo',
                  onPressed: enabled ? () => onRemove(photo) : null,
                  icon: Icon(
                    Icons.cancel,
                    size: 20,
                    color: context.v2.fgMuted,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OptionalCategoryTile extends StatelessWidget {
  const _OptionalCategoryTile({
    required this.label,
    required this.category,
    required this.photos,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final String label;
  final ProductSubmissionEvidenceCategory category;
  final List<ProductSubmissionPhoto> photos;
  final bool enabled;
  final VoidCallback onAdd;
  final void Function(ProductSubmissionPhoto photo) onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space12),
      child: Container(
        padding: const EdgeInsets.all(V2Spacing.space12),
        decoration: BoxDecoration(
          border: Border.all(color: context.v2.outline),
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: V2Typography.bodyMedium(color: context.v2.fg),
                  ),
                ),
                TextButton(
                  key: Key('missing-product-add-${category.wireValue}'),
                  onPressed: enabled ? onAdd : null,
                  child: Text(photos.isEmpty ? 'Add' : 'Add another'),
                ),
              ],
            ),
            if (photos.isNotEmpty)
              _PhotoThumbnailStrip(
                photos: photos,
                enabled: enabled,
                onRemove: onRemove,
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(V2Spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: context.v2.safe),
            const SizedBox(height: V2Spacing.space16),
            Text(
              'Thanks — it’s in review',
              textAlign: TextAlign.center,
              style: V2Typography.title(color: context.v2.fg),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'A reviewer checks every label before it can enter the '
              'catalog. Track progress under Settings → Product '
              'submissions — we’ll also notify you.',
              textAlign: TextAlign.center,
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space24),
            SizedBox(
              height: 48,
              child: FilledButton(
                key: const Key('missing-product-done'),
                onPressed: onDone,
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmissionPhotoSourceSheet extends StatelessWidget {
  const _SubmissionPhotoSourceSheet({
    required this.onCamera,
    required this.onLibrary,
  });

  final VoidCallback onCamera;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('missing-product-source-camera'),
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            onTap: onCamera,
          ),
          ListTile(
            key: const Key('missing-product-source-library'),
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from library'),
            onTap: onLibrary,
          ),
          const SizedBox(height: V2Spacing.space8),
        ],
      ),
    );
  }
}
