import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:better_player_plus/better_player_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/media_item.dart';
import '../services/android_media_library.dart';
import '../services/playback_progress_store.dart';
import '../services/transfer_service.dart';

/// A separate player surface for videos indexed directly from phone storage.
/// It does not use the companion RAVEN23 PlayerOne watch page.
class LocalDevicePlayerScreen extends StatefulWidget {
  const LocalDevicePlayerScreen({
    required this.item,
    required this.deviceVideos,
    required this.progressStore,
    this.initialPositionMs = 0,
    super.key,
  });

  final MediaItem item;
  final List<MediaItem> deviceVideos;
  final PlaybackProgressStore progressStore;
  final int initialPositionMs;

  @override
  State<LocalDevicePlayerScreen> createState() =>
      _LocalDevicePlayerScreenState();
}

class _LocalDevicePlayerScreenState extends State<LocalDevicePlayerScreen> {
  final AndroidMediaLibrary _mediaLibrary = AndroidMediaLibrary();
  late final TransferService _transfer = TransferService(_mediaLibrary);
  late final BetterPlayerController _controller;

  late MediaItem _currentItem;
  Timer? _progressTimer;
  int _lastPositionMs = 0;
  int _lastDurationMs = 0;
  DateTime _lastSaveAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _savingProgress = false;
  bool _preparing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    _controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        autoDispose: false,
        autoDetectFullscreenDeviceOrientation: true,
        fit: BoxFit.contain,
        allowedScreenSleep: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          playerTheme: BetterPlayerTheme.custom,
          showControls: true,
          showControlsOnInitialize: true,
          enableOverflowMenu: false,
          enableQualities: false,
          enableDownloadButton: false,
          customControlsBuilder: (controller, onVisibilityChanged) =>
              _LocalDeviceControls(
            controller: controller,
            item: _currentItem,
            deviceVideos: widget.deviceVideos,
            onVisibilityChanged: onVisibilityChanged,
            onBack: _back,
            onShare: _share,
            onSwitchVideo: _switchVideo,
          ),
        ),
      ),
    );
    unawaited(_prepareItem(_currentItem, widget.initialPositionMs));
    _progressTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollPlaybackProgress(),
    );
  }

  Future<BetterPlayerDataSource> _dataSourceFor(MediaItem item) async {
    final subtitleSources = <BetterPlayerSubtitlesSource>[];
    for (var index = 0; index < item.subtitles.length; index++) {
      final subtitle = item.subtitles[index];
      String? subtitlePath;
      final directPath = subtitle.path?.trim();
      if (directPath != null &&
          directPath.isNotEmpty &&
          await File(directPath).exists()) {
        subtitlePath = directPath;
      } else if (subtitle.contentUri.startsWith('content://')) {
        try {
          subtitlePath = await _mediaLibrary.cacheSubtitle(
            subtitle.contentUri,
            displayName: subtitle.displayName,
          );
        } catch (_) {
          subtitlePath = null;
        }
      }
      if (subtitlePath == null || subtitlePath.isEmpty) continue;
      subtitleSources.add(
        BetterPlayerSubtitlesSource(
          type: BetterPlayerSubtitlesSourceType.file,
          name: subtitle.language.toUpperCase(),
          urls: [subtitlePath],
          selectedByDefault: index == 0,
        ),
      );
    }

    final uri = item.contentUri.trim();
    final filePath = item.path?.trim();
    if (uri.startsWith('content://')) {
      // Media3 can read Android content:// URIs directly. Keep the phone file
      // on its original storage rather than copying large videos to app cache.
      return BetterPlayerDataSource.network(
        uri,
        subtitles: subtitleSources,
        useAsmsSubtitles: false,
        useAsmsTracks: false,
        useAsmsAudioTracks: false,
      );
    }
    if (uri.startsWith('file://')) {
      return BetterPlayerDataSource.file(
        Uri.parse(uri).toFilePath(),
        subtitles: subtitleSources,
        useAsmsSubtitles: false,
        useAsmsTracks: false,
      );
    }
    if (filePath != null && filePath.isNotEmpty) {
      return BetterPlayerDataSource.file(
        filePath,
        subtitles: subtitleSources,
        useAsmsSubtitles: false,
        useAsmsTracks: false,
      );
    }
    throw StateError('The selected phone video has no readable local URI.');
  }

  Future<void> _prepareItem(MediaItem item, int positionMs) async {
    if (!mounted) return;
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final source = await _dataSourceFor(item);
      await _controller.setupDataSource(
        source,
        initialPosition: positionMs > 0
            ? Duration(milliseconds: positionMs)
            : Duration.zero,
      );
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _error = null;
        _lastPositionMs = positionMs;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _error = error.toString();
      });
    }
  }

  void _pollPlaybackProgress() {
    final value = _controller.videoPlayerController?.value;
    if (value == null) return;
    _lastPositionMs = value.position.inMilliseconds;
    _lastDurationMs = value.duration?.inMilliseconds ?? 0;
    if (value.hasError && _error == null && mounted) {
      setState(() {
        _error = value.errorDescription ?? tr('player_unreadable_media_source');
        _preparing = false;
      });
    }
    if (DateTime.now().difference(_lastSaveAt) >=
        const Duration(seconds: 6)) {
      unawaited(_saveProgress());
    }
  }

  Future<void> _saveProgress() async {
    if (_savingProgress || _lastDurationMs <= 0) return;
    final value = _controller.videoPlayerController?.value;
    final durationMs = value?.duration?.inMilliseconds ?? _lastDurationMs;
    final positionMs = value?.position.inMilliseconds ?? _lastPositionMs;
    if (durationMs <= 0) return;
    _savingProgress = true;
    try {
      await widget.progressStore.write(
        _currentItem,
        positionMs: positionMs,
        durationMs: durationMs,
      );
      _lastPositionMs = positionMs;
      _lastDurationMs = durationMs;
      _lastSaveAt = DateTime.now();
    } finally {
      _savingProgress = false;
    }
  }

  Future<void> _switchVideo(MediaItem target) async {
    if (target.origin != MediaOrigin.deviceLocal ||
        !target.isPlayable ||
        target.id == _currentItem.id) {
      return;
    }
    await _saveProgress();
    final saved = await widget.progressStore.read(target);
    if (!mounted) return;
    setState(() {
      _currentItem = target;
      _lastPositionMs = saved?.positionMs ?? 0;
      _lastDurationMs = 0;
    });
    await _prepareItem(target, saved?.positionMs ?? 0);
  }

  Future<void> _share() async {
    try {
      await _transfer.share(_currentItem);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr('local_player_share_failed',
                namedArgs: {'error': error.toString()}),
          ),
        ),
      );
    }
  }

  Future<void> _back() async {
    if (_controller.isFullScreen) {
      _controller.exitFullScreen();
      return;
    }
    await _saveProgress();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    unawaited(_saveProgress());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: BetterPlayer(controller: _controller),
              ),
              if (_preparing)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x77000000),
                    child: Center(
                      child: SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_error != null && !_preparing)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black87,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.white70, size: 42),
                          const SizedBox(height: 14),
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white)),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: () => _prepareItem(
                              _currentItem,
                              _lastPositionMs,
                            ),
                            icon: const Icon(Icons.refresh),
                            label: Text(tr('retry')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalDeviceControls extends StatefulWidget {
  const _LocalDeviceControls({
    required this.controller,
    required this.item,
    required this.deviceVideos,
    required this.onVisibilityChanged,
    required this.onBack,
    required this.onShare,
    required this.onSwitchVideo,
  });

  final BetterPlayerController controller;
  final MediaItem item;
  final List<MediaItem> deviceVideos;
  final Function(bool) onVisibilityChanged;
  final Future<void> Function() onBack;
  final Future<void> Function() onShare;
  final Future<void> Function(MediaItem item) onSwitchVideo;

  @override
  State<_LocalDeviceControls> createState() => _LocalDeviceControlsState();
}

class _LocalDeviceControlsState extends State<_LocalDeviceControls> {
  Timer? _hideTimer;
  Timer? _refreshTimer;
  bool _visible = true;
  bool _locked = false;
  double _speed = 1;

  @override
  void initState() {
    super.initState();
    _speed = widget.controller.videoPlayerController?.value.speed ?? 1;
    _refreshTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) {
        if (!mounted) return;
        final next = widget.controller.videoPlayerController?.value.speed ?? 1;
        if ((next - _speed).abs() > .001) setState(() => _speed = next);
      },
    );
    _restartHideTimer();
    widget.onVisibilityChanged(true);
  }

  @override
  void didUpdateWidget(covariant _LocalDeviceControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _speed = widget.controller.videoPlayerController?.value.speed ?? 1;
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _refreshTimer?.cancel();
    widget.onVisibilityChanged(false);
    super.dispose();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    final value = widget.controller.videoPlayerController?.value;
    if (_locked || value?.isPlaying != true) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _locked) return;
      setState(() => _visible = false);
      widget.onVisibilityChanged(false);
    });
  }

  void _reveal() {
    if (_locked) return;
    setState(() => _visible = true);
    widget.onVisibilityChanged(true);
    _restartHideTimer();
  }

  void _toggleVisibility() {
    if (_locked) return;
    if (_visible) {
      _hideTimer?.cancel();
      setState(() => _visible = false);
      widget.onVisibilityChanged(false);
    } else {
      _reveal();
    }
  }

  Future<void> _seekBy(int seconds) async {
    final value = widget.controller.videoPlayerController?.value;
    if (value?.duration == null) return;
    final target = value!.position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : target > value.duration!
            ? value.duration!
            : target;
    await widget.controller.seekTo(clamped);
    _restartHideTimer();
  }

  Future<void> _togglePlayPause() async {
    final playing =
        widget.controller.videoPlayerController?.value.isPlaying ?? false;
    if (playing) {
      await widget.controller.pause();
    } else {
      await widget.controller.play();
    }
    _restartHideTimer();
    if (mounted) setState(() {});
  }

  Future<void> _showSpeedPicker() async {
    _reveal();
    const speeds = <double>[0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF191B24),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('local_player_playback_speed'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final speed in speeds)
                    ChoiceChip(
                      label: Text('${speed}x'),
                      selected: (_speed - speed).abs() < .001,
                      onSelected: (_) async {
                        await widget.controller.setSpeed(speed);
                        if (mounted) setState(() => _speed = speed);
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    _restartHideTimer();
  }

  Future<void> _showMore() async {
    _reveal();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF191B24),
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MoreHeader(title: tr('local_player_more')),
              _MoreRow(
                icon: PhosphorIcons.closedCaptioning(),
                title: tr('local_player_audio_subtitles'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_showAudioSubtitles());
                },
              ),
              _MoreRow(
                icon: PhosphorIcons.gauge(),
                title: tr('local_player_playback_speed'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_showSpeedPicker());
                },
              ),
              _MoreRow(
                icon: PhosphorIcons.crop(),
                title: tr('local_player_crop_fit'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_showCropFit());
                },
              ),
            ],
          ),
        ),
      ),
    );
    _restartHideTimer();
  }

  Future<void> _showAudioSubtitles() async {
    _reveal();
    final tracks = widget.controller.betterPlayerSubtitlesSourceList;
    final selected = widget.controller.betterPlayerSubtitlesSource;
    final audioTracks =
        widget.controller.betterPlayerAsmsAudioTracks ?? const [];
    final subtitleTracks = tracks
        .where((source) => source.type != BetterPlayerSubtitlesSourceType.none)
        .toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF191B24),
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MoreHeader(title: tr('local_player_audio_subtitles')),
              if (audioTracks.isNotEmpty) ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    tr('local_player_audio_subtitles'),
                    style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                for (final track in audioTracks)
                  _MoreRow(
                    icon: PhosphorIcons.waveform(),
                    title: track.label?.trim().isNotEmpty == true
                        ? track.label!.trim()
                        : (track.language?.trim().isNotEmpty == true
                            ? track.language!.toUpperCase()
                            : tr('local_player_audio_subtitles')),
                    selected:
                        widget.controller.betterPlayerAsmsAudioTrack?.id ==
                            track.id,
                    onTap: () {
                      widget.controller.setAudioTrack(track);
                      Navigator.pop(sheetContext);
                    },
                  ),
              ],
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  tr('player_subtitles'),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700),
                ),
              ),
              _MoreRow(
                icon: PhosphorIcons.subtitlesSlash(),
                title: tr('local_player_subtitles_off'),
                selected: selected == null ||
                    selected.type == BetterPlayerSubtitlesSourceType.none,
                onTap: () async {
                  final off = tracks.firstWhere(
                    (source) =>
                        source.type == BetterPlayerSubtitlesSourceType.none,
                    orElse: () => BetterPlayerSubtitlesSource(
                      type: BetterPlayerSubtitlesSourceType.none,
                    ),
                  );
                  await widget.controller.selectSubtitlesSource(off);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
              for (final source in subtitleTracks)
                _MoreRow(
                  icon: PhosphorIcons.closedCaptioning(),
                  title: source.name ?? tr('player_subtitles'),
                  selected: identical(selected, source),
                  onTap: () async {
                    await widget.controller.selectSubtitlesSource(source);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
              if (subtitleTracks.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr('local_player_no_subtitles'),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              if (audioTracks.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    tr('local_player_no_audio_tracks'),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    _restartHideTimer();
  }

  Future<void> _showCropFit() async {
    _reveal();
    final modes = <({BoxFit fit, String title})>[
      (fit: BoxFit.contain, title: tr('local_player_fit')),
      (fit: BoxFit.cover, title: tr('local_player_crop_fill')),
      (fit: BoxFit.fill, title: tr('local_player_stretch')),
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF191B24),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MoreHeader(title: tr('local_player_crop_fit')),
              for (final mode in modes)
                _MoreRow(
                  icon: PhosphorIcons.crop(),
                  title: mode.title,
                  selected: widget.controller.getFit() == mode.fit,
                  onTap: () {
                    widget.controller.setOverriddenFit(mode.fit);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
    _restartHideTimer();
  }

  Future<void> _showDeviceVideos() async {
    _reveal();
    final videos = widget.deviceVideos
        .where((item) =>
            item.origin == MediaOrigin.deviceLocal && item.isPlayable)
        .toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF191B24),
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: .72,
        minChildSize: .4,
        maxChildSize: .92,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: _MoreHeader(
                title: tr('local_player_device_videos'),
                subtitle: '${videos.length}',
              ),
            ),
            Expanded(
              child: videos.isEmpty
                  ? Center(
                      child: Text(
                        tr('local_player_no_videos'),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: videos.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Colors.white12, height: 1),
                      itemBuilder: (context, index) {
                        final video = videos[index];
                        final selected = video.id == widget.item.id;
                        return ListTile(
                          leading: Icon(
                            Icons.video_file_outlined,
                            color:
                                selected ? Colors.redAccent : Colors.white70,
                          ),
                          title: Text(
                            video.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                          subtitle: Text(
                            video.relativePath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54),
                          ),
                          trailing: selected
                              ? const Icon(Icons.check_circle,
                                  color: Colors.redAccent)
                              : null,
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            await widget.onSwitchVideo(video);
                            _restartHideTimer();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    _restartHideTimer();
  }

  Future<void> _lockControls() async {
    _hideTimer?.cancel();
    setState(() => _locked = true);
    widget.onVisibilityChanged(false);
  }

  void _unlockControls() {
    setState(() {
      _locked = false;
      _visible = true;
    });
    widget.onVisibilityChanged(true);
    _restartHideTimer();
  }

  String _time(Duration? duration) {
    final seconds = duration?.inSeconds ?? 0;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remaining = seconds % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    return hours > 0
        ? '${two(hours)}:${two(minutes)}:${two(remaining)}'
        : '${two(minutes)}:${two(remaining)}';
  }

  Widget _roundButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    double size = 48,
    double iconSize = 25,
  }) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          fixedSize: Size(size, size),
          backgroundColor: Colors.black54,
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
        ),
        icon: Icon(icon, size: iconSize),
      );

  Widget _topBar(BuildContext context) => Row(
        children: [
          _roundButton(
            icon: PhosphorIcons.arrowLeft(),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => unawaited(widget.onBack()),
            size: 42,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          _roundButton(
            icon: PhosphorIcons.dotsThreeVertical(),
            tooltip: tr('local_player_more'),
            onPressed: () => unawaited(_showMore()),
            size: 40,
          ),
        ],
      );

  Widget _seekBar() {
    final value = widget.controller.videoPlayerController?.value;
    final duration = value?.duration ?? Duration.zero;
    final position = value?.position ?? Duration.zero;
    final total = duration.inMilliseconds;
    final elapsed = position.inMilliseconds.clamp(0, total > 0 ? total : 0);
    final remaining = duration - position;
    return Row(
      children: [
        Text(_time(position),
            style: const TextStyle(color: Colors.white, fontSize: 12)),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF5A7FA7),
              inactiveTrackColor: Colors.white38,
              thumbColor: const Color(0xFF5A7FA7),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
            ),
            child: Slider(
              value: total <= 0 ? 0 : elapsed.toDouble(),
              min: 0,
              max: total <= 0 ? 1 : total.toDouble(),
              onChanged: total <= 0
                  ? null
                  : (v) {
                      widget.controller.seekTo(
                        Duration(milliseconds: v.round()),
                      );
                    },
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '-${_time(remaining.isNegative ? Duration.zero : remaining)}',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        const SizedBox(width: 4),
        _roundButton(
          icon: widget.controller.isFullScreen
              ? PhosphorIcons.cornersIn()
              : PhosphorIcons.cornersOut(),
          tooltip: widget.controller.isFullScreen
              ? tr('local_player_exit_fullscreen')
              : tr('local_player_fullscreen'),
          onPressed: () {
            if (widget.controller.isFullScreen) {
              widget.controller.exitFullScreen();
            } else {
              widget.controller.enterFullScreen();
            }
          },
          size: 38,
          iconSize: 20,
        ),
      ],
    );
  }

  Widget _centerControls() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _roundButton(
            icon: PhosphorIcons.arrowCounterClockwise(),
            tooltip: tr('local_player_rewind'),
            onPressed: () => unawaited(_seekBy(-10)),
            size: 54,
            iconSize: 27,
          ),
          const SizedBox(width: 24),
          _roundButton(
            icon: (widget.controller.videoPlayerController?.value.isPlaying ??
                    false)
                ? PhosphorIcons.pause(PhosphorIconsStyle.fill)
                : PhosphorIcons.play(PhosphorIconsStyle.fill),
            tooltip: (widget.controller.videoPlayerController?.value.isPlaying ??
                    false)
                ? tr('player_pause')
                : tr('player_play'),
            onPressed: () => unawaited(_togglePlayPause()),
            size: 62,
            iconSize: 31,
          ),
          const SizedBox(width: 24),
          _roundButton(
            icon: PhosphorIcons.arrowClockwise(),
            tooltip: tr('local_player_forward'),
            onPressed: () => unawaited(_seekBy(10)),
            size: 54,
            iconSize: 27,
          ),
        ],
      );

  Widget _landscapeActions() => Directionality(
        textDirection: ui.TextDirection.ltr,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _roundButton(
              icon: PhosphorIcons.gauge(),
              tooltip: tr('local_player_playback_speed'),
              onPressed: () => unawaited(_showSpeedPicker()),
              size: 46,
              iconSize: 23,
            ),
            _roundButton(
              icon: PhosphorIcons.lockSimple(),
              tooltip: tr('local_player_lock'),
              onPressed: () => unawaited(_lockControls()),
              size: 46,
              iconSize: 23,
            ),
            _roundButton(
              icon: PhosphorIcons.listBullets(),
              tooltip: tr('local_player_open_list'),
              onPressed: () => unawaited(_showDeviceVideos()),
              size: 46,
              iconSize: 23,
            ),
            _roundButton(
              icon: PhosphorIcons.closedCaptioning(),
              tooltip: tr('local_player_audio_subtitles'),
              onPressed: () => unawaited(_showAudioSubtitles()),
              size: 46,
              iconSize: 23,
            ),
            _roundButton(
              icon: PhosphorIcons.shareNetwork(),
              tooltip: tr('local_player_share'),
              onPressed: () => unawaited(widget.onShare()),
              size: 46,
              iconSize: 23,
            ),
          ],
        ),
      );

  Widget _portraitControls() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              _topBar(context),
              const Spacer(),
              _centerControls(),
              const Spacer(),
              _seekBar(),
            ],
          ),
        ),
      );

  Widget _landscapeControls() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            children: [
              _topBar(context),
              const Spacer(),
              _centerControls(),
              const Spacer(),
              _seekBar(),
              const SizedBox(height: 6),
              _landscapeActions(),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _unlockControls,
            child: const SizedBox.expand(),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _roundButton(
                icon: PhosphorIcons.lockSimpleOpen(),
                tooltip: tr('local_player_unlock'),
                onPressed: _unlockControls,
                size: 52,
                iconSize: 25,
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _toggleVisibility,
          child: const SizedBox.expand(),
        ),
        if (_visible)
          MediaQuery.orientationOf(context) == Orientation.landscape
              ? _landscapeControls()
              : _portraitControls(),
      ],
    );
  }
}

class _MoreHeader extends StatelessWidget {
  const _MoreHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: const TextStyle(color: Colors.white54)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: Colors.white70),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        trailing: selected
            ? const Icon(Icons.check, color: Colors.redAccent)
            : const Icon(Icons.chevron_right, color: Colors.white54),
        onTap: onTap,
      );
}
