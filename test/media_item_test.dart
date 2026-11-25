import 'package:flutter_test/flutter_test.dart';
import 'package:raven23_player/models/media_item.dart';

void main() {
  group('MediaItem origin detection', () {
    test('maps unexported primary-app downloads to the private content URI', () {
      final item = MediaItem.fromPrimaryDownload({
        'id': 'media-episode-44',
        'title': 'Episode 4',
        'mediaType': 'tv',
        'quality': '1080p',
        'state': 'completed',
        'progress': 100,
        'bytesDownloaded': 2048,
        'createdAt': 1795651200000,
        'contentId': 77,
        'seasonNumber': 2,
        'episodeNumber': 4,
        'posterUrl': 'https://example.invalid/poster.jpg',
        'subtitleUri': 'content://com.m5ham3d.raven23.offline-library/downloads/media-episode-44/subtitle',
        'subtitleName': 'Episode.4.ar.srt',
        'videoUri': 'content://com.m5ham3d.raven23.offline-library/downloads/media-episode-44/video',
        'durationMs': 2400000,
        'sizeBytes': 2048,
        'isPlayable': true,
        'downloadDataJson': '{"title":"Episode 4","subtitle":"S02 • E04 First Light • Server","streamIdentity":{"source":"offline"}}',
      });

      expect(item.origin, MediaOrigin.raven23Download);
      expect(item.isPlayable, isTrue);
      expect(item.contentUri, contains('/media-episode-44/video'));
      expect(item.subtitles, hasLength(1));
      expect(item.subtitles.single.language, 'ar');
      expect(item.mediaType, 'tv');
      expect(item.subtitle, 'S02 • E04 First Light • Server');
      expect(item.contentId, 77);
      expect(item.dateAddedSeconds, 1795651200);
      expect(item.isAccountMedia, isFalse);
    });

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
