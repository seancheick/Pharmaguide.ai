import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_progress_dots.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/services/gtin.dart';
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
///
/// Capture is camera-first: the shutter goes straight to the system camera
/// (its native confirm is the per-shot confirm), and a quiet link offers
/// the photo library for shots taken earlier.
Future<bool> showMissingProductSubmissionSheet(
  BuildContext context, {
  required String upc,
  ProductSubmissionService? service,
  PickMissingProductPhoto? pickPhoto,
  PickMissingProductPhoto? pickPhotoFromLibrary,
  EvaluatePhotoQuality? qualityGate,
  String Function()? submissionIdFactory,
  String? resubmissionOf,
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
      service: service ?? ProductSubmissionService.production(),
      submissionIdFactory: submissionIdFactory,
      resubmissionOf: resubmissionOf,
      qualityGate:
          qualityGate ?? (photo) => PhotoQualityGate.evaluate(photo.bytes),
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
/// after the facts shot — never a checkbox that could invalidate work).
enum _CaptureStep { intro, front, facts, ingredients, extras, review }

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
    this.pickPhotoFromLibrary,
    this.submissionIdFactory,
    this.resubmissionOf,
  });

  final String upc;
  final ProductSubmissionService service;
  final PickMissingProductPhoto pickPhoto;
  final PickMissingProductPhoto? pickPhotoFromLibrary;
  final EvaluatePhotoQuality qualityGate;
  final String Function()? submissionIdFactory;
  final String? resubmissionOf;

  @override
  State<MissingProductSubmissionSheet> createState() =>
      _MissingProductSubmissionSheetState();
}

