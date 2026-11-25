import 'dart:convert';

import 'package:path/path.dart' as p;

enum MediaOrigin { raven23Library, raven23Download, deviceLocal }

class MediaSubtitle {
  const MediaSubtitle({
    required this.displayName,
    required this.contentUri,
    required this.language,
    required this.format,
    this.path,
  });

  final String displayName;
  final String contentUri;
  final String language;
  final String format;
  final String? path;

  static String? _nonEmpty(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  factory MediaSubtitle.fromMap(Map<Object?, Object?> map) {
    final name = map['displayName']?.toString() ?? 'Subtitle';
    final extension = p.extension(name).replaceFirst('.', '').toLowerCase();
    return MediaSubtitle(
      displayName: name,
      path: _nonEmpty(map['path']?.toString()),
      contentUri: map['uri']?.toString() ?? '',
      language: _languageFromName(name),
      format: extension,
    );
  }

  factory MediaSubtitle.fromPrimaryDownload({
    required String displayName,
    required String contentUri,
  }) {
    final extension = p.extension(displayName).replaceFirst('.', '').toLowerCase();
    return MediaSubtitle(
      displayName: displayName,
      contentUri: contentUri,
      language: _languageFromName(displayName),
      format: extension.isEmpty ? 'vtt' : extension,
    );
  }

  static String _languageFromName(String name) {
    final tokens = p.basenameWithoutExtension(name).split(RegExp(r'[._ -]+'));
    return tokens.length > 1 ? tokens.last.toLowerCase() : 'und';
  }
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.origin,
    required this.contentUri,
    required this.relativePath,
    required this.durationMs,
    required this.sizeBytes,
    required this.dateAddedSeconds,
    required this.subtitles,
    this.path,
    this.mediaType,
    this.subtitle,
    this.contentId,
    this.episodeId,
    this.seasonNumber,
    this.episodeNumber,
    this.posterPath,
    this.backdropPath,
    this.posterUrl,
    this.downloadState,
    this.downloadProgress,
    this.sourceData = const <String, Object?>{},
    this.isPlayable = true,
  });

  final String id;
  final String title;
  final MediaOrigin origin;
  final String contentUri;
  final String relativePath;
  final int durationMs;
  final int sizeBytes;
  final int dateAddedSeconds;
  final List<MediaSubtitle> subtitles;
  final String? path;
  final String? mediaType;
  final String? subtitle;
  final int? contentId;
  final int? episodeId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? posterPath;
  final String? backdropPath;
  final String? posterUrl;
  final String? downloadState;
  final double? downloadProgress;
  final Map<String, Object?> sourceData;
  final bool isPlayable;

  bool get isAccountMedia =>
      origin == MediaOrigin.raven23Library &&
      contentId != null &&
      (mediaType == 'movie' || (mediaType == 'tv' && episodeId != null));

  bool get isPrimaryDownload => origin == MediaOrigin.raven23Download;

  String get formattedDuration {
    final totalMinutes = durationMs ~/ Duration.millisecondsPerMinute;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return hours > 0 ? '$hours h $minutes m' : '$minutes m';
  }

  factory MediaItem.fromMaps(
    Map<Object?, Object?> video,
    List<Map<Object?, Object?>> subtitleRows,
  ) {
    final relativePath =
        _normaliseFolder(video['relativePath']?.toString() ?? '');
    final displayName = video['displayName']?.toString() ?? 'Video';
    final stem = p.basenameWithoutExtension(displayName).toLowerCase();
    final matchingSubtitles = subtitleRows.where((row) {
      final subtitleName = row['displayName']?.toString() ?? '';
      final subtitleStem =
          p.basenameWithoutExtension(subtitleName).toLowerCase();
      final subtitleFolder =
          _normaliseFolder(row['relativePath']?.toString() ?? '');
      final sameFolder = subtitleFolder == relativePath ||
          subtitleFolder == '$relativePath/subtitle' ||
          subtitleFolder == '$relativePath/subtitles';
      return sameFolder &&
          (subtitleStem == stem ||
              subtitleStem.startsWith('$stem.') ||
              subtitleStem.startsWith('${stem}_') ||
              subtitleStem.startsWith('$stem-'));
    }).map(MediaSubtitle.fromMap).toList(growable: false)
      ..sort((a, b) => a.language.compareTo(b.language));

    return MediaItem(
      id: video['id']?.toString() ?? video['uri']?.toString() ?? displayName,
      title: _titleFromName(displayName),
      origin: _isRavenRelativePath(relativePath)
          ? MediaOrigin.raven23Library
          : MediaOrigin.deviceLocal,
      path: _nonEmpty(video['path']?.toString()),
      contentUri: video['uri']?.toString() ?? '',
      relativePath: relativePath,
      durationMs: (video['durationMs'] as num?)?.toInt() ?? 0,
      sizeBytes: (video['sizeBytes'] as num?)?.toInt() ?? 0,
      dateAddedSeconds: (video['dateAddedSeconds'] as num?)?.toInt() ?? 0,
      subtitles: matchingSubtitles,
    );
  }

  factory MediaItem.fromPrimaryDownload(Map<Object?, Object?> row) {
    Map<String, Object?> payload = <String, Object?>{};
    final raw = row['downloadDataJson'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          payload = <String, Object?>{
            for (final entry in decoded.entries)
              entry.key.toString(): entry.value,
          };
        }
      } catch (_) {
        payload = <String, Object?>{};
      }
    }

    final title = row['title']?.toString().trim();
    final subtitleUri = row['subtitleUri']?.toString() ?? '';
    final subtitleName = row['subtitleName']?.toString() ?? '';
    final subtitles = subtitleUri.isEmpty
        ? const <MediaSubtitle>[]
        : <MediaSubtitle>[
            MediaSubtitle.fromPrimaryDownload(
              displayName: subtitleName.isEmpty ? 'subtitle.vtt' : subtitleName,
              contentUri: subtitleUri,
            ),
          ];
    final createdAt = (row['createdAt'] as num?)?.toInt() ?? 0;
    final createdAtSeconds = createdAt > 1000000000000
        ? createdAt ~/ 1000
        : createdAt;
    final posterUrl = _nonEmpty(row['posterUrl']?.toString());
    final posterPath = _nonEmpty(row['seriesPosterPath']?.toString());
    final backdropPath = _nonEmpty(row['seriesBackdropPath']?.toString());

    return MediaItem(
      id: 'raven23-offline:${row['id']?.toString() ?? ''}',
      title: title?.isNotEmpty == true
          ? title!
          : (payload['title']?.toString() ?? 'RAVEN23 video'),
      origin: MediaOrigin.raven23Download,
      contentUri: row['videoUri']?.toString() ?? '',
      relativePath: 'RAVEN23 Downloads',
      durationMs: (row['durationMs'] as num?)?.toInt() ??
          (row['expectedDurationMs'] as num?)?.toInt() ?? 0,
      sizeBytes: (row['sizeBytes'] as num?)?.toInt() ??
          (row['bytesDownloaded'] as num?)?.toInt() ?? 0,
      dateAddedSeconds: createdAtSeconds,
      subtitles: subtitles,
      mediaType: row['mediaType']?.toString(),
      subtitle: _nonEmpty(payload['subtitle']?.toString()),
      contentId: (row['contentId'] as num?)?.toInt(),
      seasonNumber: (row['seasonNumber'] as num?)?.toInt(),
      episodeNumber: (row['episodeNumber'] as num?)?.toInt(),
      posterUrl: posterUrl,
      posterPath: posterPath,
      backdropPath: backdropPath,
      downloadState: row['state']?.toString(),
      downloadProgress: (row['progress'] as num?)?.toDouble(),
      sourceData: payload,
      isPlayable: row['isPlayable'] == true &&
          row['videoUri']?.toString().startsWith('content://') == true,
    );
  }

  static String _normaliseFolder(String value) => value
      .replaceAll(String.fromCharCode(92), '/')
      .replaceAll(RegExp(r'/+$'), '')
      .toLowerCase();

  static bool _isRavenRelativePath(String value) =>
      value.startsWith('movies/raven23/library') ||
      value.startsWith('dcim/raven23');

  static String _titleFromName(String name) =>
      p.basenameWithoutExtension(name).replaceAll(RegExp(r'[._]+'), ' ');

  static String? _nonEmpty(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
}
