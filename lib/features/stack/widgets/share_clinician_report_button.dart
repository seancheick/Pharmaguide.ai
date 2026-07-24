// ShareClinicianReportButton — UI entrypoint that gathers on-device
// state (profile + stack + safety reports), runs them through
// `ClinicianPdfBuilder`, and hands the PDF to the system share sheet
// via `ShareService`.
//
// Spec: INITIATIVE_STACK_INTELLIGENCE.md, Track C, C3.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/sharing/clinician_pdf_builder.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';

/// Tappable share-icon button. Place inside an `AppBar.actions` list on
/// the stack screen.
///
/// `shareService` is an optional override for unit tests so they can
/// capture the markdown handed to the share sheet without invoking a
/// real platform channel. Production callers omit it and the default
/// `ShareService()` runs through `share_plus`.
class ShareClinicianReportButton extends ConsumerWidget {
  const ShareClinicianReportButton({super.key, this.shareService});

  final ShareService? shareService;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Share with clinician',
      icon: const Icon(Icons.ios_share_rounded),
      onPressed: () => _onTap(context, ref),
    );
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = shareService ?? ShareService();

    try {
      // Snapshot every input the builder needs at the moment of tap.
      // Each `read` returns the latest cached value if loaded; the
      // `.future` form awaits if still in flight.
      final userDb = ref.read(userDatabaseProvider);
      final profile = await userDb.getProfile();
      final stack = await ref.read(activeStackProvider.future);
      final safetyReport = await ref.read(stackSafetyReportProvider.future);
      final synergyReport = await ref.read(synergyReportProvider.future);
      final recalledReport = await ref.read(
        recalledIngredientsReportProvider.future,
      );
      // Carry the load status, not just the matches: an `unavailable` report has
      // empty matches but must NOT print as "no depletions" (MedNutrientReport
      // contract) — the PDF states the analysis was unavailable instead.
      final depletionReport = await ref.read(depletionReportProvider.future);
      final depletions = depletionReport.matches;
      final doseAlerts = await ref.read(
        stackDoseThresholdAlertsProvider.future,
      );
      final Uint8List logoBytes;
      final Uint8List regularFontBytes;
      final Uint8List mediumFontBytes;
      try {
        final logo = await rootBundle.load('assets/images/report_logo.png');
        final regularFont = await rootBundle.load(
          'assets/fonts/Geist-Regular.ttf',
        );
        final mediumFont = await rootBundle.load(
          'assets/fonts/Geist-Medium.ttf',
        );
        logoBytes = _assetBytes(logo);
        regularFontBytes = _assetBytes(regularFont);
        mediumFontBytes = _assetBytes(mediumFont);
      } on Object catch (error, stackTrace) {
        CrashReportingService().recordError(
          error,
          stackTrace,
          hint: 'clinician_share_pdf:asset_load_failed',
        );
        rethrow;
      }

      final intelligence = const StackIntelligenceEngine().diagnoseFromReports(
        stackSize: stack.length,
        safetyReport: safetyReport,
        recalledReport: recalledReport,
        synergyReport: synergyReport,
        doseThresholdAlerts: doseAlerts,
      );

      final pdfBytes = await const ClinicianPdfBuilder().build(
        profile: profile,
        stack: stack,
        intelligence: intelligence,
        safetyReport: safetyReport,
        depletions: depletions,
        depletionStatus: depletionReport.status,
        generatedAt: DateTime.now(),
        logoBytes: logoBytes,
        regularFontBytes: regularFontBytes,
        mediumFontBytes: mediumFontBytes,
      );

      await service.shareClinicianReportPdf(pdfBytes);
    } on Object catch (error, stackTrace) {
      CrashReportingService().recordError(
        error,
        stackTrace,
        hint: 'clinician_share_pdf:build_failed',
      );
      // Anything failing in the input collection (DB, providers) drops
      // a non-blocking error to the user and bails. The share sheet
      // never opens with partial data.
      PGToast.showWith(
        messenger,
        'Could not build the report — try again in a moment.',
        variant: PGToastVariant.error,
        duration: const Duration(seconds: 3),
      );
    }
  }

  Uint8List _assetBytes(ByteData data) {
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
