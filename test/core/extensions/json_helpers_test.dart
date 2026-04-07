import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';

void main() {
  group('SafeJson', () {
    test('safeString returns value or fallback', () {
      final m = <String, dynamic>{'a': 'hello', 'b': 123, 'c': null};
      expect(m.safeString('a'), 'hello');
      expect(m.safeString('b'), '123');
      expect(m.safeString('c'), '');
      expect(m.safeString('missing'), '');
      expect(m.safeString('missing', 'default'), 'default');
    });

    test('safeDouble handles numbers and strings', () {
      final m = <String, dynamic>{
        'a': 3.14,
        'b': 42,
        'c': '99.5',
        'd': 'bad',
      };
      expect(m.safeDouble('a'), 3.14);
      expect(m.safeDouble('b'), 42.0);
      expect(m.safeDouble('c'), 99.5);
      expect(m.safeDouble('d'), 0.0);
      expect(m.safeDouble('missing'), 0.0);
    });

    test('safeInt handles numbers and strings', () {
      final m = <String, dynamic>{'a': 42, 'b': 3.7, 'c': '99'};
      expect(m.safeInt('a'), 42);
      expect(m.safeInt('b'), 3);
      expect(m.safeInt('c'), 99);
      expect(m.safeInt('missing'), 0);
    });

    test('safeBool handles various truthy values', () {
      final m = <String, dynamic>{
        'a': true,
        'b': false,
        'c': 1,
        'd': 0,
        'e': 'true',
        'f': 'false',
        'g': '1',
      };
      expect(m.safeBool('a'), true);
      expect(m.safeBool('b'), false);
      expect(m.safeBool('c'), true);
      expect(m.safeBool('d'), false);
      expect(m.safeBool('e'), true);
      expect(m.safeBool('f'), false);
      expect(m.safeBool('g'), true);
      expect(m.safeBool('missing'), false);
    });

    test('safeStringList handles lists and JSON strings', () {
      final m = <String, dynamic>{
        'a': ['x', 'y'],
        'b': '["p","q"]',
        'c': 'not a list',
      };
      expect(m.safeStringList('a'), ['x', 'y']);
      expect(m.safeStringList('b'), ['p', 'q']);
      expect(m.safeStringList('c'), isEmpty);
      expect(m.safeStringList('missing'), isEmpty);
    });

    test('safeMap handles maps and JSON strings', () {
      final m = <String, dynamic>{
        'a': {'key': 'val'},
        'b': '{"k":"v"}',
        'c': 'not a map',
      };
      expect(m.safeMap('a'), {'key': 'val'});
      expect(m.safeMap('b'), {'k': 'v'});
      expect(m.safeMap('c'), isEmpty);
      expect(m.safeMap('missing'), isEmpty);
    });
  });
}
