import 'dart:async';
import 'dart:io';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/android_media_library.dart';
import '../services/playback_progress_store.dart';

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
  BetterPlayerController? _controller;
  Timer? _saveTimer;
  bool _loading = true;
  String? _error;
  bool _restoredPosition = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialisePlayer());
  }

  Future<void> _initialisePlayer() async {
    BetterPlayerController? controller;
    try {
      final subtitles = <BetterPlayerSubtitlesSource>[];
      final library = AndroidMediaLibrary();
      for (final subtitle in widget.item.subtitles) {
        String? path = subtitle.path;
        if ((path == null || path.isEmpty) &&
            subtitle.contentUri.startsWith('content://')) {
          try {
            path = await library.cacheSubtitle(
              subtitle.contentUri,
              displayName: subtitle.displayName,
            );
          } catch (_) {
            // Subtitle failure must not block video playback.
          }
        }
        if (path == null || path.isEmpty || !await File(path).exists()) {
          continue;
        }
        subtitles.add(
          BetterPlayerSubtitlesSource(
            type: BetterPlayerSubtitlesSourceType.file,
            urls: [path],
            name: subtitle.language.toUpperCase(),
            selectedByDefault: subtitles.isEmpty,
          ),
        );
      }

      controller = BetterPlayerController(
        const BetterPlayerConfiguration(
          autoPlay: true,
          aspectRatio: 16 / 9,
          fit: BoxFit.contain,
          handleLifecycle: true,
          allowedScreenSleep: true,
        ),
      );
      _controller = controller;

      final path = widget.item.path;
      late final BetterPlayerDataSource source;
      if (path != null && await File(path).exists()) {
        source = BetterPlayerDataSource.file(
          path,
          subtitles: subtitles,
          useAsmsSubtitles: false,
          useAsmsTracks: false,
        );
      } else if (widget.item.contentUri.startsWith('content://')) {
        // Open the shared MediaStore item directly; do not copy video bytes.
        source = BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          widget.item.contentUri,
          subtitles: subtitles,
          useAsmsSubtitles: false,
          useAsmsTracks: false,
        );
      } else {
        throw StateError('This video no longer has a readable media source.');
      }

      await controller.setupDataSource(source);
      if (!mounted) return;
      final duration =
          controller.videoPlayerController?.value.duration?.inMilliseconds ?? 0;
      final resumeAt = widget.initialPositionMs;
      if (resumeAt > 15000 &&
          (duration <= 0 || resumeAt < duration - 5000)) {
        await controller.seekTo(Duration(milliseconds: resumeAt));
        _restoredPosition = true;
      }
      _saveTimer = Timer.periodic(
        const Duration(seconds: 8),
        (_) => unawaited(_saveProgress()),
      );
      setState(() => _loading = false);
    } catch (error) {
      controller?.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _saveProgress() async {
    final value = _controller?.videoPlayerController?.value;
    if (value == null) return;
    final duration = value.duration;
    if (duration == null) return;
    await widget.progressStore.write(
      widget.item,
      positionMs: value.position.inMilliseconds,
      durationMs: duration.inMilliseconds,
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(_saveProgress());
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final subtitleLabel =
        '${widget.item.subtitles.length} subtitle track(s)${_restoredPosition ? ' - Resumed' : ''}';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null || controller == null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error ?? 'Player could not be initialized.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : AspectRatio(
                    aspectRatio: 16 / 9,
                    child: BetterPlayer(controller: controller),
                  ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.subtitles_outlined, color: Colors.white54),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitleLabel,
                  style: const TextStyle(color: Colors.white60),
                ),
              ),
              if (widget.item.origin == MediaOrigin.raven23Library)
                const Chip(
                  avatar: Icon(Icons.download_done_outlined, size: 16),
                  label: Text('RAVEN23'),
                )
              else
                const Chip(
                  avatar: Icon(Icons.phone_android, size: 16),
                  label: Text('Device only'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
