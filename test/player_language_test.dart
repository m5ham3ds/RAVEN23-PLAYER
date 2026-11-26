import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:raven23_player/utils/player_language.dart';

void main() {
  group('PlayerLanguage', () {
    test('keeps only Arabic, English, and System preferences', () {
      expect(PlayerLanguage.normalizePreference('ar'), 'ar');
      expect(PlayerLanguage.normalizePreference('en'), 'en');
      expect(PlayerLanguage.normalizePreference('system'), 'system');
    });

    test('migrates previously saved Spanish and Hindi to English', () {
      expect(PlayerLanguage.normalizePreference('es'), 'en');
      expect(PlayerLanguage.normalizePreference('hi'), 'en');
      expect(PlayerLanguage.normalizePreference('unknown'), 'en');
    });

    test('System resolves to Arabic on an Arabic device', () {
      expect(
        PlayerLanguage.resolve(
          PlayerLanguage.system,
          systemLocales: const [Locale('ar', 'SD')],
        ),
        const Locale('ar'),
      );
    });

    test('System resolves to English on other devices', () {
      expect(
        PlayerLanguage.resolve(
          PlayerLanguage.system,
          systemLocales: const [Locale('fr', 'FR')],
        ),
        const Locale('en'),
      );
    });

    test('explicit selection is not overridden by system locale', () {
      expect(
        PlayerLanguage.resolve(
          'en',
          systemLocales: const [Locale('ar', 'SD')],
        ),
        const Locale('en'),
      );
    });
  });
}
