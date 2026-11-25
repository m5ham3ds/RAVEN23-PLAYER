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
  bool _preparing = true;
  String? _error;
  String? _offlineFilePath;
  OfflineDownload? _offlineDownload;
  List<BetterPlayerSubtitlesSource> _subtitles =
      const <BetterPlayerSubtitlesSource>[];

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

  TVStreamMetadata _tvMetadata() {
    final episodeNumber = widget.item.episodeNumber ?? 1;
    final seasonNumber = widget.item.seasonNumber ?? 1;
    final episodeName = widget.item.title;
    final runtime = widget.item.durationMs > 0
        ? (widget.item.durationMs / Duration.millisecondsPerMinute).round()
        : null;
    final episode = EpisodeMetadata(
      episodeId: widget.item.episodeId ?? episodeNumber,
      episodeName: episodeName,
      episodeNumber: episodeNumber,
      seasonNumber: seasonNumber,
      stillPath: widget.item.backdropPath ?? widget.item.posterPath,
      runtime: runtime,
    );
    final season = SeasonMetadata(
      seasonNumber: seasonNumber,
      seasonName: 'Season $seasonNumber',
      episodeCount: 1,
      posterPath: widget.item.posterPath,
      overview: null,
    );
    return TVStreamMetadata(
      elapsed: widget.initialPositionMs ~/ 1000,
      episodeId: episode.episodeId,
      episodeName: episodeName,
      episodeNumber: episodeNumber,
      posterPath: widget.item.posterPath,
      seasonNumber: seasonNumber,
      seriesName: widget.item.title,
      tvId: widget.item.contentId,
      airDate: null,
      episodeRuntime: runtime,
      backdropPath: widget.item.backdropPath,
      seasonEpisodes: <EpisodeMetadata>[episode],
      allSeasons: <SeasonMetadata>[season],
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
    );
  }
}
