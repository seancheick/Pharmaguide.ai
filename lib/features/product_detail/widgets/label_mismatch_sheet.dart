import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/services/product_submission_photo_service.dart';
import 'package:pharmaguide/services/product_submission_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef PickProductSubmissionPhoto =
    Future<ProductSubmissionPhoto?> Function(
      ProductSubmissionEvidenceCategory category,
      ImageSource source,
    );

/// Opens the structured, private label-mismatch flow.
///
/// Authentication, report submission, and image selection are injectable so
/// the sheet can be tested without platform channels or network calls.
Future<void> showLabelMismatchSheet(
  BuildContext context, {
  required LabelMismatchProductMetadata product,
  bool? isAuthenticated,
  ProductSubmissionService? reportService,
  PickProductSubmissionPhoto? pickPhoto,
  Future<void> Function()? onSignIn,
  String Function()? reportIdFactory,
}) async {
  final signedIn = isAuthenticated ?? _hasAuthenticatedUser();
  final picker = ImagePicker();
  final resolvedService =
      reportService ??
      (signedIn ? ProductSubmissionService.production() : null);

  await PGModal.bottomSheet<void>(
    context: context,
    builder: (sheetContext) => LabelMismatchSheet(
      product: product,
      isAuthenticated: signedIn,
      reportService: resolvedService,
      pickPhoto:
          pickPhoto ??
          (category, source) => pickProductSubmissionPhoto(
            picker: picker,
            categories: {category},
            source: source,
          ),
      reportIdFactory: reportIdFactory,
      onSignIn:
          onSignIn ??
          () async {
            Navigator.of(sheetContext).pop();
            if (context.mounted) {
              await context.push(Routes.authInvitation);
            }
          },
    ),
  );
}

class LabelMismatchSheet extends StatefulWidget {
  final LabelMismatchProductMetadata product;
  final bool isAuthenticated;
  final ProductSubmissionService? reportService;
  final PickProductSubmissionPhoto pickPhoto;
  final Future<void> Function() onSignIn;
  final String Function()? reportIdFactory;

  const LabelMismatchSheet({
    super.key,
    required this.product,
    required this.isAuthenticated,
    required this.reportService,
    required this.pickPhoto,
    required this.onSignIn,
    this.reportIdFactory,
  });

  @override
  State<LabelMismatchSheet> createState() => _LabelMismatchSheetState();
}

class _LabelMismatchSheetState extends State<LabelMismatchSheet> {
  final _categories = <LabelMismatchCategory>{};
  final _photos = <ProductSubmissionEvidenceCategory, ProductSubmissionPhoto>{};
  final _photoErrors = <ProductSubmissionEvidenceCategory, String>{};

  bool _consent = false;
  bool _submitting = false;
  bool _succeeded = false;
  ProductSubmissionPhase? _phase;
  ProductSubmissionFailure? _failure;
  LabelMismatchReportDraft? _draft;

  bool get _draftLocked => _draft != null;

  bool get _canSubmit =>
      _categories.isNotEmpty && _consent && !_submitting && !_succeeded;

  void _toggleCategory(LabelMismatchCategory category, bool selected) {
    if (_draftLocked) return;
    setState(() {
      if (selected) {
        _categories.add(category);
      } else {
        _categories.remove(category);
      }
      _invalidateDraft();
    });
  }

  void _invalidateDraft() {
    _draft = null;
    _failure = null;
    _phase = null;
  }

  Future<void> _choosePhoto(
    ProductSubmissionEvidenceCategory category,
    ImageSource source,
  ) async {
    if (_submitting || _succeeded || _draftLocked) return;
    setState(() => _photoErrors.remove(category));
    try {
      final photo = await widget.pickPhoto(category, source);
      if (!mounted || photo == null) return;
      if (!photo.categories.contains(category)) {
        setState(() {
          _photoErrors[category] =
              'That photo was assigned to the wrong label view.';
        });
        return;
      }
      setState(() {
        _photos[category] = photo;
        _invalidateDraft();
      });
    } on ProductSubmissionValidationException catch (error) {
      if (!mounted) return;
      setState(() => _photoErrors[category] = _photoValidationMessage(error));
    } on Object {
      if (!mounted) return;
      setState(() {
        _photoErrors[category] = source == ImageSource.camera
            ? 'We couldn’t open the camera. Try again.'
            : 'We couldn’t open the photo library. Try again.';
      });
    }
  }

