import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_type_badge.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';

/// Compact product / medication thumbnail.
///
/// Three states:
/// - **Image present**: cached network image, defined frame, hairline outline
/// - **Image missing (supplement)**: soft icon tile with accent-tint
///   background
/// - **Image missing (medication)**: a *designed bottle-shape placeholder*
///   — silhouette of a pill bottle drawn in accent stroke on the tint
///   background. Reads instantly as "medication" without an image.
///
/// Optional [type] badge overlays the bottom-right corner so the user
/// can tell at a glance whether each row is a supplement or a medication.
///
/// **Performance:** wrapped in `RepaintBoundary` so the thumbnail
/// doesn't repaint when surrounding state ticks (delta pills, scrolling,
/// shimmer overlays).
class PGProductThumbnail extends StatelessWidget {
  final String? imageUrl;

  /// Item type — drives placeholder shape and the optional corner badge.
  final PGItemType type;

  /// Show the type badge in the bottom-right corner.
  final bool showTypeBadge;

  /// Square dimension in logical pixels.
  final double size;

  /// Override the corner radius.
  final double? radius;

  const PGProductThumbnail({
    super.key,
    required this.type,
    this.imageUrl,
    this.showTypeBadge = true,
    this.size = 56,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final r = radius ?? V2Spacing.radiusCard;
    final missing = imageUrl == null || imageUrl!.isEmpty;

    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            // Frame.
            Container(
              decoration: BoxDecoration(
                color: missing ? type.tint(context.v2) : context.v2.surface,
                borderRadius: BorderRadius.circular(r),
                border: Border.all(color: context.v2.outline),
              ),
              clipBehavior: Clip.antiAlias,
              child: missing
                  ? _PlaceholderArt(type: type, size: size)
                  : Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _PlaceholderArt(type: type, size: size),
                    ),
            ),
            // Bottom-right type badge.
            if (showTypeBadge)
              Positioned(
                bottom: -6,
                right: -6,
                child: PGTypeBadge(type: type, solid: true),
              ),
          ],
        ),
      ),
    );
  }
}

/// Designed placeholder art keyed by [PGItemType]:
/// - Supplement → simple pill-shape icon
/// - Medication → bottle-silhouette painter (custom)
/// - Bookmark → bookmark icon
class _PlaceholderArt extends StatelessWidget {
  final PGItemType type;
  final double size;

  const _PlaceholderArt({required this.type, required this.size});

  @override
  Widget build(BuildContext context) {
    if (type == PGItemType.medication) {
      return CustomPaint(painter: _BottlePainter(color: type.color(context.v2)));
    }
    return Center(
      child: Icon(type.icon, size: size * 0.42, color: type.color(context.v2)),
    );
  }
}

/// Stylized pill-bottle silhouette painter.
///
/// Renders a recognizable bottle shape:
/// - Narrow neck top
/// - Wider body
/// - Subtle "label" stripe across the middle
///
/// Stroke-only — never fills — so it sits softly on the tint background
/// like an annotation rather than competing with foreground text.
class _BottlePainter extends CustomPainter {
  final Color color;

  const _BottlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = w * 0.06;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Geometry — proportional to the canvas size.
    final neckWidth = w * 0.30;
    final neckHeight = h * 0.16;
    final bodyTop = neckHeight + stroke * 0.5;
    final bodyLeft = w * 0.18;
    final bodyRight = w * 0.82;
    final bodyBottom = h * 0.84;
    final shoulderRadius = w * 0.10;
    final cornerRadius = w * 0.14;

    final path = Path()
      // Neck top-left
      ..moveTo((w - neckWidth) / 2, stroke * 0.5)
      // Neck top-right
      ..lineTo((w + neckWidth) / 2, stroke * 0.5)
      // Neck right → shoulder
      ..lineTo((w + neckWidth) / 2, bodyTop - shoulderRadius)
      ..quadraticBezierTo(
        (w + neckWidth) / 2,
        bodyTop,
        (w + neckWidth) / 2 + shoulderRadius,
        bodyTop,
      )
      // Shoulder → body right
      ..lineTo(bodyRight - cornerRadius, bodyTop)
      ..quadraticBezierTo(bodyRight, bodyTop, bodyRight, bodyTop + cornerRadius)
      // Body right → bottom right
      ..lineTo(bodyRight, bodyBottom - cornerRadius)
      ..quadraticBezierTo(
        bodyRight,
        bodyBottom,
        bodyRight - cornerRadius,
        bodyBottom,
      )
      // Bottom edge
      ..lineTo(bodyLeft + cornerRadius, bodyBottom)
      ..quadraticBezierTo(
        bodyLeft,
        bodyBottom,
        bodyLeft,
        bodyBottom - cornerRadius,
      )
      // Body left up
      ..lineTo(bodyLeft, bodyTop + cornerRadius)
      ..quadraticBezierTo(bodyLeft, bodyTop, bodyLeft + shoulderRadius, bodyTop)
      // Shoulder → neck left
      ..lineTo((w - neckWidth) / 2 - shoulderRadius, bodyTop)
      ..quadraticBezierTo(
        (w - neckWidth) / 2,
        bodyTop,
        (w - neckWidth) / 2,
        bodyTop - shoulderRadius,
      )
      ..close();

    canvas.drawPath(path, paint);

    // Label stripe — a single line ~40% down the body, thinner.
    final labelY = bodyTop + (bodyBottom - bodyTop) * 0.40;
    final labelPaint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.65
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(bodyLeft + stroke * 0.8, labelY),
      Offset(bodyRight - stroke * 0.8, labelY),
      labelPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BottlePainter old) => old.color != color;
}
