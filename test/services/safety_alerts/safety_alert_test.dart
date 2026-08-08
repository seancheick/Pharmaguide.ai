import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';

void main() {
  final record = <String, Object?>{
    'alert_id': 'SA_2026_0001',
    'revision': 2,
    'event_type': 'ingredient_ban',
    'source_url': 'https://www.fda.gov/example',
    'headline': 'Regulatory safety update',
    'body': 'This product contains a prohibited substance.',
    'action': 'Stop taking this product and contact your clinician.',
    'consumer_disposition': 'block',
    'resolved_dsld_ids': ['306237'],
    'scope': {
      'ingredient_canonical_ids': ['tianeptine'],
      'dsld_ids': <String>[],
    },
  };

  test('matches frozen product identity or exact canonical ingredient identity', () {
    final alert = SafetyAlert.fromJson(record);

    expect(alert.appliesTo(dsldId: '306237', ingredientCanonicalIds: const []), isTrue);
    expect(
      alert.appliesTo(dsldId: '999999', ingredientCanonicalIds: const ['tianeptine']),
      isTrue,
    );
    expect(
      alert.appliesTo(dsldId: '999999', ingredientCanonicalIds: const ['tianeptine sodium']),
      isFalse,
    );
  });

  test('rejects an unapproved disposition and malformed operational record', () {
    expect(
      () => SafetyAlert.fromJson({...record, 'consumer_disposition': 'good_to_know'}),
      throwsFormatException,
    );
    expect(() => SafetyAlert.fromJson({...record, 'revision': 0}), throwsFormatException);
  });
}
