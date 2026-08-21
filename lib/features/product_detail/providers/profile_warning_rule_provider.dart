import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';
import 'package:pharmaguide/services/warnings/warning_rule_ref_resolver.dart';

/// Rehydrates schema-3 warning references from the versioned interaction DB.
///
/// Schema-2.x blobs do not carry `warning_rule_refs`; that compatibility path
/// returns before touching the interaction DB. Every schema-3 resolution
/// failure remains an [AsyncError] so the product page can show its explicit
/// "personalized checks unavailable" hedge. An error must never look like a
/// successful lookup with no warnings.
final profileWarningRuleWarningsProvider = FutureProvider.family
    .autoDispose<List<InteractionWarning>, String>((ref, dsldId) async {
      try {
        final blob = await ref.watch(detailBlobProvider(dsldId).future);
        final ruleIds = warningRuleIds(blob);
        if (ruleIds.isEmpty) return const <InteractionWarning>[];

        final database = ref.watch(interactionDatabaseProvider);
        final rulesById = await database.lookupProfileWarningRules(ruleIds);
        return resolveWarningRuleRefs(
          blob,
          rulesById,
        ).map(InteractionWarning.fromJson).toList(growable: false);
      } on Object catch (error, stackTrace) {
        CrashReportingService().recordError(
          error,
          stackTrace,
          fatal: false,
          hint: 'profile_warning_rules:resolution_failed',
        );
        rethrow;
      }
    }, retry: (_, _) => null);
