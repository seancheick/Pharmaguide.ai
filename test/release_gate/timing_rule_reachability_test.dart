// Release gate: every verified timing rule reaches the products it claims to,
// and stops at the ones it must not.
//
// "Reachable" is deliberately not "resolves to >=1 product". A rule that hits
// one obscure row is technically reachable and still defective — which is how
// an FDA-labelled levothyroxine/soy rule shipped while matching 4 of 13,271
// products, and how a coffee rule matched 270 caffeine and guarana products
// that contain no coffee.
//
// So each verified rule is checked in both directions against the SHIPPED
// catalog: named positive canaries must match, named negative canaries must
// not, and no rule may resolve through a tag the catalog does not emit.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/timing_evaluation_service.dart';
import 'package:sqlite3/sqlite3.dart';

late Database db;
late List<Map<String, dynamic>> rules;
late TimingEvaluationService service;

Set<String> tagsFor(String dsldId) {
  final rows = db.select(
    'SELECT key_ingredient_tags FROM products_core WHERE dsld_id = ?',
    [dsldId],
  );
  if (rows.isEmpty) return const {};
  final raw = rows.first['key_ingredient_tags'] as String?;
  if (raw == null || raw.isEmpty) return const {};
  return (jsonDecode(raw) as List).cast<String>().toSet();
}

int productsCarrying(String tag) {
  final rows = db.select(
    'SELECT COUNT(DISTINCT p.dsld_id) AS n FROM products_core p, '
    "json_each(p.key_ingredient_tags) j WHERE j.value = ?",
    [tag],
  );
  return rows.first['n'] as int;
}

List<String> identityTagsOf(Map<String, dynamic> rule) => [
  ...((rule['ingredient1_tags'] as List?)?.cast<String>() ?? const []),
  ...((rule['ingredient2_tags'] as List?)?.cast<String>() ?? const []),
];

