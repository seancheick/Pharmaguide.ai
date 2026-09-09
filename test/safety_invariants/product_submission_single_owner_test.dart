import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One owner per concern, enforced rather than remembered.
///
/// Every duplicate of an identity or integrity rule is a second brain that
/// drifts the moment one copy is corrected. These checks exist because the
/// draft store was written with its own GTIN padding, its own sha256 call and
/// its own category lookup, each of which already had an owner elsewhere. A
/// reviewer caught it; a test catches it next time.
void main() {
  final submissionSources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (file) =>
            file.path.endsWith('.dart') &&
            (file.path.contains('product_submission') ||
                file.path.contains('missing_product')),
      )
      .toList();

  test('submission sources exist to be checked', () {
    expect(submissionSources, isNotEmpty);
  });

  test('product identity is compared only through GtinIdentity', () {
    // `lib/services/gtin.dart` owns canonical GTIN-14. Zero-padding a barcode
    // anywhere else is a second definition of product identity.
    final offenders = <String>[];
    for (final file in submissionSources) {
      final source = file.readAsStringSync();
      if (source.contains("padLeft(14")) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'use GtinIdentity.canonicalGtin14 instead of padding digits',
    );
  });

  test('evidence content is hashed only by the photo that owns the bytes', () {
    // ProductSubmissionPhoto.contentSha256 is the integrity contract shared
    // with the server's manifest check.
    final offenders = <String>[];
    for (final file in submissionSources) {
      if (file.path.endsWith('product_submission_service.dart')) continue;
      final source = file.readAsStringSync();
      if (source.contains('sha256.convert')) offenders.add(file.path);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'compare ProductSubmissionPhoto.contentSha256 instead of '
          'recomputing the digest',
    );
  });

  test('evidence categories are read through one fromWire', () {
    final offenders = <String>[];
    for (final file in submissionSources) {
      if (file.path.endsWith('product_submission_service.dart')) continue;
      final source = file.readAsStringSync();
      if (source.contains('ProductSubmissionEvidenceCategory.values')) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'use ProductSubmissionEvidenceCategory.fromWire instead of '
          'scanning the enum values',
    );
  });

  test('the consent version has one authored home', () {
    // The string the server records must come from the pinned copy file, never
    // be retyped at a call site.
    final offenders = <String>[];
    for (final file in submissionSources) {
      if (file.path.endsWith('product_submission_consent_copy.dart')) continue;
      final source = file.readAsStringSync();
      if (source.contains('pharmaguide.submission_consent.')) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'reference productSubmissionConsentVersion instead of the literal',
    );
  });
}
