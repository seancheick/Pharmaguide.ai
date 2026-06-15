import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/ingredients_helpers.dart';

void main() {
  group('inactiveFromMap', () {
    test('prefers label_display over normalized resolver display label', () {
      final inactive = inactiveFromMap(const {
        'name': 'Ascorbyl Palmitate',
        'label_display': 'Ascorbyl Palmitate',
        'display_label': 'Natural Preservatives',
        'display_role_label': 'Preservative natural',
      });

      expect(inactive.name, 'Ascorbyl Palmitate');
      expect(inactive.roleHelper, 'Preservative natural');
    });

    test('legacy blobs prefer label name over normalized display_label', () {
      final inactive = inactiveFromMap(const {
        'name': 'Ascorbyl Palmitate',
        'display_label': 'Natural Preservatives',
      });

      expect(inactive.name, 'Ascorbyl Palmitate');
    });

    test('falls back through display_label when no label field exists', () {
      final inactive = inactiveFromMap(const {
        'display_label': 'Hydroxypropyl Methylcellulose',
      });

      expect(inactive.name, 'Hydroxypropyl Methylcellulose');
    });
  });
}
