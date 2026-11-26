import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:raven23/constants/theme_data.dart';
import 'package:raven23/models/app_colors.dart';
import 'package:raven23/provider/app_dependency_provider.dart';
import 'package:raven23/provider/offline_download_provider.dart';
import 'package:raven23/provider/recently_watched_provider.dart';
import 'package:raven23/provider/settings_provider.dart';
import 'package:raven23/provider/wellness_provider.dart';
import 'package:raven23/widgets/occasional_effect_overlay.dart';

import 'screens/library_screen.dart';
import 'utils/player_language.dart';

class Raven23PlayerApp extends StatelessWidget {
  const Raven23PlayerApp({
    super.key,
    required this.settings,
    required this.dependencies,
  });

  final SettingsProvider settings;
  final AppDependencyProvider dependencies;

  static const Color ravenRed = Color(0xFFFF0000);
  static const Color background = Color(0xFF090909);
  static const Color surface = Color(0xFF171717);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<AppDependencyProvider>.value(
          value: dependencies,
        ),
        ChangeNotifierProvider<RecentProvider>(
          create: (_) => RecentProvider(),
        ),
        ChangeNotifierProvider<OfflineDownloadProvider>(
          create: (_) => OfflineDownloadProvider(),
        ),
        ChangeNotifierProvider<WellnessProvider>.value(
          value: WellnessProvider.instance,
        ),
      ],
      child: EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ar')],
        path: 'packages/raven23/assets/translations',
        fallbackLocale: const Locale('en'),
        saveLocale: false,
        startLocale: PlayerLanguage.resolve(settings.appLanguage),
        child: _LocalizedPlayerApp(settings: settings),
      ),
    );
  }
}

class _LocalizedPlayerApp extends StatefulWidget {
  const _LocalizedPlayerApp({required this.settings});

  final SettingsProvider settings;

  @override
  State<_LocalizedPlayerApp> createState() => _LocalizedPlayerAppState();
}

class _LocalizedPlayerAppState extends State<_LocalizedPlayerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (widget.settings.appLanguage != PlayerLanguage.system) return;
    final next = PlayerLanguage.resolve(
      PlayerLanguage.system,
      systemLocales: locales,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || context.locale.languageCode == next.languageCode) return;
      context.setLocale(next);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsProvider, AppDependencyProvider>(
      builder: (context, currentSettings, appDependencies, _) {
        final isDark = currentSettings.appTheme != 'light';
        final appColor = AppColorsList().appColors(isDark).first;
        final theme = Styles.themeData(
          appThemeMode: currentSettings.appTheme,
          isM3Enabled: currentSettings.isMaterial3Enabled,
          lightDynamicColor: null,
          darkDynamicColor: null,
          context: context,
          appColor: appColor,
          compactCorners: true,
          occasionalTheme: appDependencies.activeOccasionalTheme,
          ambientColor: appDependencies.activeAmbientColor,
        );

        return MaterialApp(
          title: 'RAVEN23 Player',
          debugShowCheckedModeBanner: false,
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          theme: theme,
          builder: (context, child) => Stack(
            fit: StackFit.expand,
            children: [
              child ?? const SizedBox.shrink(),
              OccasionalEffectOverlay(
                theme: appDependencies.activeOccasionalTheme,
                enabled: appDependencies.shouldShowOccasionalEffects,
                television: false,
                visibilityListenable: appDependencies,
                visibilityResolver: () =>
                    appDependencies.shouldShowOccasionalEffects,
              ),
            ],
          ),
          home: const LibraryScreen(),
        );
      },
    );
  }
}
