import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Shared reticle geometry: the drawn frame and the controller's
/// `scanWindow` MUST come from the same rect in the same layout box, or
/// the visual guide and the real decode region silently diverge.
class ScannerReticleGeometry {
  /// Wide frame for 1D product barcodes (UPC/EAN): ~78% width,
  /// 2.2:1 aspect, centered at ~42% height — thumb reach + label-facing
  /// ergonomics per shipping scanner conventions.
  static Rect reticleRect(Size size) {
    final width = size.width * 0.78;
    final height = width / 2.2;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: width,
      height: height,
    );
  }

  /// Decode region: slightly larger than the drawn frame so users are
  /// not scanning "through a keyhole" — the guide invites, the window
  /// forgives.
  static Rect scanWindow(Size size) =>
      reticleRect(size).inflate(reticleRect(size).height * 0.18);
}

/// Camera chrome: dim everything outside the reticle, draw corner
/// brackets, and back the helper text with a pill. White-on-camera text
/// is unreadable on bright shelves; every character here sits on its
/// own contrast layer.
class ScannerCaptureOverlay extends StatelessWidget {
  final String helperText;

  const ScannerCaptureOverlay({super.key, required this.helperText});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final reticle = ScannerReticleGeometry.reticleRect(size);
        return IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _CutoutScrimPainter(reticle: reticle)),
              // Top gradient so the title bar reads over any scene.
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  height: 132,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: reticle.bottom + V2Spacing.space16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: V2Spacing.space16,
                      vertical: V2Spacing.space8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.40),
                      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                    ),
                    child: Text(
                      helperText,
                      style: V2Typography.bodySm(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CutoutScrimPainter extends CustomPainter {
  final Rect reticle;

  _CutoutScrimPainter({required this.reticle});

  static const _cornerRadius = 16.0;
  static const _bracketLength = 26.0;
  static const _bracketStroke = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(
      reticle,
      const Radius.circular(_cornerRadius),
    );
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.50),
    );

    final bracket = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = _bracketStroke
      ..strokeCap = StrokeCap.round;
    final r = reticle;
    const len = _bracketLength;

    void corner(Offset elbow, Offset alongX, Offset alongY) {
      canvas.drawLine(elbow, elbow + alongX * len, bracket);
      canvas.drawLine(elbow, elbow + alongY * len, bracket);
    }

    corner(r.topLeft, const Offset(1, 0), const Offset(0, 1));
    corner(r.topRight, const Offset(-1, 0), const Offset(0, 1));
    corner(r.bottomLeft, const Offset(1, 0), const Offset(0, -1));
    corner(r.bottomRight, const Offset(-1, 0), const Offset(0, -1));
  }

  @override
  bool shouldRepaint(_CutoutScrimPainter oldDelegate) =>
      oldDelegate.reticle != reticle;
}
