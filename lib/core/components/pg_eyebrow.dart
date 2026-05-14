import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Mono-caps eyebrow label.
///
/// Use for section labels, brand labels, metadata. ALWAYS uppercase the
/// passed string. Color defaults to the accent for emphasis; pass
/// [V2Colors.fgMuted] for quieter metadata.
class PGEyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  final TextAlign? textAlign;

  const PGEyebrow(this.text, {super.key, this.color, this.textAlign});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: V2Typography.eyebrow(color: color ?? V2Colors.accent),
      textAlign: textAlign,
    );
  }
}

/// 10pt overline variant of [PGEyebrow]. Use for evidence levels, severity
/// names, score tier names — anything smaller than an eyebrow.
class PGOverline extends StatelessWidget {
  final String text;
  final Color? color;

  const PGOverline(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: V2Typography.overline(color: color ?? V2Colors.fgMuted),
    );
  }
}
