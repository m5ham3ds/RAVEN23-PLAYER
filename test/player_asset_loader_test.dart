import 'package:flutter_test/flutter_test.dart';
import 'package:raven23_player/utils/player_asset_loader.dart';

void main() {
  group('PlayerAssetLoader', () {
    test('overlays Player strings without dropping package translations', () {
      final merged = PlayerAssetLoader.mergeTranslations(
        {
          'settings': 'Settings',
          'nested': {'keep': 'base', 'replace': 'old'},
        },
        {
          'player_library': 'Library',
          'nested': {'replace': 'new', 'added': 'player'},
        },
      );

      expect(merged, {
        'settings': 'Settings',
        'player_library': 'Library',
        'nested': {
          'keep': 'base',
          'replace': 'new',
          'added': 'player',
        },
      });
    });
  });
}
