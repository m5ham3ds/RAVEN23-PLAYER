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

    test('migrates unset or legacy English preferences to System', () {
      expect(PlayerLanguage.migratePreference(), PlayerLanguage.system);
      expect(
        PlayerLanguage.migratePreference(legacyPreference: 'en'),
        PlayerLanguage.system,
      );
    });

    test('preserves an old explicit Arabic choice', () {
      expect(PlayerLanguage.migratePreference(legacyPreference: 'ar'), 'ar');
    });

    test('migrates legacy Spanish and Hindi preferences to English', () {
      expect(PlayerLanguage.migratePreference(legacyPreference: 'es'), 'en');
      expect(PlayerLanguage.migratePreference(legacyPreference: 'hi'), 'en');
    });

    test('preserves new explicit English and Arabic choices', () {
      expect(PlayerLanguage.migratePreference(savedPreference: 'en'), 'en');
      expect(PlayerLanguage.migratePreference(savedPreference: 'ar'), 'ar');
    });

    test('normalizes unknown language codes to English', () {
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
