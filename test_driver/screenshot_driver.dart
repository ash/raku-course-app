// Driver for the App Store screenshot run.
//
//   flutter drive \
//     --driver=test_driver/screenshot_driver.dart \
//     --target=integration_test/screenshot_test.dart \
//     -d "iPhone 17 Pro Max" --dart-define=SS_DEVICE=iphone-6.9
//
// Screenshots requested by the test (named "<device>/<slug>") are written to
// appstore/screenshots/<device>/<slug>.png.
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('appstore/screenshots/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
