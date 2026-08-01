// Manual barcode entry bottom sheet — lets the user type a UPC/EAN
// barcode number and look up the product from the on-device catalog.
//
// Reuses the same `findByUpc()` lookup as the camera scanner. The
// caller is responsible for handling the result (navigate to product
// detail or show not-found flow) via the [onProductFound] and
// [onProductNotFound] callbacks.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';

/// Shows the manual barcode entry sheet via [PGModal.bottomSheet].
///
/// Returns the normalized barcode string, or `null` if the user dismisses
/// without submitting.
Future<String?> showManualBarcodeSheet(BuildContext context) {
  return PGModal.bottomSheet<String?>(
    context: context,
    builder: (ctx) => const _ManualBarcodeSheet(),
  );
}

class _ManualBarcodeSheet extends StatefulWidget {
  const _ManualBarcodeSheet();

  @override
  State<_ManualBarcodeSheet> createState() => _ManualBarcodeSheetState();
}

class _ManualBarcodeSheetState extends State<_ManualBarcodeSheet> {
  final _controller = TextEditingController();
  String _barcode = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isValid {
    final digits = _barcode.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 8 && digits.length <= 14;
  }

  void _onChanged(String value) {
    setState(() => _barcode = value.trim());
  }

  void _submit() {
    if (!_isValid) return;
    Navigator.of(context).pop(_barcode.replaceAll(RegExp(r'[^0-9]'), ''));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter barcode manually',
            style: V2Typography.titleSm(color: context.v2.fg),
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'Type the UPC, EAN, or barcode number from the product label.',
            style: V2Typography.bodySm(color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space24),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(14),
            ],
            decoration: InputDecoration(
              hintText: 'e.g., 123456789012',
              hintStyle: V2Typography.body(
                color: context.v2.fgSubtle.withValues(alpha: 0.7),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                borderSide: BorderSide(color: context.v2.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                borderSide: BorderSide(color: context.v2.accent),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              ),
              prefixIcon: Icon(
                Icons.dialpad_rounded,
                color: context.v2.accent,
              ),
            ),
            style: V2Typography.monoData(color: context.v2.fg),
            onChanged: _onChanged,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'Most supplement barcodes are 12 or 13 digits.',
            style: V2Typography.caption(color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space24),
          PGPillButton(
            label: 'Find Product',
            icon: Icons.search_rounded,
            expand: true,
            onPressed: _isValid ? _submit : null,
          ),
        ],
      ),
    );
  }
}
