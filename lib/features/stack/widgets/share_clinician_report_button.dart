// ShareClinicianReportButton — compact entrypoint to the canonical
// on-device clinician-report preview.
//
// Spec: INITIATIVE_STACK_INTELLIGENCE.md, Track C, C3.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/features/stack/widgets/stack_share_sheet.dart';

/// Tappable entry point for the privacy-separated Stack share menu.
class ShareClinicianReportButton extends ConsumerWidget {
  const ShareClinicianReportButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Share stack',
      icon: const Icon(Icons.ios_share_rounded),
      onPressed: () => showStackShareSheet(context, ref),
    );
  }
}
