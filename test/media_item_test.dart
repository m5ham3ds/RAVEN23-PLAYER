import 'package:flutter_test/flutter_test.dart';
import 'package:raven23_player/models/media_item.dart';

void main() {
  group('MediaItem origin detection', () {
    test('recognizes the shared Movies/RAVEN23 library', () {
      final item = MediaItem.fromMaps(
        {
          'id': '42',
          'displayName': 'A Film.mp4',
          'relativePath': 'Movies/RAVEN23/Library/',
          'uri': 'content://media/external/video/media/42',
          'durationMs': 60000,
          'sizeBytes': 1000,
          'dateAddedSeconds': 1,
        },
        const [],
      );
      expect(item.origin, MediaOrigin.raven23Library);
    });

    test('keeps ordinary phone videos local-only', () {
      final item = MediaItem.fromMaps(
        {
          'id': '43',
          'displayName': 'Camera clip.mp4',
          'relativePath': 'DCIM/Camera/',
          'uri': 'content://media/external/video/media/43',
          'durationMs': 120000,
          'sizeBytes': 2000,
          'dateAddedSeconds': 1,
        },
        const [],
      );
      expect(item.origin, MediaOrigin.deviceLocal);
      expect(item.isAccountMedia, isFalse);
    });

    test('matches multiple subtitle sidecars under the subtitle folder', () {
      final item = MediaItem.fromMaps(
        {
          'id': '44',
          'displayName': 'A Film.mp4',
          'relativePath': 'DCIM/RAVEN23/MOVIES/',
          'uri': 'content://media/external/video/media/44',
          'durationMs': 60000,
          'sizeBytes': 1000,
          'dateAddedSeconds': 1,
        },
        [
          {
            'displayName': 'A Film.en.vtt',
            'relativePath': 'DCIM/RAVEN23/MOVIES/SUBTITLE/',
            'path': '/storage/emulated/0/DCIM/RAVEN23/MOVIES/SUBTITLE/A Film.en.vtt',
            'uri': 'content://media/external/file/9',
          },
          {
            'displayName': 'A Film.ar.vtt',
            'relativePath': 'DCIM/RAVEN23/MOVIES/SUBTITLE/',
            'path': '/storage/emulated/0/DCIM/RAVEN23/MOVIES/SUBTITLE/A Film.ar.vtt',
            'uri': 'content://media/external/file/10',
          },
        ],
      );
      expect(item.origin, MediaOrigin.raven23Library);
      expect(item.subtitles, hasLength(2));
      expect(item.subtitles.map((s) => s.language), containsAll(['en', 'ar']));
    });
  });
}
