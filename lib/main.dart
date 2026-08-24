import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/config/public_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(HhmApp(config: PublicConfig.fromEnvironment()));
}
