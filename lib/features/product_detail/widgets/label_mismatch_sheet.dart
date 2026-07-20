import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/services/label_mismatch_report_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef PickLabelMismatchPhoto =
    Future<LabelMismatchPhoto?> Function(
      LabelMismatchPhotoSlot slot,
      ImageSource source,
    );

typedef SanitizeLabelMismatchPhoto =
    Future<Uint8List> Function(Uint8List sourceBytes);

/// Opens the structured, private label-mismatch flow.
///
/// Authentication, report submission, and image selection are injectable so
/// the sheet can be tested without platform channels or network calls.
Future<void> showLabelMismatchSheet(
  BuildContext context, {
  required LabelMismatchProductMetadata product,
  bool? isAuthenticated,
  LabelMismatchReportService? reportService,
  PickLabelMismatchPhoto? pickPhoto,
  Future<void> Function()? onSignIn,
  String Function()? reportIdFactory,
}) async {
  final signedIn = isAuthenticated ?? _hasAuthenticatedUser();
  final picker = ImagePicker();
  final resolvedService =
      reportService ??
      (signedIn ? LabelMismatchReportService.production() : null);

  await PGModal.bottomSheet<void>(
    context: context,
    builder: (sheetContext) => LabelMismatchSheet(
      product: product,
      isAuthenticated: signedIn,
      reportService: resolvedService,
      pickPhoto:
          pickPhoto ??
          (slot, source) => _pickProductLabelPhoto(
            picker: picker,
            slot: slot,
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
  final LabelMismatchReportService? reportService;
  final PickLabelMismatchPhoto pickPhoto;
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
  final _photos = <LabelMismatchPhotoSlot, LabelMismatchPhoto>{};
  final _photoErrors = <LabelMismatchPhotoSlot, String>{};

  bool _consent = false;
  bool _submitting = false;
  bool _succeeded = false;
  LabelMismatchSubmissionPhase? _phase;
  LabelMismatchSubmissionFailure? _failure;
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
    LabelMismatchPhotoSlot slot,
    ImageSource source,
  ) async {
    if (_submitting || _succeeded || _draftLocked) return;
    setState(() => _photoErrors.remove(slot));
    try {
      final photo = await widget.pickPhoto(slot, source);
      if (!mounted || photo == null) return;
      if (photo.slot != slot) {
        setState(() {
          _photoErrors[slot] = 'That photo was assigned to the wrong slot.';
        });
        return;
      }
      setState(() {
        _photos[slot] = photo;
        _invalidateDraft();
      });
    } on LabelMismatchValidationException catch (error) {
      if (!mounted) return;
      setState(() => _photoErrors[slot] = _photoValidationMessage(error));
    } on Object {
      if (!mounted) return;
      setState(() {
        _photoErrors[slot] = source == ImageSource.camera
            ? 'We couldn’t open the camera. Try again.'
            : 'We couldn’t open the photo library. Try again.';
      });
    }
  }

  void _removePhoto(LabelMismatchPhotoSlot slot) {
    if (_draftLocked) return;
    setState(() {
      _photos.remove(slot);
      _photoErrors.remove(slot);
      _invalidateDraft();
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final service = widget.reportService;
    if (service == null) {
      setState(() {
        _failure = LabelMismatchSubmissionFailure(
          reportId: _draft?.reportId ?? '',
          kind: LabelMismatchFailureKind.authenticationRequired,
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
            for (final slot in LabelMismatchPhotoSlot.values)
              if (_photos[slot] case final photo?) photo,
          ],
          reportIdFactory: widget.reportIdFactory,
        );
    _draft = draft;

    setState(() {
      _submitting = true;
      _failure = null;
      _phase = LabelMismatchSubmissionPhase.savingReport;
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
      if (result is LabelMismatchSubmissionSuccess) {
        _succeeded = true;
        _failure = null;
        _phase = LabelMismatchSubmissionPhase.succeeded;
      } else {
        _failure = result as LabelMismatchSubmissionFailure;
        _phase = LabelMismatchSubmissionPhase.failed;
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
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space16),
            const _PrivacyNotice(),
            const SizedBox(height: V2Spacing.space24),
            Semantics(
              header: true,
              child: Text(
                'What doesn’t match?',
                style: V2Typography.titleSm(color: V2Colors.fg),
              ),
            ),
            const SizedBox(height: V2Spacing.space4),
            Text(
              'Select all that apply. No written notes are collected.',
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
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
                  style: V2Typography.body(color: V2Colors.fg),
                ),
              ),
            const SizedBox(height: V2Spacing.space24),
            Semantics(
              header: true,
              child: Text(
                'Add label photos (optional)',
                style: V2Typography.titleSm(color: V2Colors.fg),
              ),
            ),
            const SizedBox(height: V2Spacing.space4),
            Text(
              'Choose Camera or Photo library for each label view. '
              'PharmaGuide never opens either automatically.',
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space12),
            for (final slot in LabelMismatchPhotoSlot.values) ...[
              _PhotoSlotCard(
                slot: slot,
                photo: _photos[slot],
                error: _photoErrors[slot],
                enabled: !_submitting && !_draftLocked,
                onChoose: (source) => _choosePhoto(slot, source),
                onRemove: () => _removePhoto(slot),
              ),
              if (slot != LabelMismatchPhotoSlot.values.last)
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
                style: V2Typography.bodySm(color: V2Colors.fg),
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
                LabelMismatchFailureKind.authenticationRequired)
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
            child: Text(title, style: V2Typography.title(color: V2Colors.fg)),
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
            const Icon(
              Icons.lock_outline_rounded,
              size: 40,
              color: V2Colors.accent,
            ),
            const SizedBox(height: V2Spacing.space16),
            Semantics(
              header: true,
              child: Text(
                'Sign in to report a mismatch',
                textAlign: TextAlign.center,
                style: V2Typography.title(color: V2Colors.fg),
              ),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Reports are tied to your account so your photos stay private '
              'and reviewers can investigate the correct catalog record.',
              textAlign: TextAlign.center,
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
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
          color: V2Colors.accentTint,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.privacy_tip_outlined,
              size: 20,
              color: V2Colors.accent,
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
                style: V2Typography.bodySm(color: V2Colors.fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoSlotCard extends StatelessWidget {
  final LabelMismatchPhotoSlot slot;
  final LabelMismatchPhoto? photo;
  final String? error;
  final bool enabled;
  final ValueChanged<ImageSource> onChoose;
  final VoidCallback onRemove;

  const _PhotoSlotCard({
    required this.slot,
    required this.photo,
    required this.error,
    required this.enabled,
    required this.onChoose,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final label = _photoSlotLabel(slot);
    final selected = photo != null;
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space12),
      decoration: BoxDecoration(
        border: Border.all(color: V2Colors.outline),
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
                  style: V2Typography.bodyMedium(color: V2Colors.fg),
                ),
              ),
              if (selected) ...[
                Semantics(
                  key: Key('label-mismatch-photo-${slot.wireValue}-preview'),
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
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: V2Colors.safe,
                ),
                const SizedBox(width: V2Spacing.space4),
                Text(
                  'Photo selected',
                  style: V2Typography.caption(color: V2Colors.safe),
                ),
                IconButton(
                  key: Key('label-mismatch-photo-${slot.wireValue}-remove'),
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
                key: Key('label-mismatch-photo-${slot.wireValue}-camera'),
                semanticsLabel: 'Take $label photo with camera',
                icon: Icons.photo_camera_outlined,
                label: selected ? 'Retake' : 'Camera',
                onPressed: enabled ? () => onChoose(ImageSource.camera) : null,
              ),
              _PhotoSourceButton(
                key: Key('label-mismatch-photo-${slot.wireValue}-gallery'),
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
                style: V2Typography.caption(color: V2Colors.contraindicated),
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
          foregroundColor: V2Colors.accent,
        ),
      ),
    );
  }
}

class _SubmissionProgress extends StatelessWidget {
  final LabelMismatchSubmissionPhase? phase;

  const _SubmissionProgress({required this.phase});

  @override
  Widget build(BuildContext context) {
    final label = phase == LabelMismatchSubmissionPhase.uploadingPhotos
        ? 'Uploading selected photos…'
        : 'Saving report…';
    return Semantics(
      liveRegion: true,
      excludeSemantics: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: V2Typography.bodySm(color: V2Colors.fg)),
          const SizedBox(height: V2Spacing.space8),
          const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

class _FailureNotice extends StatelessWidget {
  final LabelMismatchSubmissionFailure failure;

  const _FailureNotice({required this.failure});

  @override
  Widget build(BuildContext context) {
    final message = switch (failure.kind) {
      LabelMismatchFailureKind.authenticationRequired =>
        'Your session ended. Sign in again to send this report.',
      LabelMismatchFailureKind.photoUploadFailed =>
        'We couldn’t confirm all selected photos were uploaded. Retry this '
            'same report.',
      LabelMismatchFailureKind.reportInsertFailed =>
        'We couldn’t confirm the report was saved. Retry this same report. '
            'Nothing changes in the catalog automatically.',
      LabelMismatchFailureKind.reportFinalizeFailed =>
        'We couldn’t confirm the report was finalized. Retry this same report. '
            'Nothing changes in the catalog automatically.',
    };
    return Semantics(
      liveRegion: true,
      excludeSemantics: true,
      label: 'Report error. $message',
      child: Container(
        padding: const EdgeInsets.all(V2Spacing.space12),
        decoration: BoxDecoration(
          color: V2Colors.contraindicatedTint,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: V2Typography.bodySm(color: V2Colors.contraindicated),
            ),
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
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 48,
                color: V2Colors.safe,
              ),
              const SizedBox(height: V2Spacing.space16),
              Text(
                'Report sent',
                style: V2Typography.title(color: V2Colors.fg),
              ),
              const SizedBox(height: V2Spacing.space8),
              Text(
                'Thanks. We’ll review the catalog record. Your report does '
                'not change the catalog automatically.',
                textAlign: TextAlign.center,
                style: V2Typography.bodySm(color: V2Colors.fgMuted),
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

Future<LabelMismatchPhoto?> _pickProductLabelPhoto({
  required ImagePicker picker,
  required LabelMismatchPhotoSlot slot,
  required ImageSource source,
}) async {
  // Android lost-image recovery belongs to the app-startup lifecycle owner.
  // This ephemeral sheet must not consume a different picker flow's result.
  final file = await picker.pickImage(
    source: source,
    requestFullMetadata: false,
  );
  if (file == null) return null;

  return buildLabelMismatchPhotoFromFile(file: file, slot: slot);
}

@visibleForTesting
Future<LabelMismatchPhoto> buildLabelMismatchPhotoFromFile({
  required XFile file,
  required LabelMismatchPhotoSlot slot,
  SanitizeLabelMismatchPhoto sanitizer = _sanitizeLabelMismatchPhoto,
}) async {
  _supportedContentType(file);
  if (await file.length() > LabelMismatchPhoto.maxByteSize) {
    throw const LabelMismatchValidationException(
      LabelMismatchValidationFailure.photoTooLarge,
    );
  }

  final sourceBytes = await file.readAsBytes();
  if (sourceBytes.isEmpty) {
    throw const LabelMismatchValidationException(
      LabelMismatchValidationFailure.emptyPhoto,
    );
  }
  if (sourceBytes.length > LabelMismatchPhoto.maxByteSize) {
    throw const LabelMismatchValidationException(
      LabelMismatchValidationFailure.photoTooLarge,
    );
  }

  late final Uint8List sanitizedBytes;
  try {
    sanitizedBytes = await sanitizer(sourceBytes);
  } on Object {
    throw const LabelMismatchValidationException(
      LabelMismatchValidationFailure.photoSanitizationFailed,
    );
  }
  if (sanitizedBytes.isEmpty) {
    throw const LabelMismatchValidationException(
      LabelMismatchValidationFailure.photoSanitizationFailed,
    );
  }

  return LabelMismatchPhoto(
    slot: slot,
    bytes: sanitizedBytes,
    contentType: 'image/jpeg',
  );
}

Future<Uint8List> _sanitizeLabelMismatchPhoto(Uint8List sourceBytes) async {
  final result = await FlutterImageCompress.compressWithList(
    sourceBytes,
    minWidth: 2400,
    minHeight: 2400,
    quality: 90,
    format: CompressFormat.jpeg,
    keepExif: false,
  );
  return Uint8List.fromList(result);
}

String _supportedContentType(XFile file) {
  final rawDeclared = file.mimeType?.split(';').first.trim().toLowerCase();
  final declared = rawDeclared == null || rawDeclared.isEmpty
      ? null
      : rawDeclared;
  final normalized = declared == 'image/jpg' ? 'image/jpeg' : declared;
  if (normalized != null) {
    if (LabelMismatchPhoto.allowedContentTypes.contains(normalized)) {
      return normalized;
    }
    throw const LabelMismatchValidationException(
      LabelMismatchValidationFailure.unsupportedPhotoContentType,
    );
  }

  final extension = file.name.toLowerCase().split('.').last;
  final inferred = switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'webp' => 'image/webp',
    _ => null,
  };
  if (inferred == null) {
    throw const LabelMismatchValidationException(
      LabelMismatchValidationFailure.unsupportedPhotoContentType,
    );
  }
  return inferred;
}

bool _hasAuthenticatedUser() {
  try {
    return Supabase.instance.client.auth.currentUser != null;
  } on Object {
    return false;
  }
}

String _photoValidationMessage(LabelMismatchValidationException error) {
  return switch (error.reason) {
    LabelMismatchValidationFailure.emptyPhoto =>
      'That image is empty. Choose another.',
    LabelMismatchValidationFailure.photoTooLarge =>
      'Photo must be 15 MB or smaller.',
    LabelMismatchValidationFailure.unsupportedPhotoContentType =>
      'Use a JPEG, PNG, HEIC, HEIF, or WebP image.',
    LabelMismatchValidationFailure.photoSanitizationFailed =>
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

String _photoSlotLabel(LabelMismatchPhotoSlot slot) => switch (slot) {
  LabelMismatchPhotoSlot.front => 'Front of bottle',
  LabelMismatchPhotoSlot.supplementFacts => 'Supplement Facts',
  LabelMismatchPhotoSlot.otherIngredients => 'Other Ingredients',
};
