// Manual barcode entry bottom sheet — lets the user type a UPC/EAN
// barcode number and look up the product from the on-device catalog.
//
// Reuses the same `findByUpc()` lookup as the camera scanner. The
// caller is responsible for handling the result (navigate to product
// detail or show not-found flow) via the [onProductFound] and
// [onProductNotFound] callbacks.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppTheme.space24,
        AppTheme.space8,
        AppTheme.space24,
        AppTheme.space24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter barcode manually',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.space8),
          Text(
            'Type the UPC, EAN, or barcode number from the product label.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppTheme.space20),
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
              hintStyle: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.dialpad_rounded),
            ),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 1.5,
            ),
            onChanged: _onChanged,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppTheme.space8),
          Text(
            'Most supplement barcodes are 12 or 13 digits.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.space20),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _isValid ? _submit : null,
              child: const Text('Find Product'),
            ),
          ),
        ],
      ),
    );
  }
}
