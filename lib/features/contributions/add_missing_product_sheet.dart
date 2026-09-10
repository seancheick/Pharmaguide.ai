import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/services/gtin.dart';
import 'package:pharmaguide/services/gtin_ocr_service.dart';

typedef PickIdentityReference = Future<XFile?> Function();
typedef ReadIdentityReference = Future<List<GtinIdentity>> Function(XFile file);

/// Starts the same missing-product capture flow without requiring a live
/// barcode scan. The user may enter a UPC from a store listing or let local
/// OCR suggest numbers from a photo; only a check-digit-valid GTIN can leave
/// this sheet.
Future<String?> showAddMissingProductIdentitySheet(
  BuildContext context, {
  PickIdentityReference? pickReference,
  PickIdentityReference? takeReference,
  ReadIdentityReference? readReference,
}) {
  final picker = ImagePicker();
  return PGModal.bottomSheet<String>(
    context: context,
    builder: (_) => _AddMissingProductIdentitySheet(
      pickReference:
          pickReference ??
          () => picker.pickImage(
            source: ImageSource.gallery,
            requestFullMetadata: false,
          ),
      takeReference:
          takeReference ??
          () => picker.pickImage(
            source: ImageSource.camera,
            requestFullMetadata: false,
          ),
      readReference: readReference ?? readGtinCandidatesFromFile,
    ),
  );
}

class _AddMissingProductIdentitySheet extends StatefulWidget {
  const _AddMissingProductIdentitySheet({
    required this.pickReference,
    required this.takeReference,
    required this.readReference,
  });

  final PickIdentityReference pickReference;
  final PickIdentityReference takeReference;
  final ReadIdentityReference readReference;

  @override
  State<_AddMissingProductIdentitySheet> createState() =>
      _AddMissingProductIdentitySheetState();
}

class _AddMissingProductIdentitySheetState
    extends State<_AddMissingProductIdentitySheet> {
  final _controller = TextEditingController();
  bool _reading = false;
  bool _takingPhoto = false;
  String? _error;
  List<GtinIdentity> _candidates = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _readFromPhoto({required bool fromCamera}) async {
    if (_reading || _takingPhoto) return;
    setState(() {
      if (fromCamera) {
        _takingPhoto = true;
      } else {
        _reading = true;
      }
      _error = null;
      _candidates = const [];
    });
    try {
      final file = await (fromCamera
          ? widget.takeReference()
          : widget.pickReference());
      if (!mounted || file == null) return;
      final candidates = await widget.readReference(file);
      if (!mounted) return;
      if (candidates.isEmpty) {
        setState(
          () => _error =
              'No valid UPC/GTIN was found. Enter the digits printed on the '
              'label or store listing.',
        );
      } else if (candidates.length == 1) {
        _controller.text = candidates.single.submissionIdentity;
        setState(() => _candidates = candidates);
      } else {
        setState(() => _candidates = candidates);
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'We couldn’t read that image. You can enter the UPC digits '
              'manually.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _reading = false;
          _takingPhoto = false;
        });
      }
    }
  }

  void _choose(GtinIdentity identity) {
    _controller.text = identity.submissionIdentity;
    setState(() => _candidates = [identity]);
  }

  void _continue() {
    try {
      final identity = GtinIdentity.parse(_controller.text);
      Navigator.of(context).pop(identity.submissionIdentity);
    } on FormatException {
      setState(() => _error = invalidGtinMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space32 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add a product from photos',
            style: V2Typography.titleSm(color: context.v2.fg),
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'No live barcode scan is needed. Enter the UPC/GTIN from the '
            'package or store listing, then choose the label photos you '
            'already have.',
            style: V2Typography.bodySm(color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space12),
          Text(
            'TCIN and DPCI can help you find the listing, but they are not '
            'product identity keys and are not used to match or publish a '
            'product.',
            style: V2Typography.caption(color: context.v2.fgSubtle),
          ),
          const SizedBox(height: V2Spacing.space16),
          TextField(
            key: const Key('add-product-gtin-field'),
            controller: _controller,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            scrollPadding: EdgeInsets.only(bottom: bottomInset + 24),
            decoration: const InputDecoration(
              labelText: 'UPC or GTIN',
              hintText: 'e.g. 030772032565',
              helperText: 'We verify the check digit before continuing.',
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _continue(),
          ),
          const SizedBox(height: V2Spacing.space8),
          Wrap(
            spacing: V2Spacing.space8,
            runSpacing: V2Spacing.space8,
            children: [
              OutlinedButton.icon(
                key: const Key('add-product-read-upc'),
                onPressed: (_reading || _takingPhoto)
                    ? null
                    : () => _readFromPhoto(fromCamera: false),
                icon: _reading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_outlined),
                label: Text(
                  _reading ? 'Reading library photo…' : 'Read from library',
                ),
              ),
              OutlinedButton.icon(
                key: const Key('add-product-take-upc'),
                onPressed: (_reading || _takingPhoto)
                    ? null
                    : () => _readFromPhoto(fromCamera: true),
                icon: _takingPhoto
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera_outlined),
                label: Text(
                  _takingPhoto ? 'Reading camera photo…' : 'Take a photo',
                ),
              ),
            ],
          ),
          if (_candidates.length > 1) ...[
            const SizedBox(height: V2Spacing.space12),
            Text(
              'Several valid numbers were found. Choose the UPC/GTIN, not a '
              'store item number.',
              style: V2Typography.bodySm(color: context.v2.fg),
            ),
            ..._candidates.map(
              (identity) => ListTile(
                key: Key(
                  'add-product-gtin-candidate-${identity.submissionIdentity}',
                ),
                contentPadding: EdgeInsets.zero,
                title: Text(identity.submissionIdentity),
                subtitle: Text(identity.detectedSymbology.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _choose(identity),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: V2Spacing.space8),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: V2Typography.bodySm(color: context.v2.contraindicated),
              ),
            ),
          ],
          const SizedBox(height: V2Spacing.space16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              key: const Key('add-product-continue'),
              onPressed: (_reading || _takingPhoto) ? null : _continue,
              child: const Text('Continue with this UPC'),
            ),
          ),
        ],
      ),
    );
  }
}
