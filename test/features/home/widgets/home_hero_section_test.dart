import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/home/widgets/home_hero_section.dart';

void main() {
  group('HomeHeroSection.greetingFor', () {
    test('hours 5–11 return "Good morning"', () {
      expect(HomeHeroSection.greetingFor(5), 'Good morning');
      expect(HomeHeroSection.greetingFor(8), 'Good morning');
      expect(HomeHeroSection.greetingFor(11), 'Good morning');
    });

    test('hours 12–16 return "Hello there"', () {
      expect(HomeHeroSection.greetingFor(12), 'Hello there');
      expect(HomeHeroSection.greetingFor(14), 'Hello there');
      expect(HomeHeroSection.greetingFor(16), 'Hello there');
    });

    test('hours 17–20 return "Good evening"', () {
      expect(HomeHeroSection.greetingFor(17), 'Good evening');
      expect(HomeHeroSection.greetingFor(19), 'Good evening');
      expect(HomeHeroSection.greetingFor(20), 'Good evening');
    });

    test('hours 21–4 return "Good night"', () {
      expect(HomeHeroSection.greetingFor(21), 'Good night');
      expect(HomeHeroSection.greetingFor(23), 'Good night');
      expect(HomeHeroSection.greetingFor(0), 'Good night');
      expect(HomeHeroSection.greetingFor(2), 'Good night');
      expect(HomeHeroSection.greetingFor(4), 'Good night');
    });

    test('does not contain "Good afternoon" anywhere', () {
      // User explicitly removed "Good afternoon" — replaced by "Hello there".
      // This guards against a regression that re-introduces the old copy.
      for (var hour = 0; hour < 24; hour++) {
        expect(
          HomeHeroSection.greetingFor(hour),
          isNot(contains('afternoon')),
          reason: 'hour $hour should not produce "afternoon" copy',
        );
      }
    });
  });
}
