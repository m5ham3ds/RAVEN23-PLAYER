import 'dart:async';
import 'dart:io';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:raven23/constants/app_constants.dart';
import 'package:raven23/models/movie_stream_metadata.dart';
import 'package:raven23/models/offline_download.dart';
import 'package:raven23/models/tv_stream_metadata.dart';
import 'package:raven23/provider/settings_provider.dart';
import 'package:raven23/screens/common/player.dart';

import '../app.dart';
import '../models/media_item.dart';
import '../services/android_media_library.dart';
import '../services/playback_progress_store.dart';
import '../widgets/app_press_feedback.dart';
import '../services/player_ambient_theme_controller.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.item,
    required this.progressStore,
    required this.initialPositionMs,
  });

  final MediaItem item;
  final PlaybackProgressStore progressStore;
  final int initialPositionMs;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final AndroidMediaLibrary _library = AndroidMediaLibrary();
  final PlayerAmbientThemeController _ambientTheme =
      PlayerAmbientThemeController();
  bool _preparing = true;
  String? _error;
  String? _offlineFilePath;
  OfflineDownload? _offlineDownload;
  List<BetterPlayerSubtitlesSource> _subtitles =
      const <BetterPlayerSubtitlesSource>[];
  List<MediaItem> _seriesDownloads = const <MediaItem>[];

  bool get _isPrimaryDownload =>
      widget.item.origin == MediaOrigin.raven23Download;

  bool get _isTelevision =>
      widget.item.mediaType == 'tv' ||
      widget.item.mediaType == 'episode';

  @override
  void initState() {
    super.initState();
    unawaited(_prepareOriginalPlayer());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ambientTheme.attach(context, widget.item);
  }

  String _safeFileStem(String title) {
    final normalized = title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    return normalized.isEmpty ? 'RAVEN23 video' : normalized;
  }

  Future<void> _prepareOriginalPlayer() async {
    try {
      if (_isPrimaryDownload) {
        final contentUri = widget.item.contentUri.trim();
        if (!contentUri.startsWith('content://')) {
          throw StateError('The RAVEN23 private download URI is unavailable.');
        }

        // Reading the provider URI triggers the original app's validated
        // Media3-cache export when the MP4 has not been materialized yet.
        // The Player copy remains temporary inside this app's cache directory.
        _offlineFilePath = await _library.cachePlaybackUri(
          contentUri,
          preferredName: '${_safeFileStem(widget.item.title)}.mp4',
        );
        _offlineDownload = OfflineDownload.fromMap(
          Map<Object?, Object?>.from(widget.item.sourceData),
        );
        final allDownloads = await _library.scanPrimaryDownloads();
        _seriesDownloads = allDownloads.where((download) {
          if (!download.isPrimaryDownload || download.mediaType == 'movie') {
            return false;
          }
          if (widget.item.contentId == null) {
            return download.id == widget.item.id;
          }
          return download.contentId == widget.item.contentId;
        }).toList()
          ..sort((a, b) {
            final season = (a.seasonNumber ?? 0)
                .compareTo(b.seasonNumber ?? 0);
            if (season != 0) return season;
            return (a.episodeNumber ?? 0)
                .compareTo(b.episodeNumber ?? 0);
          });
        if (!_seriesDownloads.any((item) => item.id == widget.item.id)) {
          _seriesDownloads = <MediaItem>[..._seriesDownloads, widget.item];
        }
        if (!await File(_offlineFilePath!).exists()) {
          throw StateError('The prepared offline video file is missing.');
        }
      }

      final subtitleSources = <BetterPlayerSubtitlesSource>[];
      for (final subtitle in widget.item.subtitles) {
        String? path = subtitle.path;
        if ((path == null || path.isEmpty) &&
            subtitle.contentUri.startsWith('content://')) {
          try {
            path = await _library.cacheSubtitle(
              subtitle.contentUri,
              displayName: subtitle.displayName,
            );
          } catch (_) {
            // A damaged or unavailable subtitle must not block the video.
          }
        }
        if (path == null || path.isEmpty || !await File(path).exists()) {
          continue;
        }
        subtitleSources.add(
          BetterPlayerSubtitlesSource(
            type: BetterPlayerSubtitlesSourceType.file,
            urls: <String>[path],
            name: subtitle.language.toUpperCase(),
            selectedByDefault: subtitleSources.isEmpty,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _subtitles = subtitleSources;
        _preparing = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _error = error.toString();
      });
    }
  }

  MovieStreamMetadata _movieMetadata() => MovieStreamMetadata(
        backdropPath: widget.item.backdropPath,
        elapsed: widget.initialPositionMs ~/ 1000,
        movieId: widget.item.contentId,
        movieName: widget.item.title,
        posterPath: widget.item.posterPath,
        releaseYear: null,
        isAdult: false,
        releaseDate: null,
        runtime: widget.item.durationMs > 0
            ? (widget.item.durationMs / Duration.millisecondsPerMinute).round()
            : null,
      );

  List<Map<String, Object?>> _metadataRows(Object? raw) {
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw.whereType<Map>().map((row) {
      return <String, Object?>{
        for (final entry in row.entries)
          entry.key.toString(): entry.value,
      };
    }).toList(growable: false);
  }

  int? _intValue(Map<String, Object?>? row, String key) {
    final value = row?[key];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  num? _numValue(Map<String, Object?>? row, String key) {
    final value = row?[key];
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }

  String? _stringValue(Map<String, Object?>? row, String key) =>
      row?[key]?.toString();

  String? _fallbackEpisodeName(MediaItem item) {
    final raw = item.sourceData['subtitle']?.toString() ?? '';
    final parts = raw.split(' • ');
    if (parts.length < 2) return null;
    final name = parts[1].replaceFirst(RegExp(r'^E\d+\s*'), '').trim();
    return name.isEmpty ? null : name;
  }

  EpisodeMetadata _episodeMetadata(MediaItem item) {
    final number = item.episodeNumber ?? 0;
    final season = item.seasonNumber ?? 0;
    final matchingRows = _metadataRows(item.sourceData['seasonEpisodes']).where(
      (row) =>
          _intValue(row, 'episodeNumber') == number &&
          _intValue(row, 'seasonNumber') == season,
    );
    final row = matchingRows.isEmpty ? null : matchingRows.first;
    final savedName = _stringValue(row, 'episodeName')?.trim();
    final runtime = _intValue(row, 'runtime') ??
        (item.durationMs > 0
            ? (item.durationMs / Duration.millisecondsPerMinute).round()
            : null);
    return EpisodeMetadata(
      episodeId: _intValue(row, 'episodeId') ?? item.episodeId ?? number,
      episodeName: savedName?.isNotEmpty == true
          ? savedName!
          : (_fallbackEpisodeName(item) ?? 'Episode $number'),
      episodeNumber: number,
      seasonNumber: season,
      stillPath: _stringValue(row, 'stillPath') ??
          item.backdropPath ??
          item.posterPath,
      airDate: _stringValue(row, 'airDate'),
      runtime: runtime,
      overview: _stringValue(row, 'overview'),
      voteAverage: _numValue(row, 'voteAverage'),
    );
  }

  List<MediaItem> _seasonDownloads(int seasonNumber) => _seriesDownloads
      .where((item) => (item.seasonNumber ?? 0) == seasonNumber)
      .toList(growable: false);

  TVStreamMetadata _tvMetadata() {
    final seasonNumber = widget.item.seasonNumber ?? 0;
    final downloadedSeries = _seriesDownloads.isEmpty
        ? <MediaItem>[widget.item]
        : _seriesDownloads;
    final seasonItems = _seasonDownloads(seasonNumber);
    final mappedEpisodes = (seasonItems.isEmpty
            ? <MediaItem>[widget.item]
            : seasonItems)
        .where((item) => item.episodeNumber != null)
        .map(_episodeMetadata)
        .toList(growable: false);

    final seasonNumbers = downloadedSeries
        .map((item) => item.seasonNumber ?? 0)
        .toSet()
        .toList()
      ..sort();
    final allSeasons = seasonNumbers.map((season) {
      final sample = downloadedSeries.firstWhere(
        (item) => (item.seasonNumber ?? 0) == season,
      );
      final matchingRows = _metadataRows(sample.sourceData['allSeasons'])
          .where((entry) => _intValue(entry, 'seasonNumber') == season);
      final row = matchingRows.isEmpty ? null : matchingRows.first;
      return SeasonMetadata(
        seasonNumber: season,
        seasonName: _stringValue(row, 'seasonName') ?? 'Season $season',
        episodeCount: _seasonDownloads(season).length,
        posterPath: _stringValue(row, 'posterPath') ?? sample.posterPath,
        overview: _stringValue(row, 'overview'),
      );
    }).toList(growable: false);

    final currentEpisode = _episodeMetadata(widget.item);
    final metadata = TVStreamMetadata(
      elapsed: widget.initialPositionMs ~/ 1000,
      episodeId: currentEpisode.episodeId,
      episodeName: currentEpisode.episodeName,
      episodeNumber: currentEpisode.episodeNumber,
      posterPath: widget.item.posterPath,
      seasonNumber: seasonNumber,
      seriesName: widget.item.title,
      tvId: widget.item.contentId,
      airDate: currentEpisode.airDate,
      episodeRuntime: currentEpisode.runtime,
      backdropPath: widget.item.backdropPath,
      seasonEpisodes: mappedEpisodes,
      allSeasons: allSeasons,
    );
    metadata.onSeasonChange = (requestedSeason) {
      metadata.seasonEpisodes = _seasonDownloads(requestedSeason)
          .where((item) => item.episodeNumber != null)
          .map(_episodeMetadata)
          .toList(growable: false);
    };
    return metadata;
  }

  Future<void> _playDownloadedEpisode(EpisodeMetadata episode) async {
    final target = _seriesDownloads.where((item) {
      return item.isPlayable &&
          item.seasonNumber == episode.seasonNumber &&
          item.episodeNumber == episode.episodeNumber;
    }).firstOrNull;
    if (target == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('This episode is no longer available offline.'),
        ),
      );
      return;
    }
    final saved = await widget.progressStore.read(target);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          item: target,
          progressStore: widget.progressStore,
          initialPositionMs: saved?.positionMs ?? 0,
        ),
      ),
    );
  }

  String? _localSourceUri() {
    final uri = widget.item.contentUri.trim();
    if (uri.startsWith('content://') || uri.startsWith('file://')) {
      return uri;
    }
    final path = widget.item.path?.trim();
    if (path != null && path.isNotEmpty) return Uri.file(path).toString();
    return null;
  }

  @override
  void dispose() {
    _ambientTheme.dispose();
    final path = _offlineFilePath;
    if (path != null && path.isNotEmpty) {
      // Let BetterPlayer close its file descriptor before deleting the
      // temporary cache copy. A later cache cleanup also handles process death.
      unawaited(
        Future<void>.delayed(
          const Duration(seconds: 2),
          () => _library.deletePlaybackCache(path),
        ),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_preparing) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Raven23PlayerApp.ravenRed,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _isPrimaryDownload
                      ? 'Preparing the private RAVEN23 download'
                      : 'Preparing video',
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(widget.item.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.white70,
                  size: 42,
                ),
                const SizedBox(height: 14),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 18),
                AppPressFeedback(
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _preparing = true;
                        _error = null;
                      });
                      unawaited(_prepareOriginalPlayer());
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final settings = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );
    final accent = Theme.of(context).colorScheme.primary;
    final sourceUri = _localSourceUri();
    final isTv = _isTelevision;
    if (!_isPrimaryDownload && (sourceUri == null || sourceUri.isEmpty)) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'This video no longer has a readable media source.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return PlayerOne(
      key: ValueKey<String>('original-player-${widget.item.id}'),
      sources: _isPrimaryDownload
          ? const <String, String>{}
          : <String, String>{'Original': sourceUri!},
      subs: _subtitles,
      colors: <Color>[accent],
      settings: settings,
      movieMetadata: isTv ? null : _movieMetadata(),
      tvMetadata: isTv ? _tvMetadata() : null,
      mediaType: isTv ? MediaType.tvShow : MediaType.movie,
      subtitleStyle: settings.subtitleTextStyle,
      initialPlaybackPosition: Duration(
        milliseconds: widget.initialPositionMs,
      ),
      initialStreamUrl: _isPrimaryDownload ? null : sourceUri,
      offlineDownload: _offlineDownload,
      offlineFilePath: _offlineFilePath,
      onOfflineEpisodeSelected:
          isTv && _isPrimaryDownload ? _playDownloadedEpisode : null,
    );
  }
}
