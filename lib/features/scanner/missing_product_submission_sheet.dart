import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/services/product_submission_photo_service.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

typedef PickMissingProductPhoto =
    Future<ProductSubmissionPhoto?> Function(ProductSubmissionPhotoSlot slot);

/// Opens the one production intake flow used by camera and manual barcode
/// misses. Authentication remains a caller decision so the helper never
/// guesses whether to redirect or silently drop a submission attempt.
Future<bool> showMissingProductSubmissionSheet(
  BuildContext context, {
  required String upc,
  ProductSubmissionService? service,
  PickMissingProductPhoto? pickPhoto,
}) async {
  final picker = ImagePicker();
  final submitted = await PGModal.bottomSheet<bool>(
    context: context,
    builder: (sheetContext) => MissingProductSubmissionSheet(
      upc: upc,
      service: service ?? ProductSubmissionService.production(),
      pickPhoto:
          pickPhoto ??
          (slot) async {
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
              slot: slot,
              source: source,
            );
          },
    ),
  );
  return submitted == true;
}

/// Private, structured evidence intake for a barcode the catalog cannot match.
///
/// There is deliberately no narrative field. The photos, barcode, and one
/// closed "no Other Ingredients panel" assertion are the entire user payload.
class MissingProductSubmissionSheet extends StatefulWidget {
  const MissingProductSubmissionSheet({
    super.key,
    required this.upc,
    required this.service,
    required this.pickPhoto,
    this.submissionIdFactory,
  });

  final String upc;
  final ProductSubmissionService service;
  final PickMissingProductPhoto pickPhoto;
  final String Function()? submissionIdFactory;

  @override
  State<MissingProductSubmissionSheet> createState() =>
      _MissingProductSubmissionSheetState();
}

