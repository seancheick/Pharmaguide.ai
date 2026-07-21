// Barrel: re-exports the split stack provider files so existing
// imports continue to compile unchanged.
//
// The original single-file implementation grew to ~940 lines covering
// four distinct concerns (CRUD, safety aggregation, synergy, helpers).
// It's now split into focused files under this directory; importers
// should prefer the granular files for new code but may continue to
// import this barrel.
//
// What lives where now:
//   - active_stack_provider.dart      → activeStackProvider,
//                                       stackEntryForDsldIdProvider,
//                                       StackActions, stackActionsProvider
//   - favorites_providers.dart        → favoritesProvider,
//                                       isFavoriteProvider,
//                                       FavoritesActions, favoritesActionsProvider
//   - stack_safety_providers.dart     → safetyCheckForAddProvider,
//                                       stackSafetyReportProvider,
//                                       recalledIngredientsReportProvider,
//                                       depletionReportProvider
//   - stack_nutrient_providers.dart   → stackNutrientStatusesProvider,
//                                       stackDoseThresholdAlertsProvider
//   - synergy_report_provider.dart    → synergyReportProvider
//   - stack_provider_helpers.dart     → library-internal helpers
//                                       (NOT re-exported)

export 'active_stack_provider.dart';
export 'favorites_providers.dart';
export 'stack_nutrient_providers.dart';
export 'stack_safety_providers.dart';
export 'synergy_report_provider.dart';
