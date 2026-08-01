import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/stack/widgets/clinician_report_preview_screen.dart';
import 'package:pharmaguide/features/stack/widgets/share_clinician_report_button.dart';
import 'package:pharmaguide/services/sharing/clinician_report_document_provider.dart';

void main() {
  testWidgets('renders an accessible clinician-share entry point', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: const [ShareClinicianReportButton()]),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Share stack'), findsOneWidget);
    expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
  });

  testWidgets('opens review screen before any share or print action', (
    tester,
  ) async {
    final pendingDocument = Completer<Uint8List>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clinicianReportDocumentProvider.overrideWith(
            (ref) => pendingDocument.future,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: const [ShareClinicianReportButton()]),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Share stack'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Share from your stack'), findsOneWidget);
    expect(find.text('Share supplements'), findsOneWidget);
    expect(find.text('Clinician report'), findsOneWidget);
    expect(
      find.textContaining('Product names and brands only'),
      findsOneWidget,
    );

    await tester.tap(find.text('Clinician report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Clinician report'), findsOneWidget);
    expect(find.text('Preparing your report on this device…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('fails closed instead of presenting a partial report', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clinicianReportDocumentProvider.overrideWith(
            (ref) async => throw StateError('stack unavailable'),
          ),
        ],
        child: const MaterialApp(home: Scaffold()),
      ),
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const ClinicianReportPreviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The report could not be prepared.'), findsOneWidget);
    expect(
      find.text('No partial report was created. Try again in a moment.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });
}
