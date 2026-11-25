import 'dart:io';

import 'package:flutter/services.dart';

import '../models/media_item.dart';

class AndroidMediaLibrary {
  static const MethodChannel _channel =
      MethodChannel('com.m5ham3ds.raven23.player/media_library');

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
