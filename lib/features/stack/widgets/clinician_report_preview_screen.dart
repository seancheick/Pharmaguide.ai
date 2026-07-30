import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/services/sharing/clinician_report_document_provider.dart';
import 'package:printing/printing.dart';

/// Canonical preview for the sensitive clinician report.
///
/// The PDF is generated completely on device. [PdfPreview] supplies the
/// platform print and share actions only after the user has reviewed it.
class ClinicianReportPreviewScreen extends ConsumerWidget {
  const ClinicianReportPreviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(clinicianReportDocumentProvider);

    return Scaffold(
      backgroundColor: V2Colors.bg,
      appBar: AppBar(
        backgroundColor: V2Colors.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Clinician report',
          style: V2Typography.titleSm(color: V2Colors.fg),
        ),
      ),
      body: switch (document) {
        AsyncData(:final value) => _ReportPreview(document: value),
        AsyncError(:final error) => _ReportBuildError(
          onRetry: () => ref.invalidate(clinicianReportDocumentProvider),
          error: error,
        ),
        _ => const _ReportLoading(),
      },
    );
  }
}

class _ReportPreview extends StatelessWidget {
  const _ReportPreview({required this.document});

  final Uint8List document;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: V2Colors.surface,
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space12,
            V2Spacing.space24,
            V2Spacing.space12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: V2Colors.accent,
                size: 20,
              ),
              const SizedBox(width: V2Spacing.space12),
              Expanded(
                child: Text(
                  'Review before sharing. This report contains health '
                  'profile, medication, supplement, and safety information.',
                  style: V2Typography.bodySm(color: V2Colors.fgMuted),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: PdfPreview(
            build: (_) async => document,
            initialPageFormat: PdfPageFormat.letter,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            dynamicLayout: false,
            allowPrinting: true,
            allowSharing: true,
            pdfFileName: 'pharmaguide-clinician-report.pdf',
            shareActionExtraSubject: 'PharmaGuide clinician report',
            maxPageWidth: 720,
          ),
        ),
      ],
    );
  }
}

class _ReportLoading extends StatelessWidget {
  const _ReportLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: V2Colors.accent),
          const SizedBox(height: V2Spacing.space16),
          Text(
            'Preparing your report on this device…',
            style: V2Typography.body(color: V2Colors.fgMuted),
          ),
        ],
      ),
    );
  }
}

class _ReportBuildError extends StatelessWidget {
  const _ReportBuildError({required this.onRetry, required this.error});

  final VoidCallback onRetry;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(V2Spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: V2Colors.contraindicated,
              size: 36,
            ),
            const SizedBox(height: V2Spacing.space16),
            Text(
              'The report could not be prepared.',
              textAlign: TextAlign.center,
              style: V2Typography.titleSm(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'No partial report was created. Try again in a moment.',
              textAlign: TextAlign.center,
              style: V2Typography.body(color: V2Colors.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space24),
            PGPillButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
