// Tests for the scanner screen's pure verdict→color policy.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/scoring/score_tier.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/components/pg_verdict_reveal.dart';
import 'package:pharmaguide/features/scanner/scanner_logic.dart';
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';

void main() {
  group('scanRevealKind', () {
    test('a clean catalog product confirms as success (dsld 299750)', () {
      // Liposomal Vitamin C, SAFE 91/100, flashed amber: the scan flow passed
      // its safety status id to a switch that only knew verdict strings.
      expect(
        scanRevealKind(CatalogProductSafetyStatus.noKnownCatalogConcern),
        PGVerdictKind.success,
      );
    });

    test('every other safety status asks for attention', () {
      for (final status in CatalogProductSafetyStatus.values) {
        if (status == CatalogProductSafetyStatus.noKnownCatalogConcern) {
          continue;
        }
        expect(
          scanRevealKind(status),
          PGVerdictKind.attention,
          reason: '$status',
        );
      }
    });
  });

  group('verdictFlashColor', () {
    test('SAFE → v2 safe', () {
      expect(verdictFlashColor(V2Palette.light, 'SAFE'), V2Palette.light.safe);
    });

    test('CAUTION → v2 caution', () {
      expect(
        verdictFlashColor(V2Palette.light, 'CAUTION'),
        V2Palette.light.caution,
      );
    });

    test('POOR → Poor quality tier color, never avoid', () {
      expect(
        verdictFlashColor(V2Palette.light, 'POOR'),
        ScoreTier.poor.textColor(Brightness.light),
      );
      expect(
        verdictFlashColor(V2Palette.dark, 'POOR'),
        ScoreTier.poor.textColor(Brightness.dark),
      );
    });

    test('RECOMMENDED → v2 safe', () {
      expect(
        verdictFlashColor(V2Palette.light, 'RECOMMENDED'),
        V2Palette.light.safe,
      );
    });

    test('GOOD → v2 safe', () {
      expect(verdictFlashColor(V2Palette.light, 'GOOD'), V2Palette.light.safe);
    });

    test('REVIEW → v2 caution', () {
      expect(
        verdictFlashColor(V2Palette.light, 'REVIEW'),
        V2Palette.light.caution,
      );
    });

    test('MODERATE → v2 caution', () {
      expect(
        verdictFlashColor(V2Palette.light, 'MODERATE'),
        V2Palette.light.caution,
      );
    });

    test('BLOCKED → v2 contraindicated', () {
      expect(
        verdictFlashColor(V2Palette.light, 'BLOCKED'),
        V2Palette.light.contraindicated,
      );
    });

    test('UNSAFE → v2 contraindicated', () {
      expect(
        verdictFlashColor(V2Palette.light, 'UNSAFE'),
        V2Palette.light.contraindicated,
      );
    });

    test('NOT_SCORED and NUTRITION_ONLY → v2 neutral', () {
      expect(
        verdictFlashColor(V2Palette.light, 'NOT_SCORED'),
        V2Palette.light.fgSubtle,
      );
      expect(
        verdictFlashColor(V2Palette.light, 'NUTRITION_ONLY'),
        V2Palette.light.fgSubtle,
      );
    });

    test('lowercase verdict normalizes to uppercase', () {
      expect(
        verdictFlashColor(V2Palette.light, 'recommended'),
        V2Palette.light.safe,
      );
      expect(
        verdictFlashColor(V2Palette.light, 'blocked'),
        V2Palette.light.contraindicated,
      );
    });

    test('mixed-case verdict normalizes to uppercase', () {
      expect(
        verdictFlashColor(V2Palette.light, 'Review'),
        V2Palette.light.caution,
      );
    });

    test('null verdict falls through to neutral unknown', () {
      expect(
        verdictFlashColor(V2Palette.light, null),
        V2Palette.light.fgSubtle,
      );
    });

    test('empty string falls through to neutral unknown', () {
      expect(verdictFlashColor(V2Palette.light, ''), V2Palette.light.fgSubtle);
    });

    test('unknown verdict falls through to neutral unknown', () {
      expect(
        verdictFlashColor(V2Palette.light, 'FUTURE_LABEL'),
        V2Palette.light.fgSubtle,
      );
    });
  });
}
