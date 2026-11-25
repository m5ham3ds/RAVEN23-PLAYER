import 'dart:io';

import 'package:flutter/services.dart';

import '../models/media_item.dart';

class AndroidMediaLibrary {
  static const MethodChannel _channel =
      MethodChannel('com.m5ham3ds.raven23.player/media_library');

  final Map<String, Uint8List> _thumbnailCache = <String, Uint8List>{};

  Future<List<MediaItem>> scanVideos() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('The shared RAVEN23 library is Android-only.');
    }
    final raw = await _channel.invokeMapMethod<Object?, Object?>('listVideos');
    if (raw == null) return const [];
    final videos = (raw['videos'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => row.cast<Object?, Object?>())
        .toList(growable: false);
    final subtitles = (raw['subtitles'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => row.cast<Object?, Object?>())
        .toList(growable: false);
    return videos
        .map((row) => MediaItem.fromMaps(row, subtitles))
        .toList(growable: false);
  }

  Future<List<MediaItem>> scanPrimaryDownloads() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw =
          await _channel.invokeListMethod<Object?>('listRaven23Downloads');
      return (raw ?? const <Object?>[])
          .whereType<Map>()
          .map((row) =>
              MediaItem.fromPrimaryDownload(row.cast<Object?, Object?>()))
          .where((item) => item.isPlayable)
          .toList(growable: false);
    } on PlatformException {
      // The main RAVEN23 app is optional; standalone local playback remains.
      return const [];
    }
  }

  Future<Uint8List?> videoThumbnail(String uri) async {
    if (!uri.startsWith('content://')) return null;
    final cached = _thumbnailCache[uri];
    if (cached != null) return cached;
    try {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'getVideoThumbnail',
        {'uri': uri},
      );
      if (bytes != null && bytes.isNotEmpty) {
        _thumbnailCache[uri] = bytes;
        return bytes;
      }
    } on PlatformException {
      // Thumbnail extraction is optional and must not block the library.
    }
    return null;
  }

  Future<String> cacheSubtitle(
    String uri, {
    String displayName = 'subtitle.vtt',
  }) =>
      _cacheUri('cacheSubtitle', uri, 'displayName', displayName);

  Future<String> cacheContentUri(
    String uri, {
    String preferredName = 'video.mp4',
  }) =>
      _cacheUri('cacheContentUri', uri, 'preferredName', preferredName);

  Future<String> cachePlaybackUri(
    String uri, {
    String preferredName = 'video.mp4',
  }) =>
      _cacheUri('cachePlaybackUri', uri, 'preferredName', preferredName);

  Future<void> deletePlaybackCache(String path) async {
    if (!Platform.isAndroid || path.trim().isEmpty) return;
    await _channel.invokeMethod<bool>('deletePlaybackCache', {'path': path});
  }

  Future<String> _cacheUri(
    String method,
    String uri,
    String nameKey,
    String name,
  ) async {
    if (!Platform.isAndroid || !uri.startsWith('content://')) {
      throw UnsupportedError('Media content URI is unavailable.');
    }
    final path = await _channel.invokeMethod<String>(method, {
      'uri': uri,
      nameKey: name,
    });
    if (path == null || path.isEmpty) {
      throw StateError('Could not read the selected media file.');
    }
    return path;
  }
}
