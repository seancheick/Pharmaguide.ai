import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_review_before_use_card.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/utils/product_canonical_ids.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_helpers.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/quick_check/quick_check_logic.dart'
    as quick_check;
import 'package:pharmaguide/features/scanner/scanner_logic.dart';

void main() {
  const pipelineBlob = <String, dynamic>{
    'dsld_id': '220094',
    'verdict': 'BLOCKED',
    'safety_verdict': 'BLOCKED',
    'has_banned_substance': 1,
    'blocking_reason': 'banned_ingredient',
    'ingredient_fingerprint': {
      'nutrients': {
        'potassium': {'amount': 99, 'unit': 'mg'},
      },
      'herbs': ['green_tea'],
      'categories': ['minerals'],
      'pharmacological_flags': {'stimulant': false},
    },
    'ingredients': [
      {
        'name': 'Potassium',
        'canonical_id': 'potassium',
        'severity_status': 'n/a',
      },
      {
        'name': 'Green Tea Extract',
        'canonical_id': 'green_tea',
        'severity_status': 'n/a',
      },
    ],
    'warnings_profile_gated': [
      {
        'type': 'banned_substance',
        'severity': 'critical',
        'title': 'Banned substance: Brominated Vegetable Oil',
        'detail': 'Food additive revoked by FDA in 2024. Avoid.',
        'ingredient_name': 'Brominated Vegetable Oil',
        'matched_rule_id': 'BANNED_BVO_2024',
        'display_mode_default': 'critical',
        'safety_warning_one_liner': 'Avoid products listing BVO.',
        'safety_warning': 'This ingredient is not allowed in foods.',
      },
      {
        'type': 'watchlist_substance',
        'severity': 'moderate',
        'title': 'Excipient watchlist: Titanium Dioxide',
        'detail': 'EU-banned white pigment. Avoid when possible.',
        'ingredient_name': 'Titanium Dioxide',
        'matched_rule_id': 'BANNED_ADD_TITANIUM_DIOXIDE',
        'display_mode_default': 'informational',
        'inactive_policy': 'excipient_acceptable',
      },
    ],
  };

  test(
    'Product Detail and Review Before Use share warning severity semantics',
    () {
      final warnings = (pipelineBlob['warnings_profile_gated'] as List)
          .cast<Map<String, dynamic>>()
          .map(InteractionWarning.fromJson)
          .toList(growable: false);

      expect(warnings.first.severity, Severity.contraindicated);
      expect(warnings.first.ingredientName, 'Brominated Vegetable Oil');
      expect(warnings.first.displayModeDefault, 'critical');
      expect(warnings.first.alertHeadline, 'Avoid products listing BVO.');

      final sorted = sortWarningsBySeverity(warnings);
      expect(sorted.first.title, 'Banned substance: Brominated Vegetable Oil');
      expect(toneForWarning(sorted.first.severity), PGReviewTone.danger);

      final excipient = sorted.last;
      expect(excipient.title, 'Excipient watchlist: Titanium Dioxide');
      expect(excipient.severity, Severity.caution);
      expect(excipient.displayModeDefault, 'informational');
      expect(toneForWarning(excipient.severity), PGReviewTone.caution);
    },
  );

  test(
    'Quick Check and Stack canonical ID helpers parse the same blob fields',
    () {
      final fingerprintJson = jsonEncode(
        pipelineBlob['ingredient_fingerprint'],
      );

      expect(
        quick_check.extractCanonicalIds(fingerprintJson),
        containsAll(<String>['potassium', 'green_tea']),
      );
      expect(
        canonicalIdsFromDetailBlob(pipelineBlob),
        containsAll(<String>['potassium', 'green_tea']),
      );
    },
  );

  test('Scanner blocked verdict renders red, never safe/neutral', () {
    expect(verdictFlashColor('BLOCKED'), V2Colors.contraindicated);
    expect(
      verdictFlashColor(pipelineBlob['verdict'] as String),
      V2Colors.contraindicated,
    );
  });
}
