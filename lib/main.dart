import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:raven23/constants/app_constants.dart' show sharedPrefsSingleton;
import 'package:raven23/provider/wellness_provider.dart';
import 'package:raven23/provider/app_dependency_provider.dart';

import 'utils/player_language.dart';
import 'package:raven23/provider/settings_provider.dart';
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

  final settings = SettingsProvider();
  await Future.wait<void>([
    settings.getCurrentThemeMode(),
    settings.getAppLanguage(),
    settings.getSeekDuration(),
    settings.getHoldSpeeds(),
    settings.getViewMode(),
    settings.getMaxBufferDuration(),
    settings.getVideoResolution(),
    settings.getSubtitleLanguage(),
    settings.getPreferredVidkingAudioLanguage(),
    settings.getForegroundSubtitleColor(),
    settings.getBackgroundSubtitleColor(),
    settings.getSubtitleSize(),
    settings.getSubtitleMode(),
    settings.getStreamProviderOrder(),
    settings.getPlayerTimeStyle(),
    settings.getSubtitleStyle(),
    settings.getEnableNextEpisodeButton(),
    settings.getIntroDbSettings(),
    settings.getPlayerAmbientGlowEnabled(),
    settings.getAutoPipOnLeave(),
    settings.getAutoLoadSources(),
    settings.getStreamingDnd(),
  ]);
  final dependencies = AppDependencyProvider();
  await Future.wait<void>([
    dependencies.getOccasionalTheme(),
    dependencies.getAmbientMode(),
  ]);

  // Migrate obsolete language preferences without changing System selection.
  final language = PlayerLanguage.normalizePreference(settings.appLanguage);
  if (language != settings.appLanguage) settings.appLanguage = language;

  settings.completeHydration();
  runApp(
    Raven23PlayerApp(settings: settings, dependencies: dependencies),
  );
}