class _MissingProductSubmissionSheetState
    extends State<MissingProductSubmissionSheet> {
  final List<ProductSubmissionPhoto> _photos = [];
  _CaptureStep _step = _CaptureStep.intro;
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
    _CaptureStep.intro,
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
        _CaptureStep.intro ||
        _CaptureStep.extras ||
        _CaptureStep.review => const <ProductSubmissionEvidenceCategory>{},
      };

  bool get _stepSatisfied => switch (_step) {
    _CaptureStep.front => _photosTagged(
      ProductSubmissionEvidenceCategory.frontIdentity,
    ).isNotEmpty,
    _CaptureStep.facts => _photosTagged(
      ProductSubmissionEvidenceCategory.supplementFacts,
    ).isNotEmpty,
    _CaptureStep.ingredients => _photosTagged(
      ProductSubmissionEvidenceCategory.ingredientDisclosure,
    ).isNotEmpty,
    _CaptureStep.intro || _CaptureStep.extras || _CaptureStep.review => true,
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

  /// Camera-first capture. On a required step the flow advances by itself
  /// after a passing shot — confirming in the system camera IS the
  /// confirmation, so no extra Next tap is asked for.
  Future<void> _addPhoto(
    Set<ProductSubmissionEvidenceCategory> categories, {
    bool fromLibrary = false,
    bool autoAdvance = false,
  }) async {
    if (_submitting || _adding) return;
    if (_photos.length >= ProductSubmissionPhoto.maxPerSubmission) {
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
    setState(() {
      _adding = true;
      _stepError = null;
      _failure = null;
    });
    try {
      final photo = await pick(categories);
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
      if (autoAdvance) await _advanceAfterCapture();
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

  /// The one flow fork. Right after the facts shot the user answers where
  /// the "Other Ingredients" list lives — a one-tap question that RE-TAGS
  /// the capture they just took (never deletes it) and decides whether the
  /// ingredients step exists at all.
  Future<void> _advanceAfterCapture() async {
    if (_step == _CaptureStep.facts && !_factsCarriesIngredients) {
      final combined = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('One quick check'),
          content: const Text(
            'Is the “Other Ingredients” list part of the panel you just '
            'photographed?',
          ),
          actions: [
            TextButton(
              key: const Key('missing-product-facts-separate'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('It’s separate'),
            ),
            FilledButton(
              key: const Key('missing-product-facts-combined'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('It’s on this panel'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (combined == true) _setFactsCoversIngredients(true);
    }
    _goForward();
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

  void _removePhoto(ProductSubmissionPhoto photo) {
    if (_submitting) return;
    setState(() {
      _photos.remove(photo);
      _draft = null;
      _stepError = null;
      _failure = null;
    });
  }

  /// Applies the combined-panel answer by re-tagging facts captures in
  /// place. Existing shots gain or lose the ingredient tag; standalone
  /// ingredient-step captures are left untouched. Nothing is ever deleted
  /// by answering a question.
  void _setFactsCoversIngredients(bool value, {_CaptureStep? nextStep}) {
    if (_submitting) return;
    setState(() {
      _factsCarriesIngredients = value;
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
            resubmissionOf: widget.resubmissionOf,
            submissionIdFactory: widget.submissionIdFactory,
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
            'For barcode ${widget.upc.replaceAll(RegExp(r'[^0-9]'), '')}',
            style: V2Typography.monoData(color: context.v2.fgMuted),
          ),
          if (_step != _CaptureStep.intro) ...[
            const SizedBox(height: V2Spacing.space12),
            Center(
              child: PGProgressDots(
                total: steps.length - 1,
                current: stepIndex - 1,
              ),
            ),
          ],
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
              if (stepIndex > 1)
                TextButton(
                  key: const Key('missing-product-back'),
                  onPressed: _submitting ? null : _goBack,
                  child: const Text('Back'),
                ),
              const Spacer(),
              // Forward is normally automatic (each passing shot advances);
              // the button remains for revisits and the optional-extras
              // step, where there is nothing to auto-advance on.
              if (_step != _CaptureStep.intro &&
                  _step != _CaptureStep.review &&
                  _stepSatisfied)
                FilledButton(
                  key: const Key('missing-product-next'),
                  onPressed: _submitting || _adding ? null : _goForward,
                  child: Text(
                    _step == _CaptureStep.extras ? 'Review photos' : 'Continue',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStep(BuildContext context) => switch (_step) {
    _CaptureStep.intro => _introStepBody(context),
    _CaptureStep.front => _captureStepBody(
      context,
      guidance: 'Photograph the front of the package.',
      tip: 'Fill the frame so the brand and product name are readable.',
      category: ProductSubmissionEvidenceCategory.frontIdentity,
    ),
    _CaptureStep.facts => [
      ..._captureStepBody(
        context,
        guidance: 'Photograph the whole Supplement Facts panel.',
        tip:
            'Straight on, no glare. Panel wraps around the bottle? Add a '
            'second angle after the first shot.',
        category: ProductSubmissionEvidenceCategory.supplementFacts,
      ),
      const SizedBox(height: V2Spacing.space8),
      Center(
        child: TextButton(
          key: const Key('missing-product-no-facts-link'),
          onPressed: _submitting || _adding ? null : _showNoFactsPanelDeadEnd,
          child: Text(
            'Can’t find a Supplement Facts panel?',
            style: V2Typography.bodySm(color: context.v2.fgMuted),
          ),
        ),
      ),
    ],
    _CaptureStep.ingredients => _captureStepBody(
      context,
      guidance: 'Photograph the “Other Ingredients” list.',
      tip:
          'Usually right below the Supplement Facts panel. Every '
          'ingredient matters for safety checks.',
      category: ProductSubmissionEvidenceCategory.ingredientDisclosure,
    ),
    _CaptureStep.extras => [
      Text(
        'Optional — these help reviewers verify dosing and freshness. '
        'Skip any you like.',
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

  List<Widget> _introStepBody(BuildContext context) {
    Widget chip(String label, {required bool required}) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space12,
        vertical: V2Spacing.space4,
      ),
      decoration: BoxDecoration(
        color: required ? context.v2.accentTint : Colors.transparent,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        border: Border.all(
          color: required ? context.v2.accent : context.v2.outline,
        ),
      ),
      child: Text(
        label,
        style: V2Typography.caption(
          color: required ? context.v2.accentStrong : context.v2.fgMuted,
        ),
      ),
    );

    return [
      Text(
        'A few clear photos add this product for everyone. Snap each one; '
        'the flow moves forward on its own.',
        style: V2Typography.bodySm(color: context.v2.fgMuted),
      ),
      const SizedBox(height: V2Spacing.space12),
      Wrap(
        spacing: V2Spacing.space8,
        runSpacing: V2Spacing.space8,
        children: [
          chip('Front label', required: true),
          chip('Supplement Facts', required: true),
          chip('Other Ingredients', required: true),
          chip('Warnings', required: false),
          chip('Barcode', required: false),
          chip('Lot & expiry', required: false),
        ],
      ),
      const SizedBox(height: V2Spacing.space16),
      Text(
        'Photos go privately to a human reviewer — clear shots get your '
        'product added faster.',
        style: V2Typography.caption(color: context.v2.fgSubtle),
      ),
      const SizedBox(height: V2Spacing.space16),
      SizedBox(
        height: 48,
        child: FilledButton.icon(
          key: const Key('missing-product-start'),
          onPressed: _goForward,
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Start with the front label'),
        ),
      ),
    ];
  }

  List<Widget> _captureStepBody(
    BuildContext context, {
    required String guidance,
    required String tip,
    required ProductSubmissionEvidenceCategory category,
  }) {
    final photos = _photosTagged(category);
    return [
      Text(guidance, style: V2Typography.bodyMedium(color: context.v2.fg)),
      const SizedBox(height: V2Spacing.space4),
      Text(tip, style: V2Typography.bodySm(color: context.v2.fgMuted)),
      const SizedBox(height: V2Spacing.space12),
      if (photos.isNotEmpty) ...[
        _PhotoThumbnailStrip(
          photos: photos,
          enabled: !_submitting,
          onRemove: _removePhoto,
        ),
        const SizedBox(height: V2Spacing.space8),
      ],
      SizedBox(
        height: 48,
        child: FilledButton.icon(
          key: Key('missing-product-add-${category.wireValue}'),
          onPressed: _submitting || _adding
              ? null
              : () => _addPhoto(_stepCategories(_step), autoAdvance: true),
          icon: const Icon(Icons.photo_camera_outlined, size: 20),
          label: Text(photos.isEmpty ? 'Open camera' : 'Add another angle'),
        ),
      ),
      const SizedBox(height: V2Spacing.space4),
      Center(
        child: TextButton(
          key: Key('missing-product-library-${category.wireValue}'),
          onPressed: _submitting || _adding
              ? null
              : () => _addPhoto(
                  _stepCategories(_step),
                  fromLibrary: true,
                  autoAdvance: true,
                ),
          child: Text(
            'Choose from library instead',
            style: V2Typography.caption(color: context.v2.fgSubtle),
          ),
        ),
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
    if (_factsCarriesIngredients) ...[
      const SizedBox(height: V2Spacing.space8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(V2Spacing.space12),
        decoration: BoxDecoration(
          color: context.v2.surfaceLow,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: context.v2.outline),
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
                    ),
              child: const Text('They’re on a separate panel'),
            ),
          ],
        ),
      ),
    ],
    const SizedBox(height: V2Spacing.space8),
    Center(
      child: TextButton(
        key: const Key('missing-product-wrong-barcode'),
        onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
        child: Text(
          'Not the product you scanned? Cancel and rescan.',
          style: V2Typography.caption(color: context.v2.fgSubtle),
        ),
      ),
    ),
    const SizedBox(height: V2Spacing.space8),
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
        child: Text(switch (_phase!) {
          ProductSubmissionPhase.savingReport => 'Saving your report…',
          ProductSubmissionPhase.uploadingPhotos =>
            'Uploading ${_photos.length} photo'
                '${_photos.length == 1 ? '' : 's'}…',
          ProductSubmissionPhase.succeeded => 'Done',
          ProductSubmissionPhase.failed => 'Something went wrong',
        }, style: V2Typography.caption(color: context.v2.fgMuted)),
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
    _CaptureStep.intro => 'Add this product',
    _CaptureStep.front => 'Front of the package',
    _CaptureStep.facts => 'Supplement Facts',
    _CaptureStep.ingredients => 'Other Ingredients',
    _CaptureStep.extras => 'Anything else?',
    _CaptureStep.review => 'Review & submit',
  };

  String _requiredCopy(_CaptureStep step) => switch (step) {
    _CaptureStep.front => 'Add at least one photo of the front label.',
    _CaptureStep.facts =>
      'Add at least one photo of the Supplement Facts '
          'panel.',
    _CaptureStep.ingredients =>
      'Add at least one photo of the Other '
          'Ingredients list.',
    _CaptureStep.intro || _CaptureStep.extras || _CaptureStep.review => '',
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
                  icon: Icon(Icons.cancel, size: 20, color: context.v2.fgMuted),
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
