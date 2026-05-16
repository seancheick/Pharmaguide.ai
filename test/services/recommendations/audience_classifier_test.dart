// Phase 11.7L.F — audience classifier unit tests.
//
// The audience classifier is pure-data, no DB, so these tests
// construct synthetic `ProductsCoreData` fixtures and assert the
// inferred audience plus the hard-compatibility check.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/services/recommendations/audience_classifier.dart';

ProductsCoreData _p(String name, {String? brand}) => ProductsCoreData(
      dsldId: 'fixture-${name.hashCode}',
      productName: name,
      brandName: brand,
      exportVersion: 'test',
      exportedAt: '2026-05-16T00:00:00Z',
    );

ProductsCoreCompanion _c(String name) => ProductsCoreCompanion.insert(
      dsldId: 'fixture-${name.hashCode}',
      productName: name,
      exportVersion: 'test',
      exportedAt: '2026-05-16T00:00:00Z',
      brandName: const Value(null),
    );

void main() {
  group('inferAudience', () {
    test('kids markers — case-insensitive word boundaries', () {
      expect(inferAudience(_p('Kids Multivitamin Gummies')),
          Audience.kids);
      expect(inferAudience(_p("Children's Daily Multi")),
          Audience.kids);
      expect(inferAudience(_p('Junior Probiotic Chewable')),
          Audience.kids);
      expect(inferAudience(_p('Toddler Vitamin D')),
          Audience.kids);
      // Word boundary: 'kid' inside 'skidoo' should NOT match.
      expect(inferAudience(_p('Skidoo Endurance')), isNot(Audience.kids));
    });

    test('prenatal markers — case-insensitive', () {
      expect(inferAudience(_p('Basic Prenatal')), Audience.prenatal);
      expect(inferAudience(_p('Pregnancy Support Formula')),
          Audience.prenatal);
      expect(inferAudience(_p('Fertility Boost for TTC')),
          Audience.prenatal);
      expect(inferAudience(_p('Pre-natal Daily')), Audience.prenatal);
    });

    test('senior markers — 50+/60+/70+/mature', () {
      expect(inferAudience(_p('Senior Multi 50+')), Audience.senior);
      expect(inferAudience(_p('Mature Adult Daily')), Audience.senior);
      expect(inferAudience(_p('Vitality Over 70')), Audience.senior);
      expect(inferAudience(_p('60+ Energy')), Audience.senior);
    });

    test('sport markers (checked before mens — performance overrides)',
        () {
      // "Men's Performance" should classify as `sport`, not `mens` —
      // intent (performance) outranks audience (mens) in the
      // ordering.
      expect(inferAudience(_p("Men's Performance Pre-Workout")),
          Audience.sport);
      expect(inferAudience(_p('Athletic Endurance Blend')),
          Audience.sport);
      expect(inferAudience(_p('Pre-Workout Cherry Limeade')),
          Audience.sport);
      expect(inferAudience(_p('Muscle Builder Stack')),
          Audience.sport);
    });

    test('mens / womens markers', () {
      expect(inferAudience(_p("Women's Daily Multi")), Audience.womens);
      expect(inferAudience(_p("Men's Multi 50+")), Audience.senior); // senior wins
      expect(inferAudience(_p("GNC Men")), Audience.mens);
      expect(inferAudience(_p("For Men Probiotic")), Audience.mens);
      expect(inferAudience(_p("For Women Probiotic")), Audience.womens);
    });

    test('general fallback when no marker', () {
      expect(inferAudience(_p('Magnesium Glycinate')), Audience.general);
      expect(inferAudience(_p('Omega-3 1000mg')), Audience.general);
      expect(inferAudience(_p('Vitamin D3 5000 IU')), Audience.general);
    });

    test('brand name is a secondary signal', () {
      // Name has no marker, brand carries it.
      expect(
        inferAudience(_p('Multi Plus', brand: 'GNC Mega Men')),
        Audience.mens,
      );
    });
  });

  group('isAudienceCompatible — hard walls', () {
    test('kids is a complete wall — only kids ↔ kids', () {
      expect(isAudienceCompatible(Audience.kids, Audience.kids), isTrue);
      expect(isAudienceCompatible(Audience.kids, Audience.general),
          isFalse);
      expect(isAudienceCompatible(Audience.kids, Audience.prenatal),
          isFalse);
      expect(isAudienceCompatible(Audience.kids, Audience.mens),
          isFalse);
      expect(isAudienceCompatible(Audience.general, Audience.kids),
          isFalse);
    });

    test('prenatal is a complete wall — only prenatal ↔ prenatal', () {
      expect(isAudienceCompatible(Audience.prenatal, Audience.prenatal),
          isTrue);
      expect(isAudienceCompatible(Audience.prenatal, Audience.general),
          isFalse);
      expect(isAudienceCompatible(Audience.prenatal, Audience.womens),
          isFalse);
      expect(isAudienceCompatible(Audience.womens, Audience.prenatal),
          isFalse);
    });

    test('mens ↔ womens / senior cross-blocks', () {
      expect(isAudienceCompatible(Audience.mens, Audience.womens),
          isFalse);
      expect(isAudienceCompatible(Audience.mens, Audience.senior),
          isFalse);
      expect(isAudienceCompatible(Audience.womens, Audience.senior),
          isFalse);
      // Same specific audience swaps allowed.
      expect(isAudienceCompatible(Audience.mens, Audience.mens), isTrue);
      expect(isAudienceCompatible(Audience.senior, Audience.senior),
          isTrue);
    });

    test('general compatible with mens/womens/senior/sport', () {
      expect(isAudienceCompatible(Audience.general, Audience.mens),
          isTrue);
      expect(isAudienceCompatible(Audience.general, Audience.womens),
          isTrue);
      expect(isAudienceCompatible(Audience.general, Audience.senior),
          isTrue);
      expect(isAudienceCompatible(Audience.general, Audience.sport),
          isTrue);
    });

    test('sport ↔ general allowed at this layer — ranker carves out '
        'further with ingredient overlap', () {
      // The hard filter just checks "not a wall". The ranker
      // applies the ingredient-Jaccard ≥ 0.5 carveout separately
      // (see better_alternatives_ranker_test for that path).
      expect(isAudienceCompatible(Audience.sport, Audience.general),
          isTrue);
      expect(isAudienceCompatible(Audience.general, Audience.sport),
          isTrue);
      expect(isAudienceCompatible(Audience.sport, Audience.sport),
          isTrue);
    });
  });

  // Companion fixture is referenced for compile-time check that the
  // ProductsCoreCompanion API stays stable when used elsewhere.
  test('companion fixture compiles', () {
    expect(_c('smoke').productName.value, 'smoke');
  });
}
