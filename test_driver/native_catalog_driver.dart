import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final target = Platform.environment['VERIFY_EVIDENCE_DIR'];
  if (target == null || target.isEmpty) {
    throw StateError(
      'VERIFY_EVIDENCE_DIR must name a new durable evidence folder',
    );
  }
  final directory = Directory(target);
  if (directory.existsSync()) {
    throw StateError('Evidence folder already exists');
  }
  directory.createSync(recursive: true);
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name)) return false;
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      // Screenshots are retained separately, including on a failed assertion.
      final report = Map<String, dynamic>.from(data ?? {});
      report.remove('screenshots');
      await File(
        '${directory.path}/native_journey.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    },
  );
}
