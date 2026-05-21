import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/recent_searches_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('RecentSearchesService', () {
    test('normalizes and deduplicates old persisted history on read', () async {
      SharedPreferences.setMockInitialValues({
        'recent_searches': [
          'Magnesium',
          ' magnesium ',
          '',
          'Vitamin   D',
          'vitamin d',
        ],
      });

      final service = RecentSearchesService();

      expect(await service.getRecent(), ['Magnesium', 'Vitamin D']);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('recent_searches'), [
        'Magnesium',
        'Vitamin D',
      ]);
    });

    test(
      'deduplicates by normalized query while preserving newest casing',
      () async {
        SharedPreferences.setMockInitialValues({
          'recent_searches': ['Magnesium', 'Vitamin D'],
        });

        final service = RecentSearchesService();

        await service.addSearch('  magnesium  ');

        expect(await service.getRecent(), ['magnesium', 'Vitamin D']);
      },
    );

    test('collapses whitespace and caps history at ten entries', () async {
      SharedPreferences.setMockInitialValues({});
      final service = RecentSearchesService();

      for (var i = 0; i < 11; i++) {
        await service.addSearch('query   $i');
      }

      expect(await service.getRecent(), [
        'query 10',
        'query 9',
        'query 8',
        'query 7',
        'query 6',
        'query 5',
        'query 4',
        'query 3',
        'query 2',
        'query 1',
      ]);
    });

    test('removes all normalized matches from existing history', () async {
      SharedPreferences.setMockInitialValues({
        'recent_searches': ['Magnesium', ' magnesium ', 'Vitamin D'],
      });

      final service = RecentSearchesService();

      await service.removeSearch('magnesium');

      expect(await service.getRecent(), ['Vitamin D']);
    });
  });
}
