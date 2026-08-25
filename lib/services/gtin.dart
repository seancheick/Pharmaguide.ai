/// Barcode families whose encoded widths affect GTIN interpretation.
///
/// In particular, an eight-digit value is not enough to distinguish EAN-8
/// from UPC-E. Camera callers must pass the decoder's symbology.
enum GtinSymbology { upcE, ean8, upcA, ean13, gtin14, unknown }

/// One validated product identity with every exact catalog lookup form.
class GtinIdentity {
  const GtinIdentity._({
    required this.rawDigits,
    required this.detectedSymbology,
    required this.canonicalGtin14,
    required this.lookupCandidates,
  });

  /// Digits supplied by the scanner or manual-entry field.
  final String rawDigits;

  /// Symbology supplied by the decoder, or [GtinSymbology.unknown] for manual
  /// entry.
  final GtinSymbology detectedSymbology;

  /// Zero-padded GTIN-14 used as the durable submission identity.
  final String canonicalGtin14;

  /// Exact-width representations that may exist in older catalog exports.
  final List<String> lookupCandidates;

  /// The server-facing identity is always canonical, including UPC-E inputs.
  String get submissionIdentity => canonicalGtin14;

  /// Parses and validates [value].
  ///
  /// Spaces and hyphens are accepted as display separators. Any other
  /// non-digit character, unsupported width, mismatched symbology, or invalid
  /// check digit throws [FormatException].
  factory GtinIdentity.parse(
    String value, {
    GtinSymbology detectedSymbology = GtinSymbology.unknown,
  }) {
    final rawDigits = _digitsFromInput(value);

    if (detectedSymbology == GtinSymbology.upcE) {
      final expanded = expandUpcE(rawDigits);
      if (expanded == null) {
        throw const FormatException('Invalid UPC-E');
      }
      return GtinIdentity._(
        rawDigits: rawDigits,
        detectedSymbology: detectedSymbology,
        canonicalGtin14: expanded.padLeft(14, '0'),
        lookupCandidates: List.unmodifiable({
          rawDigits,
          ...gtinWidthCandidates(expanded),
        }),
      );
    }

    final expectedWidth = switch (detectedSymbology) {
      GtinSymbology.ean8 => 8,
      GtinSymbology.upcA => 12,
      GtinSymbology.ean13 => 13,
      GtinSymbology.gtin14 => 14,
      GtinSymbology.unknown => null,
      GtinSymbology.upcE => throw StateError('Handled above'),
    };
    if (expectedWidth != null && rawDigits.length != expectedWidth) {
      throw FormatException(
        'Expected a $expectedWidth-digit ${detectedSymbology.name}',
      );
    }

    if (rawDigits.length == 8 && detectedSymbology == GtinSymbology.unknown) {
      return _parseManualEightDigits(rawDigits);
    }
    if (!isValidGtin(rawDigits)) {
      throw const FormatException('Invalid GTIN');
    }

    return GtinIdentity._(
      rawDigits: rawDigits,
      detectedSymbology: detectedSymbology,
      canonicalGtin14: rawDigits.padLeft(14, '0'),
      lookupCandidates: List.unmodifiable(gtinWidthCandidates(rawDigits)),
    );
  }
}

GtinIdentity _parseManualEightDigits(String rawDigits) {
  final isEan8 = isValidGtin(rawDigits);
  final expandedUpcA = expandUpcE(rawDigits);
  if (!isEan8 && expandedUpcA == null) {
    throw const FormatException('Invalid eight-digit GTIN');
  }

  // A valid GTIN-8 remains the primary manual identity. UPC-E is an
  // additional exact lookup interpretation only when its expanded check digit
  // also validates. If GTIN-8 is invalid but UPC-E is valid, the expanded
  // UPC-A becomes the primary identity.
  final primary = isEan8 ? rawDigits : expandedUpcA!;
  final candidates = <String>{rawDigits, ...gtinWidthCandidates(primary)};
  if (isEan8 && expandedUpcA != null) {
    candidates.addAll(gtinWidthCandidates(expandedUpcA));
  }

  return GtinIdentity._(
    rawDigits: rawDigits,
    detectedSymbology: GtinSymbology.unknown,
    canonicalGtin14: primary.padLeft(14, '0'),
    lookupCandidates: List.unmodifiable(candidates),
  );
}

String _digitsFromInput(String value) {
  if (RegExp(r'[^0-9\s-]').hasMatch(value)) {
    throw const FormatException('GTIN contains unsupported characters');
  }
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    throw const FormatException('GTIN is empty');
  }
  return digits;
}

/// Returns whether [value] is a standard GTIN-8, UPC-A, EAN-13, or GTIN-14
/// with a valid check digit.
bool isValidGtin(String value) {
  if (!RegExp(
    r'^(?:[0-9]{8}|[0-9]{12}|[0-9]{13}|[0-9]{14})$',
  ).hasMatch(value)) {
    return false;
  }

  final body = value.substring(0, value.length - 1);
  var sum = 0;
  for (
    var positionFromRight = 1;
    positionFromRight <= body.length;
    positionFromRight++
  ) {
    final digit = int.parse(body[body.length - positionFromRight]);
    sum += digit * (positionFromRight.isOdd ? 3 : 1);
  }
  final expectedCheckDigit = (10 - (sum % 10)) % 10;
  return expectedCheckDigit == int.parse(value[value.length - 1]);
}

/// Expands an eight-digit UPC-E (number system + six data digits + check
/// digit) to UPC-A. Returns null for invalid number systems or check digits.
String? expandUpcE(String value) {
  if (!RegExp(r'^[0-9]{8}$').hasMatch(value)) return null;

  final numberSystem = value[0];
  if (numberSystem != '0' && numberSystem != '1') return null;

  final d1 = value[1];
  final d2 = value[2];
  final d3 = value[3];
  final d4 = value[4];
  final d5 = value[5];
  final d6 = value[6];
  final checkDigit = value[7];

  final body = switch (d6) {
    '0' || '1' || '2' =>
      '$numberSystem$d1$d2$d6'
          '0000'
          '$d3$d4$d5',
    '3' =>
      '$numberSystem$d1$d2$d3'
          '00000'
          '$d4$d5',
    '4' =>
      '$numberSystem$d1$d2$d3$d4'
          '00000'
          '$d5',
    _ =>
      '$numberSystem$d1$d2$d3$d4$d5'
          '0000'
          '$d6',
  };
  final expanded = '$body$checkDigit';
  return isValidGtin(expanded) ? expanded : null;
}

/// Exact storage-width equivalents for an already validated GTIN value.
///
/// EAN-8 is never treated as a stripped longer code. Leading zeros are
/// removed only at the established 14→13→12 boundaries.
Set<String> gtinWidthCandidates(String digits) {
  final candidates = <String>{digits};
  switch (digits.length) {
    case 8:
      candidates.add(digits.padLeft(14, '0'));
    case 12:
      candidates
        ..add('0$digits')
        ..add('00$digits');
    case 13:
      if (digits.startsWith('0')) candidates.add(digits.substring(1));
      candidates.add('0$digits');
    case 14:
      if (digits.startsWith('0')) candidates.add(digits.substring(1));
      if (digits.startsWith('00')) candidates.add(digits.substring(2));
      if (digits.startsWith('000000')) candidates.add(digits.substring(6));
  }
  return candidates;
}
