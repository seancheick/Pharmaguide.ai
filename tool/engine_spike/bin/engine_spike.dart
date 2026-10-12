// Server-side engine spike entry. Same source runs under:
//   dart run    --packages=tool/engine_spike/.build/package_config.json ...
//   dart compile exe / js  (see tool/engine_spike/build.sh)
// Line 1 of stdout: canonical findings JSON. Line 2: `TIMING {...}`.
import 'dart:convert';

import 'package:engine_spike/findings_codec.dart';
import 'package:engine_spike/spike_runner.dart';
import 'package:engine_spike/src/fixture_data.g.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

double _ms(Stopwatch sw) => sw.elapsedMicroseconds / 1000.0;

Future<void> main() async {
  final total = Stopwatch()..start();

  // Cold: parse rules + reference data, then run the fixture once.
  final parse = Stopwatch()..start();
  final data = SpikeData.parse(
    stackJson: kStackJson,
    interactionsJson: kInteractionsJson,
    drugClassMapJson: kDrugClassMapJson,
    productsJson: kProductsJson,
    depletionsJson: kDepletionsJson,
  );
  final parseMs = _ms(parse);
  final candidate =
      (jsonDecode(kStackJson) as Map<String, dynamic>)['candidate_dsld_id']
          as String;

  final run = Stopwatch()..start();
  final pre = await preAddCheck(data, candidate);
  final dep = depletionReport(data);
  final fixtureRunMs = _ms(run);

  print(
    jsonEncode(
      encodeFindings(
        preAddResults: pre.results,
        preAddChecksIncomplete: pre.checksIncomplete,
        depletionStatus: dep.status,
        depletions: dep.matches,
      ),
    ),
  );

  // 10-item stack over the FULL live ruleset (132 rules) + all reference data.
  final benchParse = Stopwatch()..start();
  final bench = benchData(data, kInteractionsAllLiveJson, kDrugClassMapJson);
  final benchParseMs = _ms(benchParse);

  Future<int> once() async {
    final p = await preAddCheck(bench, candidate);
    final pivot = await stackPivot(bench);
    final d = depletionReport(bench);
    return p.results.length + pivot + d.matches.length;
  }

  final cold = Stopwatch()..start();
  final benchFindings = await once();
  final benchColdMs = _ms(cold);
  const iterations = 200;
  final warm = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    await once();
  }
  final benchWarmAvgMs = _ms(warm) / iterations;

  print(
    'TIMING ${jsonEncode({
      'fixture_parse_ms': parseMs,
      'fixture_run_ms': fixtureRunMs,
      'bench10_parse_ms': benchParseMs,
      'bench10_cold_ms': benchColdMs,
      'bench10_warm_avg_ms': benchWarmAvgMs,
      'bench10_findings': benchFindings,
      'total_ms': _ms(total),
      'recorded_errors': CrashReportingService.recorded,
    })}',
  );
}
