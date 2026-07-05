// FIX (integrity): downloaded detail blobs must be checksum-verified.
//
// The blob path is content-addressed (`…/{sha256[0:2]}/{sha256}.json`) but
// the bytes come back over the PUBLIC CDN with no authentication — a
// mis-served, stale, or tampered object would otherwise feed unverified
// ingredient/warning JSON straight into FitScore and the personalized
// warnings engine. [detailBlobBytesMatchSha256] is the PURE integrity gate
// that DetailBlobService.fetchDetailBlobByHash applies to the raw bytes
// BEFORE any parsing; a mismatch is treated as a fetch failure.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';

void main() {
  group('detailBlobBytesMatchSha256 (pure integrity gate)', () {
    // Known NIST SHA-256 test vector: sha256("abc").
    const abcSha =
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

    test('bytes hashing to the expected sha are accepted', () {
      expect(detailBlobBytesMatchSha256(utf8.encode('abc'), abcSha), isTrue);
    });

    test('tampered bytes are rejected', () {
      expect(detailBlobBytesMatchSha256(utf8.encode('abd'), abcSha), isFalse);
      expect(detailBlobBytesMatchSha256(utf8.encode('abc '), abcSha), isFalse);
    });

    test('truncated body is rejected', () {
      expect(detailBlobBytesMatchSha256(utf8.encode('ab'), abcSha), isFalse);
    });

    test('empty body never matches a real blob hash', () {
      expect(detailBlobBytesMatchSha256(const <int>[], abcSha), isFalse);
    });

    test('expected-sha comparison is case-insensitive hex', () {
      expect(
        detailBlobBytesMatchSha256(utf8.encode('abc'), abcSha.toUpperCase()),
        isTrue,
      );
    });

    test('surrounding whitespace in the expected sha is tolerated', () {
      expect(
        detailBlobBytesMatchSha256(utf8.encode('abc'), ' $abcSha\n'),
        isTrue,
      );
    });

    test('realistic JSON blob with multi-byte UTF-8 verifies byte-for-byte', () {
      // The gate must hash the RAW bytes (never a decode/re-encode round
      // trip, which is not byte-stable for arbitrary input).
      final bytes = utf8.encode('{"ingredients":[{"name":"Ashwagandhā"}]}');
      // sha256 of exactly those bytes, computed with `shasum -a 256`.
      const expected =
          '561333f09727a97ce6417f4e16f2411365741fd13cd7d6c15301f14007faad56';
      expect(detailBlobBytesMatchSha256(bytes, expected), isTrue);
      // Tampering a single byte must flip the verdict.
      final tampered = List<int>.from(bytes)..[0] = 0x20;
      expect(detailBlobBytesMatchSha256(tampered, expected), isFalse);
    });
  });
}
