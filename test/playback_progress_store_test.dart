import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:raven23_player/models/media_item.dart';
import 'package:raven23_player/services/playback_progress_store.dart';

MediaItem localItem(String id) => MediaItem(
      id: id,
      title: 'Sample',
      origin: MediaOrigin.deviceLocal,
      contentUri: 'content://media/video/$id',
      relativePath: 'DCIM/Camera/',
      durationMs: 90000,
      sizeBytes: 1024,
      dateAddedSeconds: 1,
      subtitles: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists and restores a local-device playback position', () async {
    final store = await PlaybackProgressStore.create();
    final item = localItem('phone-video-1');

    await store.write(item, positionMs: 45000, durationMs: 90000);
    final restored = await store.read(item);

    expect(restored?.positionMs, 45000);
    expect(restored?.durationMs, 90000);
  });

  test('clamps invalid positions to the known duration', () async {
    final store = await PlaybackProgressStore.create();
    final item = localItem('phone-video-2');

    await store.write(item, positionMs: 120000, durationMs: 90000);
    expect((await store.read(item))?.positionMs, 90000);
  });

  test('local videos cannot acquire account identity from progress', () async {
    final store = await PlaybackProgressStore.create();
    final item = localItem('camera-clip');

    await store.write(item, positionMs: 30000, durationMs: 90000);

    expect((await store.read(item))?.positionMs, 30000);
    expect(item.isAccountMedia, isFalse);
    expect(item.contentId, isNull);
  });
}
