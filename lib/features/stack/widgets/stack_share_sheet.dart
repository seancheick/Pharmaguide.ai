import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/widgets/clinician_report_preview_screen.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';

enum _StackShareChoice { supplements, clinicianReport }

/// Single Stack sharing entry point.
///
/// Supplement sharing is intentionally non-clinical. The clinician report is
/// a separate, clearly labelled sensitive document that must be previewed
/// before its system share or print actions become available.
Future<void> showStackShareSheet(BuildContext context, WidgetRef ref) async {
  final choice = await PGModal.bottomSheet<_StackShareChoice>(
    context: context,
    builder: (_) => const _StackShareOptions(),
  );
  if (!context.mounted || choice == null) return;

  switch (choice) {
    case _StackShareChoice.clinicianReport:
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => const ClinicianReportPreviewScreen(),
        ),
      );
    case _StackShareChoice.supplements:
      final stack = await ref.read(activeStackProvider.future);
      final coreDb = ref.read(coreDatabaseProvider);
      final supplements = <SupplementShareItem>[];
      for (final entry in stack.where((item) => item.type == 'supplement')) {
        String? brand;
        final dsldId = entry.dsldId;
        if (dsldId != null && dsldId.isNotEmpty) {
          brand = (await coreDb.findById(dsldId))?.brandName;
        }
        supplements.add(SupplementShareItem(name: entry.name, brand: brand));
      }
      if (!context.mounted) return;
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              SupplementSharePreviewScreen(supplements: supplements),
        ),
      );
  }
}

class _StackShareOptions extends StatelessWidget {
  const _StackShareOptions();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Share from your stack',
            style: V2Typography.titleSm(color: context.v2.fg),
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'Choose exactly what leaves this device.',
            style: V2Typography.body(color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space16),
          _ShareOption(
            icon: Icons.medication_outlined,
            title: 'Share supplements',
            description:
                'Product names and brands only. Medications and health '
                'profile are never included.',
            onTap: () =>
                Navigator.of(context).pop(_StackShareChoice.supplements),
          ),
          const SizedBox(height: V2Spacing.space12),
          _ShareOption(
            icon: Icons.medical_information_outlined,
            title: 'Clinician report',
            description:
                'Sensitive PDF with profile, medications, supplements, and '
                'safety analysis. Preview before sharing or printing.',
            onTap: () =>
                Navigator.of(context).pop(_StackShareChoice.clinicianReport),
          ),
        ],
      ),
    );
  }
}

class _ShareOption extends StatelessWidget {
  const _ShareOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.v2.bg,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(V2Spacing.space16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: context.v2.accent, size: 24),
              const SizedBox(width: V2Spacing.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: V2Typography.bodyMedium(color: context.v2.fg),
                    ),
                    const SizedBox(height: V2Spacing.space4),
                    Text(
                      description,
                      style: V2Typography.bodySm(color: context.v2.fgMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.v2.fgSubtle),
            ],
          ),
        ),
      ),
    );
  }
}

class SupplementSharePreviewScreen extends StatelessWidget {
  const SupplementSharePreviewScreen({
    super.key,
    required this.supplements,
    this.shareService,
  });

  final List<SupplementShareItem> supplements;
  final ShareService? shareService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Share supplements',
          style: V2Typography.titleSm(color: context.v2.fg),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(V2Spacing.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(V2Spacing.space16),
                decoration: BoxDecoration(
                  color: context.v2.accentTint,
                  borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                ),
                child: Text(
                  'This list contains supplement names and brands only. It '
                  'does not include medications, health conditions, warnings, '
                  'scores, or clinician-report details.',
                  style: V2Typography.bodySm(color: context.v2.fg),
                ),
              ),
              const SizedBox(height: V2Spacing.space24),
              Text(
                '${supplements.length} '
                '${supplements.length == 1 ? 'supplement' : 'supplements'}',
                style: V2Typography.titleSm(color: context.v2.fg),
              ),
              const SizedBox(height: V2Spacing.space12),
              Expanded(
                child: supplements.isEmpty
                    ? Center(
                        child: Text(
                          'No supplements are saved in your stack.',
                          textAlign: TextAlign.center,
                          style: V2Typography.body(color: context.v2.fgMuted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: supplements.length,
                        separatorBuilder: (_, _) =>
                            Divider(color: context.v2.outline),
                        itemBuilder: (_, index) {
                          final item = supplements[index];
                          final brand = item.brand?.trim() ?? '';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.medication_outlined,
                              color: context.v2.accent,
                            ),
                            title: Text(
                              item.name,
                              style: V2Typography.bodyMedium(
                                color: context.v2.fg,
                              ),
                            ),
                            subtitle: brand.isNotEmpty
                                ? Text(
                                    brand,
                                    style: V2Typography.bodySm(
                                      color: context.v2.fgMuted,
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
              ),
              const SizedBox(height: V2Spacing.space16),
              PGPillButton(
                label: 'Share supplement list',
                icon: Icons.ios_share_rounded,
                expand: true,
                onPressed: supplements.isEmpty
                    ? null
                    : () => _shareSupplements(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareSupplements(BuildContext context) async {
    try {
      await (shareService ?? ShareService()).shareSupplementList(supplements);
    } on Object {
      if (!context.mounted) return;
      PGToast.show(
        context,
        'Could not open the share sheet. Try again.',
        variant: PGToastVariant.error,
      );
    }
  }
}
