import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';
import 'package:url_launcher/url_launcher.dart';

/// Live recall and ban alerts that match this product, shown under the hero.
///
/// The fast-lane feed reaches users between catalog releases, so a product
/// recalled after the last release has no blocked status yet; without this
/// slot only Stack and push saw it. Alert copy is authored and shown verbatim.
class LiveSafetyAlertSection extends ConsumerWidget {
  const LiveSafetyAlertSection({super.key, required this.product});

  final ProductsCoreData product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(productSafetyAlertsProvider(product));
    return alerts.maybeWhen(
      data: (matches) {
        if (matches.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final alert in matches)
              Padding(
                padding: const EdgeInsets.only(bottom: V2Spacing.space12),
                child: PGSeverityBanner(
                  key: Key('live-safety-alert-${alert.alertId}'),
                  tone: alert.disposition == SafetyAlertDisposition.block
                      ? PGBannerTone.danger
                      : PGBannerTone.caution,
                  title: alert.headline,
                  body: '${alert.body} ${alert.action}',
                  actionLabel: 'View source',
                  onAction: () => launchUrl(
                    alert.sourceUrl,
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
