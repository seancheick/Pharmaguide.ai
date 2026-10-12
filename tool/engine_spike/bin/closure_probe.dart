// Compile-only probe: imports EVERY engine file (lib/services/{fit_score,warnings,stack})
// through the overlay. If this compiles with dart2js and AOT, no engine file reaches
// dart:ui, dart:io, dart:ffi, Drift, Riverpod or Sentry. Generated list; see build.sh.
// ignore_for_file: unused_import

import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart' as m0;
import 'package:pharmaguide/services/fit_score/e2a_goal_calculator.dart' as m1;
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart' as m2;
import 'package:pharmaguide/services/fit_score/e2c_medical_calculator.dart' as m3;
import 'package:pharmaguide/services/fit_score/fit_display.dart' as m4;
import 'package:pharmaguide/services/fit_score/fit_score_service.dart' as m5;
import 'package:pharmaguide/services/warnings/condition_gate.dart' as m6;
import 'package:pharmaguide/services/warnings/interaction_warning.dart' as m7;
import 'package:pharmaguide/services/warnings/profile_gate_evaluator.dart' as m8;
import 'package:pharmaguide/services/warnings/profile_gate_summary_filter.dart' as m9;
import 'package:pharmaguide/services/warnings/warning_rule_ref_resolver.dart' as m10;
import 'package:pharmaguide/services/stack/coverage_analyzer.dart' as m11;
import 'package:pharmaguide/services/stack/depletion_checker.dart' as m12;
import 'package:pharmaguide/services/stack/depletion_watch.dart' as m13;
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart' as m14;
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart' as m15;
import 'package:pharmaguide/services/stack/research_pair_lookup.dart' as m16;
import 'package:pharmaguide/services/stack/stack_dose_summer.dart' as m17;
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart' as m18;
import 'package:pharmaguide/services/stack/stack_interaction_checker.dart' as m19;
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart' as m20;
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart' as m21;
import 'package:pharmaguide/services/stack/stack_reminder_scheduler.dart' as m22;
import 'package:pharmaguide/services/stack/stack_safety_report.dart' as m23;
import 'package:pharmaguide/services/stack/stack_safety_scorer.dart' as m24;
import 'package:pharmaguide/services/stack/stack_ul_checker.dart' as m25;
import 'package:pharmaguide/services/stack/synergy_result.dart' as m26;
import 'package:pharmaguide/services/stack/timing_evaluation_service.dart' as m27;
import 'package:pharmaguide/services/stack/timing_guidance_builder.dart' as m28;

void main() => print('closure-probe ok: 29 engine files');
