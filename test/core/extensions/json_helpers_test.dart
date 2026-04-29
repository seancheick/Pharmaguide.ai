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
      final m = <String, dynamic>{'a': 3.14, 'b': 42, 'c': '99.5', 'd': 'bad'};
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
        // Map<dynamic, dynamic> shape — yaml/json roundtrips sometimes
        // produce this; safeMap must coerce rather than throw.
        'd': <dynamic, dynamic>{'x': 1},
      };
      expect(m.safeMap('a'), {'key': 'val'});
      expect(m.safeMap('b'), {'k': 'v'});
      expect(m.safeMap('c'), isEmpty);
      expect(m.safeMap('d'), {'x': 1});
      expect(m.safeMap('missing'), isEmpty);
    });

    test(
      'safeList returns the raw List or const [] for any non-list shape',
      () {
        final m = <String, dynamic>{
          'a': [1, 2, 3],
          'b': {'not': 'a list'},
          'c': 'string',
          'd': 42,
          'e': null,
        };
        expect(m.safeList('a'), [1, 2, 3]);
        expect(m.safeList('b'), isEmpty);
        expect(m.safeList('c'), isEmpty);
        expect(m.safeList('d'), isEmpty);
        expect(m.safeList('e'), isEmpty);
        expect(m.safeList('missing'), isEmpty);
      },
    );

    test('safeMapList filters to Map<String, dynamic> records and returns [] '
        'for non-list inputs', () {
      final m = <String, dynamic>{
        // The shape the probiotic crash hit — a list-of-maps where the
        // widget expected an int. safeMapList preserves the records.
        'a': [
          {'name': 'L. acidophilus'},
          {'name': 'B. lactis'},
        ],
        // Mixed list — non-map elements get dropped, not thrown on.
        'b': [
          {'name': 'good'},
          'string',
          42,
          null,
        ],
        // Wrong shape — must return empty without throwing.
        'c': {'not': 'a list'},
        'd': 99,
      };
      expect(m.safeMapList('a').length, 2);
      expect(m.safeMapList('a').first['name'], 'L. acidophilus');
      expect(m.safeMapList('b').length, 1);
      expect(m.safeMapList('c'), isEmpty);
      expect(m.safeMapList('d'), isEmpty);
      expect(m.safeMapList('missing'), isEmpty);
    });

    test('safeNum returns num/parsed-num/null without throwing', () {
      final m = <String, dynamic>{
        'a': 3.14,
        'b': 42,
        'c': '99.5',
        'd': 'bad',
        'e': null,
        'f': [1, 2],
      };
      expect(m.safeNum('a'), 3.14);
      expect(m.safeNum('b'), 42);
      expect(m.safeNum('c'), 99.5);
      expect(m.safeNum('d'), isNull);
      expect(m.safeNum('e'), isNull);
      expect(m.safeNum('f'), isNull);
      expect(m.safeNum('missing'), isNull);
    });
  });
}
