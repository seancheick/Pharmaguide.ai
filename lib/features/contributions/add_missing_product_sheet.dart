import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/services/gtin.dart';
import 'package:pharmaguide/services/product_submission_service.dart';
import 'package:pharmaguide/services/gtin_ocr_service.dart';

typedef PickIdentityReference = Future<XFile?> Function();
typedef ReadIdentityReference = Future<List<GtinIdentity>> Function(XFile file);

/// Starts the same missing-product capture flow without requiring a live
/// barcode scan. The user may enter a UPC from a store listing or let local
/// OCR suggest numbers from a photo. The explicit alternative retains private
/// printed-code evidence without asserting a numeric GTIN or catalog absence.
Future<Object?> showAddMissingProductIdentitySheet(
  BuildContext context, {
  PickIdentityReference? pickReference,
  PickIdentityReference? takeReference,
  ReadIdentityReference? readReference,
}) {
  final picker = ImagePicker();
  return PGModal.bottomSheet<Object>(
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
  bool _alternative = false;
  bool _noCode = false;
  final _brand = TextEditingController();
  final _name = TextEditingController();
  final _url = TextEditingController();
  bool _reading = false;
  bool _takingPhoto = false;
  String? _error;
  List<GtinIdentity> _candidates = const [];

  @override
  void dispose() {
    _controller.dispose();
    _brand.dispose();
    _name.dispose();
    _url.dispose();
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
      if (_alternative) {
        final identifier = ProductSubmissionIdentifier(
          observedCode: _noCode ? null : _controller.text,
          codeType: _noCode ? 'none' : 'other',
          noCode: _noCode,
          brandName: _brand.text,
          fullName: _name.text,
          listingUrl: _url.text.isEmpty ? null : _url.text,
        );
        Navigator.of(context).pop(identifier);
        return;
      }
      final identity = GtinIdentity.parse(_controller.text);
      Navigator.of(context).pop(identity.submissionIdentity);
    } on FormatException {
      setState(
        () => _error = _alternative
            ? 'Enter the brand, full product name and printed code, or select no printed code. Listing links must use https:// or http://.'
            : invalidGtinMessage,
      );
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
            _alternative
                ? 'You can continue without a UPC. Enter the brand, full '
                      'product name, and any code exactly as printed. A reviewer '
                      'will check the label photos.'
                : 'Enter the UPC/GTIN from the package or store listing. We’ll '
                      'check your installed catalog first. For a missing product, '
                      'include clear photos showing the brand and full product name, '
                      'complete Supplement Facts, directions and warnings, and the '
                      'barcode or printed UPC.',
            style: V2Typography.bodySm(color: context.v2.fgMuted),
          ),
          if (!_alternative) ...[
            const SizedBox(height: V2Spacing.space12),
            Text(
              'TCIN and DPCI can help you find the listing, but they are not '
              'product identity keys and are not used to match or publish a '
              'product.',
              style: V2Typography.caption(color: context.v2.fgSubtle),
            ),
          ],
          const SizedBox(height: V2Spacing.space16),
          TextButton(
            key: const Key('add-product-alternate-code'),
            onPressed: () => setState(() {
              _alternative = !_alternative;
              _error = null;
            }),
            child: Text(
              _alternative
                  ? 'Use a UPC / GTIN instead'
                  : 'My code contains letters / I can’t find a UPC',
            ),
          ),
          if (_alternative) ...[
            TextField(
              key: const Key('add-product-brand'),
              controller: _brand,
              decoration: const InputDecoration(labelText: 'Brand'),
            ),
            TextField(
              key: const Key('add-product-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full product name'),
            ),
            TextField(
              key: const Key('add-product-listing'),
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Product link (optional)',
              ),
            ),
            CheckboxListTile(
              key: const Key('add-product-no-code'),
              contentPadding: EdgeInsets.zero,
              title: const Text('There is no printed code on this package'),
              value: _noCode,
              onChanged: (v) => setState(() => _noCode = v!),
            ),
            const Text(
              'You don’t need to know the code type. A reviewer will check it against your photos.',
            ),
          ],
          if (!_alternative || !_noCode)
            TextField(
              key: const Key('add-product-gtin-field'),
              controller: _controller,
              keyboardType: _alternative
                  ? TextInputType.text
                  : TextInputType.number,
              textInputAction: TextInputAction.done,
              scrollPadding: EdgeInsets.only(bottom: bottomInset + 24),
              decoration: InputDecoration(
                labelText: _alternative ? 'Exact printed code' : 'UPC or GTIN',
                hintText: 'e.g. 030772032565',
                helperText: _alternative
                    ? 'Preserve letters, case and punctuation exactly.'
                    : 'We verify the check digit before continuing.',
                prefixIcon: const Icon(Icons.numbers_rounded),
                // Filled with a real border: the default underline reads as
                // blank space, and a contributor cannot tell it is a field.
                filled: true,
                fillColor: context.v2.surfaceLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                  borderSide: BorderSide(color: context.v2.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                  borderSide: BorderSide(color: context.v2.accent, width: 2),
                ),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _continue(),
            ),
          if (!_alternative) ...[
            const SizedBox(height: V2Spacing.space12),
            // Says what the two buttons do, so "Photo library" is not mistaken
            // for choosing the label photos, which comes after Continue.
            Text(
              'Or read the number from a photo',
              style: V2Typography.caption(color: context.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space8),
            // Two equal halves spanning exactly the Continue button's width,
            // at its height; stacked when large text would squeeze the labels.
            LayoutBuilder(
              builder: (context, constraints) {
                final library = _readButton(
                  key: const Key('add-product-read-upc'),
                  busy: _reading,
                  icon: Icons.photo_library_outlined,
                  label: 'Photo library',
                  fromCamera: false,
                );
                final camera = _readButton(
                  key: const Key('add-product-take-upc'),
                  busy: _takingPhoto,
                  icon: Icons.photo_camera_outlined,
                  label: 'Take photo',
                  fromCamera: true,
                );
                final stacked =
                    constraints.maxWidth < 300 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      library,
                      const SizedBox(height: V2Spacing.space8),
                      camera,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: library),
                    const SizedBox(width: V2Spacing.space8),
                    Expanded(child: camera),
                  ],
                );
              },
            ),
          ],
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
              child: Text(
                _alternative
                    ? 'Continue with label photos'
                    : 'Continue with this UPC',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _readButton({
    required Key key,
    required bool busy,
    required IconData icon,
    required String label,
    required bool fromCamera,
  }) => SizedBox(
    height: 48,
    child: FilledButton.tonalIcon(
      key: key,
      onPressed: (_reading || _takingPhoto)
          ? null
          : () => _readFromPhoto(fromCamera: fromCamera),
      icon: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      // A half-width button has no room for "Reading library photo…".
      label: Text(
        busy ? 'Reading…' : label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}
