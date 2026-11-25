import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:raven23/constants/app_constants.dart' show sharedPrefsSingleton;
import 'package:raven23/provider/wellness_provider.dart';
import 'package:raven23/singleton/sharedpreferences_singleton.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // No account or backend secrets are bundled in the standalone Player.
  // These safe defaults satisfy the original PlayerOne dependency bootstrap;
  // private offline playback itself does not use the configured endpoint.
  dotenv.testLoad(
    fileInput: '''
RAVEN23_API_URL=https://example.invalid
TMDB_API_KEY=
MIXPANEL_API_KEY=
''',
  );
  await EasyLocalization.ensureInitialized();
  sharedPrefsSingleton = await SharedPreferencesSingleton.getInstance();
  await WellnessProvider.instance.initialize();
  runApp(const Raven23PlayerApp());
}
