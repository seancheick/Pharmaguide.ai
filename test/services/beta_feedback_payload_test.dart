import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Safety net for the beta-feedback path: the only thing that may leave the
/// device is a small set of safe, structured tags plus a synthesized message.
/// No profile, stack, medication, or free-text/prose ever reaches Sentry.
void main() {
  group('beta feedback — safe payload', () {
    test('buildFeedbackTags emits only the allowed safe keys', () {
      final tags = CrashReportingService.buildFeedbackTags(
        category: PgFeedbackCategory.confusingResult,
        impact: PgFeedbackImpact.frustrating,
        catalogVersion: '2026.06.20.213929',
      );
      expect(tags.keys.toSet(), {
        'pg.kind',
        'feedback.category',
        'feedback.impact',
        'pg.catalog_version',
      });
      expect(tags['pg.kind'], 'beta_feedback');
      expect(tags['feedback.category'], 'confusing_result');
      expect(tags['feedback.impact'], 'frustrating');
      expect(tags['pg.catalog_version'], '2026.06.20.213929');
    });

    test('catalog version is omitted when null or empty', () {
      for (final v in <String?>[null, '']) {
        final tags = CrashReportingService.buildFeedbackTags(
          category: PgFeedbackCategory.bug,
          impact: PgFeedbackImpact.minor,
          catalogVersion: v,
        );
        expect(tags.containsKey('pg.catalog_version'), isFalse);
      }
    });

    test('no tag key or value is sensitive, for every enum combination', () {
      for (final c in PgFeedbackCategory.values) {
        for (final i in PgFeedbackImpact.values) {
          final tags = CrashReportingService.buildFeedbackTags(
            category: c,
            impact: i,
            catalogVersion: 'v1',
          );
          tags.forEach((k, v) {
            expect(
              CrashReportingService.isSensitiveForTest(k),
              isFalse,
              reason: 'tag key "$k" must not be sensitive',
            );
            expect(
              CrashReportingService.isSensitiveForTest(v),
              isFalse,
              reason: 'tag value "$v" must not be sensitive',
            );
          });
        }
      }
    });

    test('synthesized message is labels-only (no prose channel)', () {
      final msg = CrashReportingService.feedbackMessageForTest(
        PgFeedbackCategory.wrongProductData,
        PgFeedbackImpact.blocksMe,
      );
      expect(msg, 'Beta feedback: Wrong product data / Blocks me');
    });

    test('controlled clinical beta categories are exact and complete', () {
      expect(
        {for (final category in PgFeedbackCategory.values) category.tag},
        containsAll({
          'clinical_false_positive',
          'clinical_false_negative',
          'clinical_identity_normalization_failure',
          'clinical_wording_confusion',
          'clinician_report_interpretation',
          'search_no_result',
          'clinical_class_mapping_missing',
        }),
      );
    });

    test(
      'captureBetaFeedback reports disabled when Sentry is not enabled',
      () async {
        final result = await CrashReportingService().captureBetaFeedback(
          category: PgFeedbackCategory.bug,
          impact: PgFeedbackImpact.minor,
        );

        expect(result, PgFeedbackSubmissionResult.disabled);
      },
    );

    test(
      '_scrubEvent drops contact fields on a feedback event, keeps message',
      () {
        final event = SentryEvent(
          type: 'feedback',
          contexts: Contexts(
            feedback: SentryFeedback(
              message: 'Beta feedback: Bug / Minor',
              contactEmail: 'leak@example.com',
              name: 'Jane Doe',
            ),
          ),
          level: SentryLevel.info,
        );

        final scrubbed = CrashReportingService.scrubEventForTest(event, Hint());

        expect(scrubbed, isNotNull);
        final fb = scrubbed!.contexts.feedback!;
        expect(
          fb.contactEmail,
          isNull,
          reason: 'contact email must be dropped',
        );
        expect(fb.name, isNull, reason: 'name must be dropped');
        expect(fb.message, 'Beta feedback: Bug / Minor');
      },
    );
  });
}
