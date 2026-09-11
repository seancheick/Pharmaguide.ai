import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/contribution_points.dart';

void main() {
  test('adds up the ledger and skips rows that are not awards', () {
    expect(
      sumLedgerPoints([
        {'points': 10},
        {'points': 10},
        {'points': 'ten'},
        {'points': -10},
        {'points': null},
        <String, Object?>{},
      ]),
      20,
    );
  });

  test('an empty ledger is zero points', () {
    expect(sumLedgerPoints(const []), 0);
  });
}
