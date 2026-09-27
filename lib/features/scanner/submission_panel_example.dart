import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

/// A small drawn picture of the label panel a capture step asks for, framed
/// by viewfinder corners.
///
/// "Supplement Facts" is obvious to a reviewer and not to everyone else; a
/// picture of the box answers "which part do they mean?" faster than more
/// words. It is drawn rather than photographed so it themes with the app,
/// ships no assets, and never shows a real product's doses. It is a picture:
/// its lettering is decorative, excluded from semantics, and immune to text
/// scaling, while one label describes it to screen readers.
class SubmissionPanelExample extends StatelessWidget {
  const SubmissionPanelExample({
    super.key,
    required this.category,
    this.barcodeDigits,
  });

  final ProductSubmissionEvidenceCategory category;

  /// The scanned code, drawn under the example bars so the user knows the
  /// exact number to look for.
  final String? barcodeDigits;

  String get _description => switch (category) {
    ProductSubmissionEvidenceCategory.frontIdentity =>
      'Example: the front of a supplement package with its brand and name',
    ProductSubmissionEvidenceCategory.supplementFacts =>
      'Example: a Supplement Facts panel listing each ingredient and amount',
    ProductSubmissionEvidenceCategory.ingredientDisclosure =>
      'Example: an Other Ingredients list',
    ProductSubmissionEvidenceCategory.barcode =>
      'Example: a barcode with its printed number',
    _ => 'Example label panel',
  };

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    return Semantics(
      image: true,
      label: _description,
      excludeSemantics: true,
      child: SizedBox(
        height: 156,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: v2.surfaceLow,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          ),
          child: Center(
            child: MediaQuery.withNoTextScaling(
              child: CustomPaint(
                foregroundPainter: _ViewfinderPainter(color: v2.accentStrong),
                child: Padding(
                  padding: const EdgeInsets.all(V2Spacing.space12),
                  child: switch (category) {
                    ProductSubmissionEvidenceCategory.frontIdentity =>
                      const _FrontDrawing(),
                    ProductSubmissionEvidenceCategory.supplementFacts =>
                      const _FactsDrawing(),
                    ProductSubmissionEvidenceCategory.ingredientDisclosure =>
                      const _IngredientsDrawing(),
                    ProductSubmissionEvidenceCategory.barcode =>
                      _BarcodeDrawing(digits: barcodeDigits),
                    _ => const SizedBox(width: 120, height: 96),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Decorative lettering: a [RichText], so it reads as part of the picture
/// rather than as another copy of the step's own text.
Widget _glyph(
  String text, {
  required Color color,
  double size = 9,
  FontWeight weight = FontWeight.w400,
  double letterSpacing = 0,
}) => RichText(
  maxLines: 1,
  text: TextSpan(
    text: text,
    style: TextStyle(
      fontFamily: 'Geist',
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.2,
      letterSpacing: letterSpacing,
    ),
  ),
);

Widget _bar(BuildContext context, double width, {double height = 5}) =>
    Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.v2.fg.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );

class _FrontDrawing extends StatelessWidget {
  const _FrontDrawing();

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    return Container(
      width: 132,
      height: 108,
      padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space12),
      decoration: BoxDecoration(
        color: v2.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: v2.fg.withValues(alpha: 0.18)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _glyph(
            'BRAND',
            color: v2.fgMuted,
            size: 8,
            weight: FontWeight.w500,
            letterSpacing: 1.4,
          ),
          const SizedBox(height: V2Spacing.space4),
          _glyph(
            'Product name',
            color: v2.accentStrong,
            size: 14,
            weight: FontWeight.w500,
          ),
          const SizedBox(height: V2Spacing.space8),
          _bar(context, 72),
          const SizedBox(height: V2Spacing.space4),
          _bar(context, 44),
        ],
      ),
    );
  }
}

class _FactsDrawing extends StatelessWidget {
  const _FactsDrawing();

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    Widget rule(double thickness) => Container(
      height: thickness,
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: v2.fg,
    );
    Widget row(String name, double amount) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          _glyph(name, color: v2.fg, size: 8.5),
          const Spacer(),
          _bar(context, amount, height: 4),
        ],
      ),
    );
    return Container(
      width: 164,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: v2.surface,
        border: Border.all(color: v2.fg, width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _glyph(
            'Supplement Facts',
            color: v2.fg,
            size: 13,
            weight: FontWeight.w700,
          ),
          _glyph('Serving Size 1 Capsule', color: v2.fgMuted, size: 7.5),
          rule(3),
          row('Vitamin D', 22),
          Container(height: 0.6, color: v2.fg.withValues(alpha: 0.4)),
          row('Magnesium', 30),
          Container(height: 0.6, color: v2.fg.withValues(alpha: 0.4)),
          row('Zinc', 18),
          rule(1.5),
        ],
      ),
    );
  }
}

class _IngredientsDrawing extends StatelessWidget {
  const _IngredientsDrawing();

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    return Container(
      width: 164,
      padding: const EdgeInsets.all(V2Spacing.space8),
      decoration: BoxDecoration(
        color: v2.surface,
        border: Border.all(color: v2.fg.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _glyph(
            'Other ingredients:',
            color: v2.fg,
            size: 10,
            weight: FontWeight.w700,
          ),
          const SizedBox(height: V2Spacing.space8),
          _bar(context, 146),
          const SizedBox(height: V2Spacing.space4),
          _bar(context, 118),
          const SizedBox(height: V2Spacing.space4),
          _bar(context, 84),
        ],
      ),
    );
  }
}

class _BarcodeDrawing extends StatelessWidget {
  const _BarcodeDrawing({this.digits});

  final String? digits;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    final number = (digits ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final seed = number.isEmpty ? '036000291452' : number;
    // Bar widths follow the digits, so each code draws its own pattern.
    final bars = <Widget>[];
    for (var i = 0; i < 34; i++) {
      final digit = seed.codeUnitAt(i % seed.length) - 48;
      final width = 1.0 + (digit + i) % 3;
      bars.add(
        Container(width: width, color: i.isEven ? v2.fg : Colors.transparent),
      );
      bars.add(SizedBox(width: i.isEven ? 1.5 : 0.5));
    }
    return Container(
      width: 164,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: v2.surface,
        border: Border.all(color: v2.fg.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 58,
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                height: 58,
                child: Row(mainAxisSize: MainAxisSize.min, children: bars),
              ),
            ),
          ),
          const SizedBox(height: V2Spacing.space4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: _glyph(
              number.isEmpty ? '0 36000 29145 2' : number,
              color: v2.fg,
              size: 11,
              weight: FontWeight.w500,
              letterSpacing: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Camera-style corner brackets around the example: "fill the frame like
/// this". Same vocabulary as the scanner reticle.
class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const length = 16.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final r = Offset.zero & size;
    void corner(Offset elbow, Offset alongX, Offset alongY) {
      canvas.drawLine(elbow, elbow + alongX * length, paint);
      canvas.drawLine(elbow, elbow + alongY * length, paint);
    }

    corner(r.topLeft, const Offset(1, 0), const Offset(0, 1));
    corner(r.topRight, const Offset(-1, 0), const Offset(0, 1));
    corner(r.bottomLeft, const Offset(1, 0), const Offset(0, -1));
    corner(r.bottomRight, const Offset(-1, 0), const Offset(0, -1));
  }

  @override
  bool shouldRepaint(_ViewfinderPainter oldDelegate) =>
      oldDelegate.color != color;
}
