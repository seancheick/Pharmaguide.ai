import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// RFC 8032 test vector 1: a published key, so it can never be anyone's real one.
const testAlertFeedKeyId = 'alert-feed-test';
const testAlertFeedPublicKey =
    'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';
const testAlertFeedKeys = {testAlertFeedKeyId: testAlertFeedPublicKey};
const _testAlertFeedSeed =
    '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';

List<int> _hex(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

/// Any Ed25519 key, in the `<key id>:<base64>` format of
/// scripts/release_manifest.py.
Future<String> signText(String text, {List<int>? seed, String? keyId}) async {
  final algorithm = Ed25519();
  final signature = await algorithm.sign(
    utf8.encode(text),
    keyPair: await algorithm.newKeyPairFromSeed(
      seed ?? _hex(_testAlertFeedSeed),
    ),
  );
  return '${keyId ?? testAlertFeedKeyId}:${base64.encode(signature.bytes)}';
}

/// The text scripts/sync_safety_alerts.py::build_statement writes.
String feedStatement({
  required String path,
  required String checksum,
  Object? extended,
  int sequence = 1,
  String keyId = testAlertFeedKeyId,
  String purpose = 'safety_alert_feed',
  int format = 1,
}) => jsonEncode({
  'base_feed': {'checksum': checksum, 'path': path},
  'extended_feed': extended,
  'format': format,
  'key_id': keyId,
  'purpose': purpose,
  'release_sequence': sequence,
});

/// The `signed_feed` block the publisher adds to the release row's manifest.
Future<Map<String, Object?>> signedFeedBlock({
  required String path,
  required String checksum,
  Object? extended,
  int sequence = 1,
}) async {
  final statement = feedStatement(
    path: path,
    checksum: checksum,
    extended: extended,
    sequence: sequence,
  );
  return {'statement': statement, 'signature': await signText(statement)};
}
