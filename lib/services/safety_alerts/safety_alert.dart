/// Strict, authored regulatory-event feed model.
///
/// The app never reconstructs an alert from the long-lived banned-ingredient
/// reference data. It consumes only the human-approved, checksum-verified
/// fast-lane record and matches exact IDs locally.
enum SafetyAlertEventType { ingredientBan, productRecall }

enum SafetyAlertDisposition { block, review }

final class SafetyAlert {
  const SafetyAlert({
    required this.alertId,
    required this.revision,
    required this.eventType,
    required this.sourceUrl,
    required this.headline,
    required this.body,
    required this.action,
    required this.disposition,
    required this.resolvedDsldIds,
    required this.ingredientCanonicalIds,
  });

  final String alertId;
  final int revision;
  final SafetyAlertEventType eventType;
  final Uri sourceUrl;
  final String headline;
  final String body;
  final String action;
  final SafetyAlertDisposition disposition;
  final Set<String> resolvedDsldIds;
  final Set<String> ingredientCanonicalIds;

  factory SafetyAlert.fromJson(Map<String, Object?> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Safety alert $key is required.');
      }
      return value.trim();
    }

    final id = requiredString('alert_id');
    if (!RegExp(r'^SA_[0-9]{4}_[0-9]{4}$').hasMatch(id)) {
      throw const FormatException('Safety alert id is malformed.');
    }
    final revision = json['revision'];
    if (revision is! int || revision < 1) {
      throw const FormatException('Safety alert revision is malformed.');
    }
    final eventType = switch (requiredString('event_type')) {
      'ingredient_ban' => SafetyAlertEventType.ingredientBan,
      'product_recall' => SafetyAlertEventType.productRecall,
      _ => throw const FormatException('Safety alert event type is unsupported.'),
    };
    final disposition = switch (requiredString('consumer_disposition')) {
      'block' => SafetyAlertDisposition.block,
      'review' => SafetyAlertDisposition.review,
      _ => throw const FormatException('Safety alert disposition is unsupported.'),
    };
    final sourceUrl = Uri.tryParse(requiredString('source_url'));
    if (sourceUrl == null || sourceUrl.scheme != 'https' || sourceUrl.host.isEmpty) {
      throw const FormatException('Safety alert source is not an HTTPS URL.');
    }
    final resolved = _stringSet(json['resolved_dsld_ids'], 'resolved_dsld_ids');
    final scope = json['scope'];
    if (scope is! Map) throw const FormatException('Safety alert scope is malformed.');
    final ingredients = _stringSet(scope['ingredient_canonical_ids'], 'scope.ingredient_canonical_ids');
    return SafetyAlert(
      alertId: id,
      revision: revision,
      eventType: eventType,
      sourceUrl: sourceUrl,
      headline: requiredString('headline'),
      body: requiredString('body'),
      action: requiredString('action'),
      disposition: disposition,
      resolvedDsldIds: resolved,
      ingredientCanonicalIds: ingredients,
    );
  }

  bool appliesTo({required String dsldId, required Iterable<String> ingredientCanonicalIds}) {
    if (resolvedDsldIds.contains(dsldId)) return true;
    return ingredientCanonicalIds.any(this.ingredientCanonicalIds.contains);
  }

  static Set<String> _stringSet(Object? value, String field) {
    if (value is! List) throw FormatException('Safety alert $field is malformed.');
    final result = <String>{};
    for (final item in value) {
      if (item is! String || item.trim().isEmpty) {
        throw FormatException('Safety alert $field has an invalid value.');
      }
      result.add(item.trim());
    }
    return Set.unmodifiable(result);
  }
}
