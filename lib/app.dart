import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:raven23/provider/app_dependency_provider.dart';
import 'package:raven23/provider/offline_download_provider.dart';
import 'package:raven23/provider/recently_watched_provider.dart';
import 'package:raven23/provider/settings_provider.dart';
import 'package:raven23/provider/wellness_provider.dart';

import 'screens/library_screen.dart';

class Raven23PlayerApp extends StatelessWidget {
  Raven23PlayerApp({super.key, required this.settings});

  final SettingsProvider settings;

  static const Color ravenRed = Color(0xFFFF2020);
  static const Color background = Color(0xFF090909);
  static const Color surface = Color(0xFF171717);

  ThemeData _themeFor(String mode) {
    final isLight = mode == 'light';
    final isAmoled = mode == 'amoled';
    final brightness = isLight ? Brightness.light : Brightness.dark;
    final page = isLight
        ? const Color(0xFFF5F5F6)
        : isAmoled
            ? Colors.black
            : background;
    final card = isLight
        ? Colors.white
        : isAmoled
            ? const Color(0xFF090909)
            : surface;
    final ink = isLight ? const Color(0xFF171719) : Colors.white;
    final scheme = ColorScheme.fromSeed(
      seedColor: ravenRed,
      brightness: brightness,
      surface: card,
    ).copyWith(
      primary: ravenRed,
      onPrimary: Colors.white,
      surface: card,
      onSurface: ink,
    );
    final baseTextTheme =
        isLight ? ThemeData.light().textTheme : ThemeData.dark().textTheme;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: page,
      textTheme: baseTextTheme.apply(bodyColor: ink, displayColor: ink),
      iconTheme: IconThemeData(color: ink),
      dividerTheme: DividerThemeData(
        color: ink.withValues(alpha: 0.12),
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: page,
        foregroundColor: ink,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: ravenRed.withValues(alpha: 0.18),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:
            isLight ? const Color(0xFF202024) : const Color(0xFF292929),
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<AppDependencyProvider>(
          create: (_) => AppDependencyProvider(),
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
        supportedLocales: const [
          Locale('en'),
          Locale('ar'),
          Locale('es'),
          Locale('hi'),
        ],
        path: 'packages/raven23/assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: Locale(settings.appLanguage),
        child: Builder(
          builder: (context) => Consumer<SettingsProvider>(
            builder: (context, currentSettings, _) => MaterialApp(
              title: 'RAVEN23 Player',
              debugShowCheckedModeBanner: false,
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              theme: _themeFor(currentSettings.appTheme),
              home: const LibraryScreen(),
            ),
          ),
        ),
      ),
    );
  }
}
