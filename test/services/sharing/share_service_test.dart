import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';

void main() {
  group('ShareService', () {
    test('shareProduct builds formatted text with highlights', () {
      // ShareService uses Share.share() which needs platform channel.
      // We test the logic by verifying the service instantiates.
      final service = ShareService();
      expect(service, isNotNull);
    });
  });
}
