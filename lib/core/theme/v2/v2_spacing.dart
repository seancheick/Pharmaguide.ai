/// v2 spacing tokens — fixed scale, no other values allowed.
abstract final class V2Spacing {
  static const space4 = 4.0;
  static const space8 = 8.0;
  static const space12 = 12.0;
  static const space16 = 16.0;
  static const space24 = 24.0;
  static const space32 = 32.0;
  static const space48 = 48.0;
  static const space64 = 64.0;
  static const space96 = 96.0;

  /// Card / surface corner radius.
  static const radiusCard = 12.0;

  /// Bottom sheet / dialog corner radius.
  static const radiusSheet = 20.0;

  /// Pill CTA — fully rounded.
  static const radiusPill = 999.0;

  // Stagger base — entrance animation delays.
  static const staggerStep1 = Duration(milliseconds: 80);
  static const staggerStep2 = Duration(milliseconds: 120);
  static const staggerStep3 = Duration(milliseconds: 160);
  static const staggerStep4 = Duration(milliseconds: 200);
}
