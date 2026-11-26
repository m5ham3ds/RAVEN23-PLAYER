import 'dart:ui';

/// Normalizes the standalone Player's language preference and resolves the
/// System option to one of its two supported locales.
abstract final class PlayerLanguage {
  static const String system = 'system';

  static String normalizePreference(String value) {
    switch (value.trim().toLowerCase()) {
      case system:
        return system;
      case 'ar':
        return 'ar';
      case 'en':
        return 'en';
      default:
        // Migrate old Spanish/Hindi values and any unknown saved codes.
        return 'en';
    }
  }

  static Locale resolve(
    String preference, {
    List<Locale>? systemLocales,
  }) {
    final normalized = normalizePreference(preference);
    if (normalized == 'ar') return const Locale('ar');
    if (normalized == 'en') return const Locale('en');

    final locales = systemLocales ?? PlatformDispatcher.instance.locales;
    final code = locales.isNotEmpty
        ? locales.first.languageCode.toLowerCase()
        : PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return Locale(code == 'ar' ? 'ar' : 'en');
  }
}