  void _removePhoto(ProductSubmissionEvidenceCategory category) {
    if (_draftLocked) return;
    setState(() {
      _photos.remove(category);
      _photoErrors.remove(category);
      _invalidateDraft();
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final service = widget.reportService;
    if (service == null) {
      setState(() {
        _failure = ProductSubmissionFailure(
          submissionId: _draft?.submissionId ?? '',
          kind: ProductSubmissionFailureKind.authenticationRequired,
        );
      });
      return;
    }

    final draft =
        _draft ??
        LabelMismatchReportDraft.create(
          product: widget.product,
          categories: _categories,
          photos: [
            for (final category in _attachmentCategories)
              if (_photos[category] case final photo?) photo,
          ],
          reportIdFactory: widget.reportIdFactory,
        );
    _draft = draft;

    setState(() {
      _submitting = true;
      _failure = null;
      _phase = ProductSubmissionPhase.savingReport;
    });

    final result = await service.submit(
      draft,
      onPhaseChanged: (phase) {
        if (!mounted) return;
        setState(() => _phase = phase);
      },
    );
    if (!mounted) return;

    setState(() {
      _submitting = false;
      if (result is ProductSubmissionSuccess) {
        _succeeded = true;
        _failure = null;
        _phase = ProductSubmissionPhase.succeeded;
      } else {
        _failure = result as ProductSubmissionFailure;
        _phase = ProductSubmissionPhase.failed;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAuthenticated) {
      return _SignInGate(onSignIn: widget.onSignIn);
    }
    if (_succeeded) return const _SuccessState();

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: ListView(
          key: const Key('label-mismatch-scroll'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space8,
            V2Spacing.space24,
            V2Spacing.space32,
          ),
          children: [
            _SheetHeader(
              title: 'Report a label mismatch',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Tell us which catalog details differ from the package in '
              'your hand. Select only what you can verify on the label.',
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space16),
            const _PrivacyNotice(),
            const SizedBox(height: V2Spacing.space24),
            Semantics(
              header: true,
              child: Text(
                'What doesn’t match?',
                style: V2Typography.titleSm(color: context.v2.fg),
              ),
            ),
            const SizedBox(height: V2Spacing.space4),
            Text(
              'Select all that apply. No written notes are collected.',
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space8),
            for (final category in LabelMismatchCategory.values)
              CheckboxListTile(
                key: Key('label-mismatch-category-${category.wireValue}'),
                value: _categories.contains(category),
                onChanged: _submitting || _draftLocked
                    ? null
                    : (value) => _toggleCategory(category, value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                title: Text(
                  _categoryLabel(category),
                  style: V2Typography.body(color: context.v2.fg),
                ),
              ),
            const SizedBox(height: V2Spacing.space24),
            Semantics(
              header: true,
              child: Text(
                'Add label photos (optional)',
                style: V2Typography.titleSm(color: context.v2.fg),
              ),
            ),
            const SizedBox(height: V2Spacing.space4),
            Text(
              'Choose Camera or Photo library for each label view. '
              'PharmaGuide never opens either automatically.',
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space12),
            for (final category in _attachmentCategories) ...[
              _PhotoSlotCard(
                category: category,
                photo: _photos[category],
                error: _photoErrors[category],
                enabled: !_submitting && !_draftLocked,
                onChoose: (source) => _choosePhoto(category, source),
                onRemove: () => _removePhoto(category),
              ),
              if (category != _attachmentCategories.last)
                const SizedBox(height: V2Spacing.space12),
            ],
            const SizedBox(height: V2Spacing.space24),
            CheckboxListTile(
              key: const Key('label-mismatch-consent'),
              value: _consent,
              onChanged: _submitting || _draftLocked
                  ? null
                  : (value) => setState(() {
                      _consent = value ?? false;
                      _failure = null;
                    }),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'I consent to send this account-linked product report, its '
                'catalog identifiers, selected categories, and selected '
                'label photos to PharmaGuide for review.',
                style: V2Typography.bodySm(color: context.v2.fg),
              ),
            ),
            if (_submitting) ...[
              const SizedBox(height: V2Spacing.space12),
              _SubmissionProgress(phase: _phase),
            ],
            if (_failure case final failure?) ...[
              const SizedBox(height: V2Spacing.space12),
              _FailureNotice(failure: failure),
            ],
            const SizedBox(height: V2Spacing.space16),
            if (_failure?.kind ==
                ProductSubmissionFailureKind.authenticationRequired)
              PGPillButton(
                key: const Key('label-mismatch-sign-in-again'),
                label: 'Sign in to report a mismatch',
                icon: Icons.person_outline_rounded,
                expand: true,
                onPressed: widget.onSignIn,
              )
            else if (_failure?.retryable == true)
              PGPillButton(
                key: const Key('label-mismatch-retry'),
                label: 'Retry report',
                icon: Icons.refresh_rounded,
                expand: true,
                onPressed: _submitting ? null : _submit,
              )
            else
              PGPillButton(
                key: const Key('label-mismatch-submit'),
                label: _submitting ? 'Sending report…' : 'Send mismatch report',
                icon: Icons.send_outlined,
                expand: true,
                onPressed: _canSubmit ? _submit : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const _SheetHeader({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: V2Typography.title(color: context.v2.fg)),
          ),
        ),
        IconButton(
          tooltip: 'Close report form',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

class _SignInGate extends StatelessWidget {
  final Future<void> Function() onSignIn;

  const _SignInGate({required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space24,
          V2Spacing.space8,
          V2Spacing.space24,
          V2Spacing.space32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Close report form',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Icon(
              Icons.lock_outline_rounded,
              size: 40,
              color: context.v2.accent,
            ),
            const SizedBox(height: V2Spacing.space16),
            Semantics(
              header: true,
              child: Text(
                'Sign in to report a mismatch',
                textAlign: TextAlign.center,
                style: V2Typography.title(color: context.v2.fg),
              ),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Reports are tied to your account so your photos stay private '
              'and reviewers can investigate the correct catalog record.',
              textAlign: TextAlign.center,
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                key: const Key('label-mismatch-sign-in'),
                onPressed: onSignIn,
                icon: const Icon(Icons.person_outline_rounded),
                label: const Text('Sign in to report a mismatch'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          'Privacy. Your account identifier, this product’s catalog '
          'identifiers, selected mismatch categories, and selected '
          'product-label photos are sent. Embedded photo metadata is removed. '
          'Health profile data stays on this device.',
      child: Container(
        padding: const EdgeInsets.all(V2Spacing.space12),
        decoration: BoxDecoration(
          color: context.v2.accentTint,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.privacy_tip_outlined,
              size: 20,
              color: context.v2.accent,
            ),
            const SizedBox(width: V2Spacing.space12),
            Expanded(
              child: Text(
                'Your account identifier, this product’s catalog identifiers '
                '(including UPC when available), the mismatch categories you '
                'select, and selected product-label photos are sent. We remove '
                'embedded photo metadata before upload. Your profile, '
                'medications, conditions, allergies, and stack stay on this '
                'device.',
                style: V2Typography.bodySm(color: context.v2.fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoSlotCard extends StatelessWidget {
  final ProductSubmissionEvidenceCategory category;
  final ProductSubmissionPhoto? photo;
  final String? error;
  final bool enabled;
  final ValueChanged<ImageSource> onChoose;
  final VoidCallback onRemove;

  const _PhotoSlotCard({
    required this.category,
    required this.photo,
    required this.error,
    required this.enabled,
    required this.onChoose,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final label = _photoSlotLabel(category);
    final selected = photo != null;
    return Container(
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
              if (selected) ...[
                Semantics(
                  key: Key('label-mismatch-photo-${category.wireValue}-preview'),
                  container: true,
                  image: true,
                  excludeSemantics: true,
                  label: 'Selected $label photo preview',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                    child: Image.memory(
                      photo!.bytes,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.square(
                        dimension: 48,
                        child: Icon(Icons.image_outlined),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: V2Spacing.space8),
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: context.v2.safe,
                ),
                const SizedBox(width: V2Spacing.space4),
                Text(
                  'Photo selected',
                  style: V2Typography.caption(color: context.v2.safe),
                ),
                IconButton(
                  key: Key('label-mismatch-photo-${category.wireValue}-remove'),
                  tooltip: 'Remove $label photo',
                  onPressed: enabled ? onRemove : null,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ],
          ),
          const SizedBox(height: V2Spacing.space8),
          Wrap(
            spacing: V2Spacing.space8,
            runSpacing: V2Spacing.space8,
            children: [
              _PhotoSourceButton(
                key: Key('label-mismatch-photo-${category.wireValue}-camera'),
                semanticsLabel: 'Take $label photo with camera',
                icon: Icons.photo_camera_outlined,
                label: selected ? 'Retake' : 'Camera',
                onPressed: enabled ? () => onChoose(ImageSource.camera) : null,
              ),
              _PhotoSourceButton(
                key: Key('label-mismatch-photo-${category.wireValue}-gallery'),
                semanticsLabel: 'Choose $label photo from library',
                icon: Icons.photo_library_outlined,
                label: selected ? 'Replace from library' : 'Photo library',
                onPressed: enabled ? () => onChoose(ImageSource.gallery) : null,
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: V2Spacing.space8),
            Semantics(
              liveRegion: true,
              excludeSemantics: true,
              label: '$label photo error. $error',
              child: Text(
                error!,
                style: V2Typography.caption(color: context.v2.contraindicated),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhotoSourceButton extends StatelessWidget {
  final String semanticsLabel;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _PhotoSourceButton({
    super.key,
    required this.semanticsLabel,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticsLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          foregroundColor: context.v2.accent,
        ),
      ),
    );
  }
}

class _SubmissionProgress extends StatelessWidget {
  final ProductSubmissionPhase? phase;

  const _SubmissionProgress({required this.phase});

  @override
  Widget build(BuildContext context) {
    final label = phase == ProductSubmissionPhase.uploadingPhotos
        ? 'Uploading selected photos…'
        : 'Saving report…';
    return Semantics(
      liveRegion: true,
      excludeSemantics: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: V2Typography.bodySm(color: context.v2.fg)),
          const SizedBox(height: V2Spacing.space8),
          const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

class _FailureNotice extends StatelessWidget {
  final ProductSubmissionFailure failure;

  const _FailureNotice({required this.failure});

  @override
  Widget build(BuildContext context) {
    final message = switch (failure.kind) {
      ProductSubmissionFailureKind.authenticationRequired =>
        'Your session ended. Sign in again to send this report.',
      ProductSubmissionFailureKind.photoUploadFailed =>
        'We couldn’t confirm all selected photos were uploaded. Retry this '
            'same report.',
      ProductSubmissionFailureKind.reportInsertFailed =>
        'We couldn’t confirm the report was saved. Retry this same report. '
            'Nothing changes in the catalog automatically.',
      ProductSubmissionFailureKind.reportFinalizeFailed =>
        'We couldn’t confirm the report was finalized. Retry this same report. '
            'Nothing changes in the catalog automatically.',
    };
    final style = context.v2.tintedLabel(context.v2.contraindicated);
    return Semantics(
      liveRegion: true,
      excludeSemantics: true,
      label: 'Report error. $message',
      child: Container(
        padding: const EdgeInsets.all(V2Spacing.space12),
        decoration: BoxDecoration(
          color: style.fill,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: V2Typography.bodySm(color: style.foreground)),
          ],
        ),
      ),
    );
  }
}

class _SuccessState extends StatelessWidget {
  const _SuccessState();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Semantics(
        liveRegion: true,
        excludeSemantics: true,
        label:
            'Report sent. Your report does not change the catalog '
            'automatically.',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space32,
            V2Spacing.space24,
            V2Spacing.space32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 48,
                color: context.v2.safe,
              ),
              const SizedBox(height: V2Spacing.space16),
              Text(
                'Report sent',
                style: V2Typography.title(color: context.v2.fg),
              ),
              const SizedBox(height: V2Spacing.space8),
              Text(
                'Thanks. We’ll review the catalog record. Your report does '
                'not change the catalog automatically.',
                textAlign: TextAlign.center,
                style: V2Typography.bodySm(color: context.v2.fgMuted),
              ),
              const SizedBox(height: V2Spacing.space24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _hasAuthenticatedUser() {
  try {
    return Supabase.instance.client.auth.currentUser != null;
  } on Object {
    return false;
  }
}

String _photoValidationMessage(ProductSubmissionValidationException error) {
  return switch (error.reason) {
    ProductSubmissionValidationFailure.emptyPhoto =>
      'That image is empty. Choose another.',
    ProductSubmissionValidationFailure.photoTooLarge =>
      'Photo must be 15 MB or smaller.',
    ProductSubmissionValidationFailure.unsupportedPhotoContentType =>
      'Use a JPEG, PNG, HEIC, HEIF, or WebP image.',
    ProductSubmissionValidationFailure.photoSanitizationFailed =>
      'We couldn’t remove embedded photo metadata. Choose another image.',
    _ => 'We couldn’t use that photo. Choose another.',
  };
}

String _categoryLabel(LabelMismatchCategory category) => switch (category) {
  LabelMismatchCategory.productIdentity => 'Product identity',
  LabelMismatchCategory.ingredientMissing => 'Ingredient missing from the app',
  LabelMismatchCategory.ingredientExtra =>
    'Ingredient shown in the app but not on the label',
  LabelMismatchCategory.amountOrUnit => 'Amount or unit',
  LabelMismatchCategory.formOrParenthetical =>
    'Form or parenthetical label detail',
  LabelMismatchCategory.servingSizeOrDirections => 'Serving size or directions',
  LabelMismatchCategory.otherIngredients => 'Other Ingredients list',
  LabelMismatchCategory.catalogVersionOrStatus =>
    'Catalog version or product status',
};

/// The three label views a correction may attach, in display order.
const _attachmentCategories = <ProductSubmissionEvidenceCategory>[
  ProductSubmissionEvidenceCategory.frontIdentity,
  ProductSubmissionEvidenceCategory.supplementFacts,
  ProductSubmissionEvidenceCategory.ingredientDisclosure,
];

String _photoSlotLabel(ProductSubmissionEvidenceCategory category) =>
    switch (category) {
      ProductSubmissionEvidenceCategory.frontIdentity => 'Front of bottle',
      ProductSubmissionEvidenceCategory.supplementFacts => 'Supplement Facts',
      ProductSubmissionEvidenceCategory.ingredientDisclosure =>
        'Other Ingredients',
      _ => 'Label detail',
    };
