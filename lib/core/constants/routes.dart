/// Centralized route path constants.
/// All navigation uses these instead of magic strings.
abstract final class Routes {
  static const home = '/';
  static const scan = '/scan';
  static const stack = '/stack';
  static const chat = '/chat';
  static const profile = '/profile';
  static const profileSetup = '/profile/setup';
  static const onboarding = '/onboarding';
  static const search = '/search';

  /// Product detail — append the dsldId: `'${Routes.product}/$dsldId'`
  static const product = '/product';

  /// Build a product detail path with dsldId.
  static String productDetail(String dsldId) => '/product/$dsldId';

  /// "Safe to Take Together?" quick pair interaction check.
  static const quickCheck = '/quick-check';
}
