import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('StackSafetyScore is numeric data, not a second verdict engine', () {
    final source = File(
      'lib/core/models/stack_safety_score.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('enum RiskTier')));
    expect(source, isNot(contains('healthLabel')));
    expect(source, isNot(contains('hasUnsafeIssue')));
  });
}
