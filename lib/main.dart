import 'package:flutter/widgets.dart';
import 'package:ores_otel_flutter/ores_otel_flutter.dart';

import 'src/app.dart';
import 'src/config/public_config.dart';

void main() {
  final logger = Logger(appName: 'hhm_flutter');
  runOresFlutterApp(
    appName: 'hhm_flutter',
    emitToDeveloperLog: false,
    sinks: [NextLoggersStartupDiagnosticSink(logger: logger)],
    builder: (_) => HhmApp(config: PublicConfig.fromEnvironment()),
  );
}
