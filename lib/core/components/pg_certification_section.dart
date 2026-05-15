import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One certification or quality check — verified third-party programs
/// (USP, NSF, ConsumerLab, IFOS), purity attestations, label-accuracy
/// audits.
class PGCertification {
  final String label;

  /// True when verified by a documented third-party source. Drives the
  /// leading check vs cancel icon + green/grey tone.
  final bool verified;

  /// Optional 1-line caption ("Tested for 200+ contaminants").
  final String? caption;

  const PGCertification({
    required this.label,
    required this.verified,
    this.caption,
  });
}

/// v2 mirror of `CertificationDetailSection`
/// (lib/features/product_detail/widgets/pipeline_sections/
/// certification_detail_section.dart).
///
/// Lists certifications + quality checks as a flat row of items. Each
/// item: green check (verified) or muted-grey cancel (not verified) +
/// label + optional caption.
class PGCertificationSection extends StatelessWidget {
  final List<PGCertification> certifications;
  final String title;

  const PGCertificationSection({
    super.key,
    required this.certifications,
    this.title = 'Certifications & checks',
  });

  @override
  Widget build(BuildContext context) {
    if (certifications.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: V2Typography.titleSm(color: V2Colors.fg)),
          const SizedBox(height: V2Spacing.space12),
          for (var i = 0; i < certifications.length; i++) ...[
            if (i > 0) const SizedBox(height: V2Spacing.space8),
            _CertificationRow(cert: certifications[i]),
          ],
        ],
      ),
    );
  }
}

class _CertificationRow extends StatelessWidget {
  final PGCertification cert;
  const _CertificationRow({required this.cert});

  @override
  Widget build(BuildContext context) {
    final tone =
        cert.verified ? AppTheme.severitySafe : V2Colors.fgSubtle;
    final icon =
        cert.verified ? Icons.check_circle_rounded : Icons.cancel_outlined;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: tone),
        const SizedBox(width: V2Spacing.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cert.label,
                style: V2Typography.bodyMedium(color: V2Colors.fg),
              ),
              if (cert.caption != null) ...[
                const SizedBox(height: 2),
                Text(
                  cert.caption!,
                  style: V2Typography.caption(color: V2Colors.fgMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
