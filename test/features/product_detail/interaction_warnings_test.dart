import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';

void main() {
  group('InteractionWarning.fromJson', () {
    test('parses valid JSON', () {
      final json = {
        'severity': 'caution',
        'evidence_level': 'established',
        'title': 'Ginkgo + Anticoagulants',
        'mechanism': 'Increased bleeding risk',
        'management': 'Monitor closely',
        'source_urls': ['https://pubmed.ncbi.nlm.nih.gov/12345/'],
      };
      final warning = InteractionWarning.fromJson(json);
      expect(warning.severity, Severity.caution);
      expect(warning.evidenceLevel, EvidenceLevel.established);
      expect(warning.title, 'Ginkgo + Anticoagulants');
      expect(warning.sourceUrls, hasLength(1));
    });

    test('handles missing fields gracefully', () {
      final json = <String, dynamic>{
        'title': 'Test warning',
      };
      final warning = InteractionWarning.fromJson(json);
      expect(warning.severity, Severity.safe);
      expect(warning.evidenceLevel, EvidenceLevel.theoretical);
      expect(warning.sourceUrls, isEmpty);
    });
  });

  group('InteractionWarning sorting', () {
    test('sorts by severity weight descending', () {
      final warnings = [
        const InteractionWarning(
          severity: Severity.monitor,
          evidenceLevel: EvidenceLevel.theoretical,
          title: 'Low',
          mechanism: '',
          management: '',
        ),
        const InteractionWarning(
          severity: Severity.contraindicated,
          evidenceLevel: EvidenceLevel.established,
          title: 'Critical',
          mechanism: '',
          management: '',
        ),
        const InteractionWarning(
          severity: Severity.caution,
          evidenceLevel: EvidenceLevel.probable,
          title: 'Medium',
          mechanism: '',
          management: '',
        ),
      ];
      warnings.sort((a, b) => b.severity.weight.compareTo(a.severity.weight));
      expect(warnings[0].title, 'Critical');
      expect(warnings[1].title, 'Medium');
      expect(warnings[2].title, 'Low');
    });
  });
}
