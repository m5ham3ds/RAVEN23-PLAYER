import 'package:flutter/material.dart';

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
    return MaterialApp(
      title: 'RAVEN23 Player',
      debugShowCheckedModeBanner: false,
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
    );
  }
}