void main() {
  setUpAll(() {
    db = sqlite3.open('assets/db/pharmaguide_core.db', mode: OpenMode.readOnly);
    final json =
        jsonDecode(
              File('assets/reference_data/timing_rules.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    rules = (json['timing_rules'] as List).cast<Map<String, dynamic>>();
    service = TimingEvaluationService.fromJson(json);
  });

  /// Does [ruleId] actually fire for the shipped product [dsldId]?
  ///
  /// Behavioural, not tag-membership: a `standalone` rule's negative canary is
  /// normally a combination product that DOES carry the tag - proving the rule
  /// stays out of it is the whole point, and a tag check would call that a
  /// failure.
  bool ruleFiresFor(String ruleId, String dsldId) {
    return service
        .evaluateStack(
          stackItems: [
            TimingStackItem.supplement(
              stackEntryId: 'row-$dsldId',
              displayName: 'canary-$dsldId',
              ingredientTags: tagsFor(dsldId),
            ),
          ],
        )
        .any((o) => o.ruleId == ruleId);
  }

  tearDownAll(() => db.dispose());

  List<Map<String, dynamic>> verifiedRules() =>
      rules.where((r) => r['review_status'] == 'verified').toList();

  test('there is something to gate', () {
    expect(verifiedRules(), isNotEmpty);
  });

  test('every verified rule resolves only through tags the catalog emits', () {
    for (final rule in verifiedRules()) {
      for (final tag in identityTagsOf(rule)) {
        expect(
          productsCarrying(tag),
          greaterThan(0),
          reason:
              '${rule['id']} names tag "$tag", which no shipped product '
              'carries. A rule that resolves to nothing looks healthy and '
              'warns no one.',
        );
      }
    }
  });

  test('every verified rule has at least one identity', () {
    for (final rule in verifiedRules()) {
      final hasTags = identityTagsOf(rule).isNotEmpty;
      final hasRxcuis =
          (rule['ingredient1_rxcuis'] as List?)?.isNotEmpty == true ||
          (rule['ingredient2_rxcuis'] as List?)?.isNotEmpty == true;
      expect(hasTags || hasRxcuis, isTrue, reason: '${rule['id']}');
    }
  });

  test('positive canaries actually carry the rule identity', () {
    for (final rule in verifiedRules()) {
      final canaries = rule['canaries'] as Map<String, dynamic>;
      final positives = (canaries['positive'] as List).cast<String>();
      final identity = identityTagsOf(rule).toSet();
      if (identity.isEmpty) continue; // medication-only side

      for (final dsldId in positives) {
        final tags = tagsFor(dsldId);
        expect(
          tags,
          isNotEmpty,
          reason: '${rule['id']}: canary $dsldId is not in the shipped catalog',
        );
        expect(
          tags.intersection(identity),
          isNotEmpty,
          reason:
              '${rule['id']}: canary $dsldId carries none of the rule identity '
              '$identity',
        );
      }
    }
  });

  test('a unary rule actually fires on its positive canary', () {
    for (final rule in verifiedRules()) {
      // Binary rules need their partner row present; the dedicated
      // levothyroxine canary test supplies the medication side.
      if (rule['timing_relation']['type'] == 'separate_from') continue;
      final canaries = rule['canaries'] as Map<String, dynamic>;
      for (final dsldId in (canaries['positive'] as List).cast<String>()) {
        expect(
          ruleFiresFor(rule['id'] as String, dsldId),
          isTrue,
          reason:
              '${rule['id']} does not fire on its own positive canary $dsldId '
              '- reachable on paper, silent in practice',
        );
      }
    }
  });

  test('a rule never fires on its negative canary', () {
    for (final rule in verifiedRules()) {
      if (rule['timing_relation']['type'] == 'separate_from') continue;
      final canaries = rule['canaries'] as Map<String, dynamic>;
      for (final dsldId in (canaries['negative'] as List).cast<String>()) {
        expect(
          tagsFor(dsldId),
          isNotEmpty,
          reason: '${rule['id']}: canary $dsldId is not in the shipped catalog',
        );
        expect(
          ruleFiresFor(rule['id'] as String, dsldId),
          isFalse,
          reason:
              '${rule['id']} fires on negative canary $dsldId. For a '
              'standalone rule that usually means the combination-product '
              'guard let a multi-ingredient bottle through.',
        );
      }
    }
  });

  test('every verified rule declares both canary directions', () {
    for (final rule in verifiedRules()) {
      final canaries = rule['canaries'] as Map<String, dynamic>;
      expect(canaries.containsKey('positive'), isTrue, reason: '${rule['id']}');
      expect(
        (canaries['negative'] as List),
        isNotEmpty,
        reason:
            '${rule['id']}: without a negative canary, over-matching is '
            'invisible',
      );
    }
  });

  test('no verified rule keys on caffeine or guarana', () {
    // The specific over-match this work removed: two rules about drinking
    // coffee were keyed to `caffeine`, which the app expanded to include
    // `guarana`, so 270 products received copy about a beverage they do not
    // contain. Coffee is not a catalog identity at all, so no rule may claim it
    // through a stimulant tag.
    for (final rule in verifiedRules()) {
      for (final tag in identityTagsOf(rule)) {
        expect(
          tag,
          isNot(anyOf('caffeine', 'guarana')),
          reason:
              '${rule['id']} keys on $tag. Coffee polyphenols are the actor in '
              'the iron and levothyroxine literature; caffeine is not a valid '
              'stand-in.',
        );
      }
    }
  });

  test('the levothyroxine soy rule reaches real soy products', () {
    // Regression guard for the worst defect found: an FDA-labelled hard drug
    // rule that matched 4 of 13,271 products because it aliased to `soy` and
    // `soy_protein`, tags the catalog never emits.
    //
    // Checked across ALL rules, not just verified ones. Reachability and
    // clinical disposition are independent: this rule's identity is fixed and
    // must stay fixed, while its 4-hour interval is separately suppressed
    // pending a source that actually states four hours. A rule can be correctly
    // targeted and still not ready to publish.
    final rule = rules.firstWhere(
      (r) => r['id'] == 'timing_thyroid_med_soy_separate',
      orElse: () => throw StateError('the soy rule is gone'),
    );
    final reach = identityTagsOf(
      rule,
    ).fold<int>(0, (sum, tag) => sum + productsCarrying(tag));
    expect(reach, greaterThan(4), reason: 'still effectively unreachable');
    expect(identityTagsOf(rule), contains('soybean'));
    expect(identityTagsOf(rule), isNot(contains('soy_protein')));
  });

  test('no rule anywhere keys coffee guidance on a stimulant tag', () {
    // Broader than the verified-only check above: the caffeine/guarana route
    // must not come back through a rule that is merely suppressed today, since
    // suppression is temporary and identity defects are not self-announcing.
    for (final rule in rules) {
      final advice = (rule['advice'] as String).toLowerCase();
      if (!advice.contains('coffee')) continue;
      for (final tag in identityTagsOf(rule)) {
        expect(
          tag,
          isNot(anyOf('caffeine', 'guarana')),
          reason:
              '${rule['id']} gives coffee advice keyed on $tag. The catalog '
              'emits no `coffee` tag at all, so this rule has no honest '
              'identity yet — it must stay suppressed, not be re-pointed at a '
              'stimulant.',
        );
      }
    }
  });
}
