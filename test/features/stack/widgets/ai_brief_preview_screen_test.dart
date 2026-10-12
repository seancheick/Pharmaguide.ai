import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_settings_tile.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/stack/widgets/ai_brief_preview_screen.dart';
import 'package:pharmaguide/services/sharing/clinician_report_document_provider.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

UserStacksLocalData _entry(String id, String name, String type) {
  final ts = DateTime.utc(2026, 10, 12);
  return UserStacksLocalData(
    id: id,
    type: type,
    name: name,
    dsldId: null,
    rxcui: null,
    ingredientKeys: null,
    drugClassesCol: null,
    genericRxcui: null,
    ingredientRxcuisCol: null,
    dosage: null,
    frequency: null,
    addedAt: ts,
    clientUpdatedAt: ts,
    deletedAt: null,
    syncedAt: null,
  );
}

ClinicianReportData _fixture() => ClinicianReportData(
  profile: null,
  stack: [
    _entry('supp-1', 'Vitamin D3', 'supplement'),
    _entry('med-1', 'Lisinopril', 'medication'),
  ],
  intelligence: const StackIntelligence(
    tier: StackTier.decent,
    stackSize: 2,
    issues: [],
    interactionCount: 0,
    nutrientWarningCount: 0,
    hasRecalledIngredient: false,
    hasContraindicatedInteraction: false,
    hasBannedIngredient: false,
  ),
  safetyReport: const StackSafetyReport(),
  depletions: const [],
  generatedAt: DateTime.utc(2026, 10, 12, 16),
);

Widget _app({required ShareService shareService}) {
  return ProviderScope(
    overrides: [
      clinicianReportDataProvider.overrideWith((ref) async => _fixture()),
    ],
    child: MaterialApp(
      theme: V2Theme.light,
      home: AiBriefPreviewScreen(shareService: shareService),
    ),
  );
}

String _previewText(WidgetTester tester) {
  final widget = tester.widget<SelectableText>(
    find.byKey(const Key('ai_brief_preview_text')),
  );
  return widget.data!;
}

void main() {
  testWidgets('medications stay out until switched on, then share the exact '
      'previewed text', (tester) async {
    String? shared;
    final service = ShareService(
      shareOverride: (text, {subject}) async => shared = text,
    );
    await tester.pumpWidget(_app(shareService: service));
    await tester.pumpAndSettle();

    expect(_previewText(tester), contains('Vitamin D3'));
    expect(_previewText(tester), isNot(contains('Lisinopril')));
    expect(_previewText(tester), contains('Medications: not shared'));

    final medicationSwitch = find.descendant(
      of: find.widgetWithText(PGSettingsTile, 'Medications'),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(medicationSwitch);
    await tester.tap(medicationSwitch);
    await tester.pumpAndSettle();
    expect(_previewText(tester), contains('Lisinopril'));

    final shareButton = find.text('Share');
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pumpAndSettle();
    expect(shared, _previewText(tester));
  });

  testWidgets('copy puts the previewed text on the clipboard', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? clipboard;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final service = ShareService(shareOverride: (text, {subject}) async {});
    await tester.pumpWidget(_app(shareService: service));
    await tester.pumpAndSettle();

    final copyButton = find.text('Copy');
    await tester.ensureVisible(copyButton);
    await tester.tap(copyButton);
    await tester.pumpAndSettle();

    expect(clipboard, _previewText(tester));
    expect(clipboard, isNot(contains('Lisinopril')));
  });

  testWidgets('simple list preset drops findings and keeps names', (
    tester,
  ) async {
    final service = ShareService(shareOverride: (text, {subject}) async {});
    await tester.pumpWidget(_app(shareService: service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Simple list'));
    await tester.pumpAndSettle();

    final text = _previewText(tester);
    expect(text, contains('Vitamin D3'));
    expect(text, isNot(contains('## PharmaGuide findings')));
    expect(text, contains('PharmaGuide findings: not shared'));
  });
}
