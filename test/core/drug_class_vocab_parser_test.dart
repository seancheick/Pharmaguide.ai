import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/data/drug_class_vocab.dart';

/// Parser contract for the v1.1.0 sheet-facing consumer fields.
///
/// The pipeline vocab (schema 1.1.0) adds `group_label` and
/// `commonly_used_for`. The bundled asset may lag behind (1.0.0 has
/// neither), so the parser must treat them as optional: missing or blank
/// values become null, and the medication details sheet omits its
/// education section when null.
void main() {
  final full = <String, dynamic>{
    'id': 'statins',
    'name': 'Statins / Cholesterol medication',
    'group_label': 'Cholesterol medications',
    'commonly_used_for':
        'Commonly used to help lower cholesterol and reduce the risk of '
        'heart attack and stroke.',
    'notes': 'Lower LDL cholesterol via HMG-CoA reductase.',
    'examples': ['atorvastatin (Lipitor)'],
    'rx_status': 'rx_only',
    'user_selectable': true,
  };

  group('DrugClassEntry.fromJson v1.1.0 consumer fields', () {
    test('parses group_label and commonly_used_for when present', () {
      final d = DrugClassEntry.fromJson(full);
      expect(d.groupLabel, 'Cholesterol medications');
      expect(d.commonlyUsedFor, startsWith('Commonly used'));
    });

    test('v1.0.0 asset without the fields parses with nulls', () {
      final legacy = Map<String, dynamic>.from(full)
        ..remove('group_label')
        ..remove('commonly_used_for');
      final d = DrugClassEntry.fromJson(legacy);
      expect(d.id, 'statins');
      expect(d.name, 'Statins / Cholesterol medication');
      expect(d.groupLabel, isNull);
      expect(d.commonlyUsedFor, isNull);
    });

    test('blank strings normalize to null so the sheet gate stays simple', () {
      final blank = Map<String, dynamic>.from(full)
        ..['group_label'] = '   '
        ..['commonly_used_for'] = '';
      final d = DrugClassEntry.fromJson(blank);
      expect(d.groupLabel, isNull);
      expect(d.commonlyUsedFor, isNull);
    });
  });
}
