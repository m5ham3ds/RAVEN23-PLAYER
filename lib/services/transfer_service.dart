import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/media_item.dart';
import 'android_media_library.dart';

class TransferService {
  TransferService(this._library);

  final AndroidMediaLibrary _library;

  Future<void> share(MediaItem item) async {
    final videoPath = await _localPath(
      item.path,
      item.contentUri,
      item.title + '.mp4',
    );
    final videoFile = File(videoPath);
    if (!await videoFile.exists()) {
      throw StateError('The selected video could not be opened for transfer.');
    }

    final files = <XFile>[XFile(videoPath)];
    final subtitleManifest = <Map<String, Object?>>[];
    for (final subtitle in item.subtitles) {
      final path = await _localPath(
        subtitle.path,
        subtitle.contentUri,
        subtitle.displayName,
      );
      final file = File(path);
      if (!await file.exists()) continue;
      final digest = await sha256.bind(file.openRead()).first;
      files.add(XFile(path));
      subtitleManifest.add({
        'fileName': file.uri.pathSegments.last,
        'language': subtitle.language,
        'format': subtitle.format,
        'sha256': digest.toString(),
        'bytes': await file.length(),
      });
    }

    final videoDigest = await sha256.bind(videoFile.openRead()).first;
    final manifest = <String, Object?>{
      'schema': 'raven23.player.transfer',
      'version': 1,
      'title': item.title,
      'origin': item.origin.name,
      'mediaType': item.mediaType,
      'contentId': item.contentId,
      'episodeId': item.episodeId,
      'seasonNumber': item.seasonNumber,
      'episodeNumber': item.episodeNumber,
      'posterPath': item.posterPath,
      'backdropPath': item.backdropPath,
      'durationMs': item.durationMs,
      'relativePath': item.relativePath,
      'video': {
        'fileName': videoFile.uri.pathSegments.last,
        'sha256': videoDigest.toString(),
        'bytes': await videoFile.length(),
      },
      'subtitles': subtitleManifest,
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    };

    final temporaryDirectory = await getTemporaryDirectory();
    final manifestFile = File(
      temporaryDirectory.path +
          '/raven23-transfer-' +
          DateTime.now().microsecondsSinceEpoch.toString() +
          '.json',
    );
    await manifestFile.writeAsString(jsonEncode(manifest), flush: true);
    files.add(XFile(manifestFile.path));

    await Share.shareXFiles(
      files,
      subject: 'RAVEN23 Transfer - ' + item.title,
      text: 'RAVEN23 Player media package. Include the video, subtitle files and JSON manifest.',
    );
  }

  Future<String> _localPath(
    String? path,
    String contentUri,
    String preferredName,
  ) async {
    if (path != null && path.isNotEmpty && await File(path).exists()) {
      return path;
    }
    if (!contentUri.startsWith('content://')) {
      throw StateError('This media item has no readable local URI.');
    }
    return _library.cacheContentUri(
      contentUri,
      preferredName: preferredName,
    );
  }
}
