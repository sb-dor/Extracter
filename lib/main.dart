import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/common/utils/app_zone.dart';
import 'package:extracter/src/common/widget/app.dart';
import 'package:extracter/src/common/widget/fatal_error_app.dart';
import 'package:flutter/widgets.dart';
import 'package:l/l.dart';

void main() => appZone(() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final dependencies = await Dependencies.initialize();
    runApp(dependencies.inject(child: const App()));
  } on Object catch (error, stackTrace) {
    l.e('Initialization failed: ${error.runtimeType}', stackTrace);
    runApp(FatalErrorApp(error: error));
  }
});
