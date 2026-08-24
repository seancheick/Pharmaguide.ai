import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// On-device photo quality gate for submission evidence.
///
/// Decoding and scoring run on a DOWNSAMPLED copy inside an isolate
/// (`compute`), so a 12-megapixel capture never blocks the UI thread.
///
/// Policy (per the amended plan):
///  * inadequate resolution HARD-BLOCKS — a panel below the floor cannot be
///    read by a reviewer or a model, so uploading it only wastes the user's
///    data and time;
///  * blur is a SOFT WARNING with "Use anyway" — variance-of-Laplacian is a
///    heuristic, and blocking on a heuristic strands users with unusual
///    labels. The threshold ships calibrated against real label photos
///    (see photo_quality_gate_test.dart fixtures).
enum PhotoQualityVerdict { ok, tooSmall, likelyBlurry }

@immutable
class PhotoQualityResult {
  const PhotoQualityResult({
    required this.verdict,
    required this.shortSide,
    required this.blurScore,
  });

  final PhotoQualityVerdict verdict;

  /// Shorter dimension of the decoded image, in pixels.
  final int shortSide;

  /// Variance of the Laplacian over the downsampled grayscale image.
  /// Higher is sharper; `double.nan` when the image could not be decoded.
  final double blurScore;

  bool get isHardBlock => verdict == PhotoQualityVerdict.tooSmall;
  bool get isSoftWarning => verdict == PhotoQualityVerdict.likelyBlurry;
}

class PhotoQualityGate {
  /// Below this short-side floor a Supplement Facts panel is not reliably
  /// readable even by a human reviewer at zoom.
  static const minShortSidePx = 800;

  /// Variance-of-Laplacian floor, calibrated on the committed fixture set
  /// (sharp label photos score well above 100; defocused captures of the
  /// same panels score in single digits). Tune ONLY together with the
  /// calibration fixtures.
  static const blurVarianceFloor = 25.0;

  /// Longest side of the analysis copy. Downsampling normalizes the score
  /// across capture resolutions and keeps the isolate fast.
  static const analysisMaxDimension = 640;

  /// Evaluate photo bytes off the UI thread.
  static Future<PhotoQualityResult> evaluate(Uint8List bytes) {
    return compute(_evaluateSync, bytes, debugLabel: 'photo_quality_gate');
  }

  /// Synchronous scoring: exposed for tests and for the isolate entrypoint.
  @visibleForTesting
  static PhotoQualityResult evaluateSync(Uint8List bytes) =>
      _evaluateSync(bytes);
}

PhotoQualityResult _evaluateSync(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    // Format probes can throw (not just return null) on garbage bytes.
    decoded = null;
  }
  if (decoded == null) {
    // Undecodable bytes never reach here in production (the sanitizer
    // re-encodes to JPEG first); treat defensively as too small.
    return const PhotoQualityResult(
      verdict: PhotoQualityVerdict.tooSmall,
      shortSide: 0,
      blurScore: double.nan,
    );
  }

  final shortSide = decoded.width < decoded.height
      ? decoded.width
      : decoded.height;
  if (shortSide < PhotoQualityGate.minShortSidePx) {
    return PhotoQualityResult(
      verdict: PhotoQualityVerdict.tooSmall,
      shortSide: shortSide,
      blurScore: double.nan,
    );
  }

  final longSide = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;
  final analysis = longSide > PhotoQualityGate.analysisMaxDimension
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height
              ? PhotoQualityGate.analysisMaxDimension
              : null,
          height: decoded.height > decoded.width
              ? PhotoQualityGate.analysisMaxDimension
              : null,
          interpolation: img.Interpolation.average,
        )
      : decoded;

  final blurScore = _laplacianVariance(analysis);
  if (blurScore < PhotoQualityGate.blurVarianceFloor) {
    return PhotoQualityResult(
      verdict: PhotoQualityVerdict.likelyBlurry,
      shortSide: shortSide,
      blurScore: blurScore,
    );
  }
  return PhotoQualityResult(
    verdict: PhotoQualityVerdict.ok,
    shortSide: shortSide,
    blurScore: blurScore,
  );
}

/// Variance of the 4-neighbour Laplacian over the grayscale image — the
/// standard cheap focus measure: defocus removes high-frequency content,
/// collapsing the Laplacian's variance toward zero.
double _laplacianVariance(img.Image image) {
  final gray = img.grayscale(image);
  final width = gray.width;
  final height = gray.height;
  if (width < 3 || height < 3) return 0;

  final luma = List<double>.filled(width * height, 0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      luma[y * width + x] = gray.getPixel(x, y).r.toDouble();
    }
  }

  var sum = 0.0;
  var sumSquares = 0.0;
  final count = (width - 2) * (height - 2);
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final index = y * width + x;
      final response =
          luma[index - width] +
          luma[index + width] +
          luma[index - 1] +
          luma[index + 1] -
          4 * luma[index];
      sum += response;
      sumSquares += response * response;
    }
  }
  final mean = sum / count;
  return sumSquares / count - mean * mean;
}
