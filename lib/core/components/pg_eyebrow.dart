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
  final int? maxLines;

  const PGEyebrow(
    this.text, {
    super.key,
    this.color,
    this.textAlign,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    // Eyebrow tracking + uppercase + mono caps means long copy
    // ("NO KNOWN INTERACTION IN OUR DATABASE") regularly exceeds
    // single-line width on small screens. Allow soft-wrap so the
    // text reflows instead of overflowing the parent (Sean 2026-05-17
    // screenshot regression). Callers can clamp via `maxLines` if a
    // single-line layout is required (chip / pill contexts).
    return Text(
      text.toUpperCase(),
      style: V2Typography.eyebrow(color: color ?? V2Colors.accent),
      textAlign: textAlign,
      softWrap: true,
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : TextOverflow.visible,
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
