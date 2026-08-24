import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pharmaguide/services/photo_quality_gate.dart';

/// Calibration fixtures are generated, not photographed, so the suite is
/// hermetic and deterministic. Measured sweep on this fixture at 1200px
/// (2026-08-24): radius 0 -> 8373, 4 -> 397, 8 -> 113, 12 -> 36,
/// 20 -> 4.0, 32 -> 2.8. The floor of 25 deliberately passes the marginal
/// radius-12 capture (readable at zoom) and warns from the clearly
/// defocused radius-20 level — an over-eager warning trains users to
/// ignore it. These tests pin ordering and policy, not exact scores.
Uint8List _syntheticLabel({required int size, int blurRadius = 0}) {
  var image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(245, 243, 238));
  // Text-like structure: alternating dark bars and a facts-style grid.
  for (var y = 40; y < size - 40; y += 28) {
    img.fillRect(
      image,
      x1: 32,
      y1: y,
      x2: size - 32,
      y2: y + 10,
      color: img.ColorRgb8(24, 26, 27),
    );
  }
  for (var x = 32; x < size - 32; x += 46) {
    img.drawLine(
      image,
      x1: x,
      y1: 24,
      x2: x,
      y2: size - 24,
      color: img.ColorRgb8(92, 95, 97),
    );
  }
  if (blurRadius > 0) {
    image = img.gaussianBlur(image, radius: blurRadius);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  test('sharp label passes', () {
    final result = PhotoQualityGate.evaluateSync(_syntheticLabel(size: 1200));

    expect(result.verdict, PhotoQualityVerdict.ok);
    expect(result.shortSide, 1200);
    expect(result.blurScore, greaterThan(PhotoQualityGate.blurVarianceFloor));
  });

  test('defocused label soft-warns, never hard-blocks', () {
    final result = PhotoQualityGate.evaluateSync(
      _syntheticLabel(size: 1200, blurRadius: 20),
    );

    expect(result.verdict, PhotoQualityVerdict.likelyBlurry);
    expect(result.isSoftWarning, isTrue);
    expect(result.isHardBlock, isFalse);
    expect(result.blurScore, lessThan(PhotoQualityGate.blurVarianceFloor));
  });

  test('sharpness ordering holds: blurred always scores below sharp', () {
    final sharp = PhotoQualityGate.evaluateSync(_syntheticLabel(size: 1000));
    final blurred = PhotoQualityGate.evaluateSync(
      _syntheticLabel(size: 1000, blurRadius: 8),
    );

    expect(blurred.blurScore, lessThan(sharp.blurScore));
  });

  test('inadequate resolution hard-blocks regardless of sharpness', () {
    final result = PhotoQualityGate.evaluateSync(_syntheticLabel(size: 400));

    expect(result.verdict, PhotoQualityVerdict.tooSmall);
    expect(result.isHardBlock, isTrue);
    expect(result.shortSide, 400);
  });

  test('undecodable bytes fail closed as too small', () {
    final result = PhotoQualityGate.evaluateSync(
      Uint8List.fromList([1, 2, 3, 4]),
    );

    expect(result.verdict, PhotoQualityVerdict.tooSmall);
    expect(result.shortSide, 0);
  });

  test('async evaluate matches the synchronous scorer', () async {
    final bytes = _syntheticLabel(size: 900);
    final asyncResult = await PhotoQualityGate.evaluate(bytes);
    final syncResult = PhotoQualityGate.evaluateSync(bytes);

    expect(asyncResult.verdict, syncResult.verdict);
    expect(asyncResult.shortSide, syncResult.shortSide);
  });
}
