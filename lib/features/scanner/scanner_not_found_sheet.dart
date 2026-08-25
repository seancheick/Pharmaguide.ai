import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// What the user chose from the not-found sheet. The scanner screen owns
/// navigation and camera lifecycle; the sheet only reports intent.
enum ScannerNotFoundAction {
  searchByName,
  scanAgain,
  helpAddProduct,
  addMedication,
}

/// Modal "product not found" sheet, shown over a stopped, dimmed camera.
///
/// Exactly one primary and one secondary action, contribution and manual
/// entry as quiet links — the code was READ (it is shown to prove it),
/// so re-typing it is never offered here; manual entry lives on the idle
/// scanner chrome for the can't-read failure mode instead.
Future<ScannerNotFoundAction?> showScannerNotFoundSheet(
  BuildContext context, {
  required String scannedCode,
  bool canSubmitProduct = true,
  bool manualEntry = false,
}) {
  return showModalBottomSheet<ScannerNotFoundAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _ScannerNotFoundSheet(
      scannedCode: scannedCode,
      canSubmitProduct: canSubmitProduct,
      manualEntry: manualEntry,
    ),
  );
}

class _ScannerNotFoundSheet extends StatelessWidget {
  final String scannedCode;
  final bool canSubmitProduct;
  final bool manualEntry;

  const _ScannerNotFoundSheet({
    required this.scannedCode,
    required this.canSubmitProduct,
    required this.manualEntry,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.all(V2Spacing.space8),
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space16,
            V2Spacing.space24,
            V2Spacing.space16,
          ),
          decoration: BoxDecoration(
            color: context.v2.bg,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.v2.outline,
                    borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                  ),
                ),
              ),
              const SizedBox(height: V2Spacing.space16),
              Text(
                'Product not found',
                textAlign: TextAlign.center,
                style: V2Typography.titleSm(color: context.v2.fg),
              ),
              const SizedBox(height: V2Spacing.space8),
              Text(
                manualEntry
                    ? "That code isn't in your on-device catalog yet."
                    : 'The barcode scanned fine — it is not in your '
                          'on-device catalog yet.',
                textAlign: TextAlign.center,
                style: V2Typography.body(color: context.v2.fgMuted),
              ),
              const SizedBox(height: V2Spacing.space12),
              Center(
                child: Container(
                  key: const Key('scanner-not-found-code'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: V2Spacing.space12,
                    vertical: V2Spacing.space4,
                  ),
                  decoration: BoxDecoration(
                    color: context.v2.surface,
                    borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                    border: Border.all(color: context.v2.outline),
                  ),
                  child: Text(
                    scannedCode,
                    style: V2Typography.overline(color: context.v2.fgMuted),
                  ),
                ),
              ),
              const SizedBox(height: V2Spacing.space24),
              PGPillButton(
                key: const Key('scanner-not-found-search'),
                label: 'Search by name',
                icon: Icons.search_rounded,
                expand: true,
                onPressed: () => Navigator.of(
                  context,
                ).pop(ScannerNotFoundAction.searchByName),
              ),
              const SizedBox(height: V2Spacing.space12),
              PGPillButton(
                key: const Key('scanner-not-found-rescan'),
                label: manualEntry ? 'Re-enter code' : 'Scan again',
                icon: manualEntry
                    ? Icons.keyboard_rounded
                    : Icons.qr_code_scanner_rounded,
                variant: PGPillVariant.secondary,
                expand: true,
                onPressed: () =>
                    Navigator.of(context).pop(ScannerNotFoundAction.scanAgain),
              ),
              const SizedBox(height: V2Spacing.space8),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  if (canSubmitProduct) ...[
                    TextButton(
                      key: const Key('scanner-not-found-help-add'),
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(ScannerNotFoundAction.helpAddProduct),
                      child: Text(
                        'Help add this product',
                        style: V2Typography.bodySm(color: context.v2.accent),
                      ),
                    ),
                  ],
                  TextButton(
                    key: const Key('scanner-not-found-add-medication'),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(ScannerNotFoundAction.addMedication),
                    child: Text(
                      'Add as medication',
                      style: V2Typography.bodySm(color: context.v2.accent),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
