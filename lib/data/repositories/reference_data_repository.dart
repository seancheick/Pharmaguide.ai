import 'dart:convert';
import 'package:flutter/services.dart';

class ReferenceDataRepository {
  Map<String, dynamic>? _taxonomyCache;
  Map<String, dynamic>? _goalsCache;
  Map<String, dynamic>? _rdaCache;
  Map<String, dynamic>? _timingCache;

  Future<Map<String, dynamic>> loadClinicalRiskTaxonomy() async {
    _taxonomyCache ??=
        await _loadJson('assets/reference_data/clinical_risk_taxonomy.json');
    return _taxonomyCache!;
  }

  Future<Map<String, dynamic>> loadGoalMappings() async {
    _goalsCache ??=
        await _loadJson('assets/reference_data/user_goals_to_clusters.json');
    return _goalsCache!;
  }

  Future<Map<String, dynamic>> loadRdaOptimalUls() async {
    _rdaCache ??=
        await _loadJson('assets/reference_data/rda_optimal_uls.json');
    return _rdaCache!;
  }

  Future<Map<String, dynamic>> loadTimingRules() async {
    _timingCache ??=
        await _loadJson('assets/reference_data/timing_rules.json');
    return _timingCache!;
  }

  Future<Map<String, dynamic>> _loadJson(String path) async {
    final raw = await rootBundle.loadString(path);
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