class _MissingProductSubmissionSheetState
    extends State<MissingProductSubmissionSheet> {
  final Map<ProductSubmissionPhotoSlot, ProductSubmissionPhoto> _photos = {};
  bool _otherIngredientsNotPresent = false;
  bool _consent = false;
  bool _submitting = false;
  bool _submitted = false;
  String? _photoError;
  ProductSubmissionFailure? _failure;
  MissingProductSubmissionDraft? _draft;

  bool get _hasRequiredEvidence =>
      _photos.containsKey(ProductSubmissionPhotoSlot.front) &&
      _photos.containsKey(ProductSubmissionPhotoSlot.supplementFacts) &&
      (_photos.containsKey(ProductSubmissionPhotoSlot.otherIngredients) ||
          _otherIngredientsNotPresent);

  Future<void> _pick(ProductSubmissionPhotoSlot slot) async {
    if (_submitting) return;
    try {
      final photo = await widget.pickPhoto(slot);
      if (!mounted || photo == null) return;
      if (photo.slot != slot) {
        throw const ProductSubmissionValidationException(
          ProductSubmissionValidationFailure.invalidMetadataValue,
        );
      }
      setState(() {
        _photos[slot] = photo;
        if (slot == ProductSubmissionPhotoSlot.otherIngredients) {
          _otherIngredientsNotPresent = false;
        }
        _draft = null;
        _photoError = null;
        _failure = null;
      });
    } on ProductSubmissionValidationException {
      if (!mounted) return;
      setState(() {
        _photoError =
            'That photo could not be prepared. Choose a clear JPG, PNG, '
            'HEIC, or WebP image under 15 MB.';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _photoError = 'We couldn’t open that photo. Please try again.';
      });
    }
  }

  void _setOtherIngredientsAbsent(bool? value) {
    if (_submitting) return;
    setState(() {
      _otherIngredientsNotPresent = value ?? false;
      if (_otherIngredientsNotPresent) {
        _photos.remove(ProductSubmissionPhotoSlot.otherIngredients);
      }
      _draft = null;
      _photoError = null;
      _failure = null;
    });
  }

  Future<void> _submit() async {
    if (!_hasRequiredEvidence || !_consent || _submitting) return;
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
            photos: _photos.values.toList(growable: false),
            otherIngredientsNotPresent: _otherIngredientsNotPresent,
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

    final result = await widget.service.submit(draft);
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
            'Help add this product',
            style: V2Typography.title(color: V2Colors.fg),
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'UPC ${widget.upc.replaceAll(RegExp(r'[^0-9]'), '')}',
            style: V2Typography.monoData(color: V2Colors.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space16),
          Container(
            padding: const EdgeInsets.all(V2Spacing.space16),
            decoration: BoxDecoration(
              color: V2Colors.cautionTint,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            ),
            child: Text(
              'Your account identifier, this barcode, and the label photos '
              'you select are sent privately to PharmaGuide for review. '
              'Embedded photo metadata is removed. Your health profile, '
              'medications, conditions, allergies, and stack stay on this '
              'device.\n\nPhotograph only the product package. Do not include '
              'pharmacy labels, names, prescription numbers, or other '
              'personal information visible in the photo.',
              style: V2Typography.bodySm(color: V2Colors.fg),
            ),
          ),
          const SizedBox(height: V2Spacing.space24),
          _PhotoRow(
            label: 'Front label',
            required: true,
            added: _photos.containsKey(ProductSubmissionPhotoSlot.front),
            enabled: !_submitting,
            onTap: () => _pick(ProductSubmissionPhotoSlot.front),
          ),
          _PhotoRow(
            label: 'Supplement Facts',
            required: true,
            added: _photos.containsKey(
              ProductSubmissionPhotoSlot.supplementFacts,
            ),
            enabled: !_submitting,
            onTap: () => _pick(ProductSubmissionPhotoSlot.supplementFacts),
          ),
          _PhotoRow(
            label: 'Other Ingredients',
            required: !_otherIngredientsNotPresent,
            added: _photos.containsKey(
              ProductSubmissionPhotoSlot.otherIngredients,
            ),
            enabled: !_submitting,
            onTap: () => _pick(ProductSubmissionPhotoSlot.otherIngredients),
          ),
          CheckboxListTile(
            key: const Key('missing-product-other-ingredients-absent'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _otherIngredientsNotPresent,
            onChanged: _submitting ? null : _setOtherIngredientsAbsent,
            title: Text(
              'No Other Ingredients panel on this label',
              style: V2Typography.bodySm(color: V2Colors.fg),
            ),
          ),
          if (_photoError != null) ...[
            const SizedBox(height: V2Spacing.space8),
            Semantics(
              liveRegion: true,
              child: Text(
                _photoError!,
                style: V2Typography.bodySm(color: V2Colors.contraindicated),
              ),
            ),
          ],
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
              'I consent to send my account identifier, this barcode, and '
              'the selected product-label photos to PharmaGuide for review.',
              style: V2Typography.bodySm(color: V2Colors.fg),
            ),
          ),
          if (_failure != null) ...[
            const SizedBox(height: V2Spacing.space8),
            Semantics(
              liveRegion: true,
              child: Text(
                _failure!.kind ==
                        ProductSubmissionFailureKind.authenticationRequired
                    ? 'Sign in before submitting product photos.'
                    : 'Could not submit this product. Your selected photos '
                          'remain here so you can try again.',
                style: V2Typography.bodySm(color: V2Colors.contraindicated),
              ),
            ),
          ],
          const SizedBox(height: V2Spacing.space16),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const Key('missing-product-submit'),
              onPressed: _hasRequiredEvidence && _consent && !_submitting
                  ? _submit
                  : null,
              child: _submitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit'),
            ),
          ),
          const SizedBox(height: V2Spacing.space12),
          Text(
            'A reviewer must verify the label before anything can enter the '
            'PharmaGuide catalog.',
            textAlign: TextAlign.center,
            style: V2Typography.caption(color: V2Colors.fgMuted),
          ),
        ],
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.label,
    required this.required,
    required this.added,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool required;
  final bool added;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: V2Typography.body(color: V2Colors.fg)),
      subtitle: Text(
        added ? 'Photo added' : (required ? 'Required' : 'Optional'),
        style: V2Typography.caption(
          color: added ? V2Colors.safe : V2Colors.fgMuted,
        ),
      ),
      trailing: Icon(
        added ? Icons.check_circle_outline : Icons.add_a_photo_outlined,
        color: added ? V2Colors.safe : V2Colors.accent,
      ),
      onTap: enabled ? onTap : null,
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
          children: [
            const Icon(Icons.task_alt_rounded, color: V2Colors.safe, size: 48),
            const SizedBox(height: V2Spacing.space16),
            Text(
              'Submitted for review',
              style: V2Typography.title(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'We’ll show the status in Profile. Submission does not add the '
              'product automatically.',
              textAlign: TextAlign.center,
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(onPressed: onDone, child: const Text('Done')),
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space24,
          V2Spacing.space8,
          V2Spacing.space24,
          V2Spacing.space24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Add product photo',
              style: V2Typography.titleSm(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space16),
            PGPillButton(
              label: 'Take photo',
              icon: Icons.photo_camera_outlined,
              expand: true,
              onPressed: onCamera,
            ),
            const SizedBox(height: V2Spacing.space12),
            PGPillButton(
              label: 'Choose from library',
              icon: Icons.photo_library_outlined,
              variant: PGPillVariant.secondary,
              expand: true,
              onPressed: onLibrary,
            ),
          ],
        ),
      ),
    );
  }
}
