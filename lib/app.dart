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
  const Raven23PlayerApp({super.key});

  static const Color ravenRed = Color(0xFFFF2020);
  static const Color background = Color(0xFF090909);
  static const Color surface = Color(0xFF171717);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: ravenRed,
      brightness: Brightness.dark,
      surface: surface,
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),
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
        supportedLocales: const [Locale('en'), Locale('ar')],
        path: 'packages/raven23/assets/translations',
        fallbackLocale: const Locale('en'),
        child: Builder(
          builder: (context) => MaterialApp(
            title: 'RAVEN23 Player',
            debugShowCheckedModeBanner: false,
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: scheme,
              scaffoldBackgroundColor: background,
              appBarTheme: const AppBarTheme(
                backgroundColor: background,
                foregroundColor: Colors.white,
                centerTitle: false,
              ),
              cardTheme: CardThemeData(
                color: surface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              navigationBarTheme: NavigationBarThemeData(
                backgroundColor: surface,
                indicatorColor: ravenRed.withValues(alpha: 0.18),
              ),
            ),
            home: const LibraryScreen(),
          ),
        ),
      ),
    );
  }
}
