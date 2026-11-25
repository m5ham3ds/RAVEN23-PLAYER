import 'package:path/path.dart' as p;

enum MediaOrigin { raven23Library, deviceLocal }

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
    this.contentId,
    this.episodeId,
    this.seasonNumber,
    this.episodeNumber,
    this.posterPath,
    this.backdropPath,
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

  // These fields are populated only after Phase 01 validates the RAVEN manifest.
  final String? mediaType;
  final int? contentId;
  final int? episodeId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? posterPath;
  final String? backdropPath;

  bool get isAccountMedia =>
      origin == MediaOrigin.raven23Library &&
      contentId != null &&
      (mediaType == 'movie' || (mediaType == 'tv' && episodeId != null));

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
