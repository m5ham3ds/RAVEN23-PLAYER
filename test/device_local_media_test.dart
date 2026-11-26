import 'package:flutter_test/flutter_test.dart';
import 'package:raven23_player/models/media_item.dart';
import 'package:raven23_player/utils/device_local_media.dart';

MediaItem _item(String id, MediaOrigin origin) => MediaItem(
      id: id,
      title: id,
      origin: origin,
      contentUri: 'content://media/external/video/media/$id',
      relativePath: 'DCIM/Camera',
      durationMs: 60000,
      sizeBytes: 1000,
      dateAddedSeconds: 1,
      subtitles: const [],
    );

void main() {
  group('deviceLocalMedia', () {
    test('keeps phone files and excludes RAVEN23 library and downloads', () {
      final result = deviceLocalMedia([
        _item('phone-1', MediaOrigin.deviceLocal),
        _item('primary-library-1', MediaOrigin.raven23Library),
        _item('primary-download-1', MediaOrigin.raven23Download),
        _item('phone-2', MediaOrigin.deviceLocal),
      ]);

      expect(result.map((item) => item.id), ['phone-1', 'phone-2']);
    });

    test('does not expose non-playable phone items', () {
      final item = _item('missing', MediaOrigin.deviceLocal);
      final unavailable = MediaItem(
        id: item.id,
        title: item.title,
        origin: item.origin,
        contentUri: item.contentUri,
        relativePath: item.relativePath,
        durationMs: item.durationMs,
        sizeBytes: item.sizeBytes,
        dateAddedSeconds: item.dateAddedSeconds,
        subtitles: const [],
        isPlayable: false,
      );

      expect(deviceLocalMedia([unavailable]), isEmpty);
    });

    test('returns an immutable playlist', () {
      final result = deviceLocalMedia([
        _item('phone-1', MediaOrigin.deviceLocal),
      ]);

      expect(
        () => result.add(_item('phone-2', MediaOrigin.deviceLocal)),
        throwsUnsupportedError,
      );
    });
  });
}
