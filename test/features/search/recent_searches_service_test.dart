import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/recent_searches_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RecentSearchesService', () {
    test('addSearch dedupes case-insensitively and moves to top', () async {
      final service = RecentSearchesService();
      await service.addSearch('Thorne');
      await service.addSearch('magnesium');
      await service.addSearch('THORNE');

      final recent = await service.getRecent();
      expect(recent, ['THORNE', 'magnesium']);
    });

    test('list is capped at 10 entries', () async {
      final service = RecentSearchesService();
      for (var i = 0; i < 14; i++) {
        await service.addSearch('query $i');
      }

      final recent = await service.getRecent();
      expect(recent.length, 10);
      expect(recent.first, 'query 13');
      expect(recent.last, 'query 4');
    });

    test('getRecent collapses strict prefixes of newer entries', () async {
      // Simulates a list persisted before commit-only recording:
      // keystroke fragments, newest first.
      SharedPreferences.setMockInitialValues({
        'flutter.recent_searches': <String>[
          'thorne',
          'thorn',
          'thor',
          'tho',
          'th',
          'magnesium',
          'thr', // not a prefix of "thorne" — kept
        ],
      });

      final service = RecentSearchesService();
      final recent = await service.getRecent();
      expect(recent, ['thorne', 'magnesium', 'thr']);
    });

    test('older entry that prefixes a newer one is collapsed', () async {
      final service = RecentSearchesService();
      await service.addSearch('creatine');
      await service.addSearch('creatine monohydrate');

      // Older "creatine" is a prefix of the newer entry — collapsed.
      final recent = await service.getRecent();
      expect(recent, ['creatine monohydrate']);
    });
  });
}
