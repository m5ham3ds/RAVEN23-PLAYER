import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app.dart';
import '../models/media_item.dart';
import '../services/android_media_library.dart';
import '../services/playback_progress_store.dart';
import '../services/transfer_service.dart';
import 'player_screen.dart';

enum LibraryFilter { all, raven23, device }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final AndroidMediaLibrary _library = AndroidMediaLibrary();
  late final TransferService _transfer = TransferService(_library);
  LibraryFilter _filter = LibraryFilter.all;
  Future<List<MediaItem>>? _load;
  PlaybackProgressStore? _progressStore;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load = _initialise();
  }

  Future<List<MediaItem>> _initialise() async {
    _progressStore = await PlaybackProgressStore.create();
    return _scan();
  }

  Future<List<MediaItem>> _scan() async {
    if (!Platform.isAndroid) {
      _setError('RAVEN23 Player currently targets Android.');
      return const [];
    }
    final status = await _requestVideoPermission();
    if (!status) {
      _setError('Allow video access to scan this device.');
      return const [];
    }
    try {
      final items = await _library.scanVideos();
      if (mounted) setState(() => _error = null);
      return items;
    } catch (error) {
      _setError(error.toString());
      rethrow;
    }
  }

  Future<bool> _requestVideoPermission() async {
    var result = await Permission.videos.request();
    if (!result.isGranted && !result.isLimited) {
      result = await Permission.storage.request();
    }
    return result.isGranted || result.isLimited;
  }

  void _setError(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _refresh() async {
    setState(() {
      _error = null;
      _load = _scan();
    });
    await _load;
  }

  List<MediaItem> _filtered(List<MediaItem> items) {
    switch (_filter) {
      case LibraryFilter.raven23:
        return items
            .where((item) => item.origin == MediaOrigin.raven23Library)
            .toList();
      case LibraryFilter.device:
        return items
            .where((item) => item.origin == MediaOrigin.deviceLocal)
            .toList();
      case LibraryFilter.all:
        return items;
    }
  }

  Future<void> _open(MediaItem item) async {
    final progress = await _progressStore?.read(item);
    if (!mounted || _progressStore == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          item: item,
          progressStore: _progressStore!,
          initialPositionMs: progress?.positionMs ?? 0,
        ),
      ),
    );
  }

  Future<void> _share(MediaItem item) async {
    try {
      await _transfer.share(item);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transfer could not start: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.play_circle_fill_rounded,
                color: Raven23PlayerApp.ravenRed, size: 28),
            SizedBox(width: 10),
            Text('RAVEN23 Player',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh library',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<MediaItem>>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || _error != null) {
            return _MessageState(
              icon: Icons.video_library_outlined,
              title: 'Library unavailable',
              message: _error ?? snapshot.error.toString(),
              onAction: _refresh,
            );
          }
          final all = snapshot.data ?? const <MediaItem>[];
          final items = _filtered(all);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your videos, one library',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Play videos on this device or open the shared RAVEN23 library.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.white60),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          children: [
                            _filterChip('All', LibraryFilter.all, all.length),
                            _filterChip(
                              'RAVEN23',
                              LibraryFilter.raven23,
                              all.where((e) =>
                                  e.origin == MediaOrigin.raven23Library).length,
                            ),
                            _filterChip(
                              'On this device',
                              LibraryFilter.device,
                              all.where((e) =>
                                  e.origin == MediaOrigin.deviceLocal).length,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _MessageState(
                      icon: Icons.movie_outlined,
                      title: 'No videos found',
                      message: _filter == LibraryFilter.raven23
                          ? 'No shared RAVEN23 downloads were found yet. Main-app publishing is Phase 01.'
                          : 'Videos stored on this device will appear here.',
                      onAction: _refresh,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                    sliver: SliverList.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _MediaTile(
                        item: items[index],
                        onTap: () => _open(items[index]),
                        onTransfer: () => _share(items[index]),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filterChip(String label, LibraryFilter value, int count) =>
      ChoiceChip(
        label: Text('$label ($count)'),
        selected: _filter == value,
        onSelected: (_) => setState(() => _filter = value),
        selectedColor: Raven23PlayerApp.ravenRed.withValues(alpha: 0.2),
        side: BorderSide(
          color: _filter == value ? Raven23PlayerApp.ravenRed : Colors.white12,
        ),
      );
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.item,
    required this.onTap,
    required this.onTransfer,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    final sizeMb = item.sizeBytes / (1024 * 1024);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Raven23PlayerApp.ravenRed.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            item.origin == MediaOrigin.raven23Library
                ? Icons.download_done_rounded
                : Icons.video_file_rounded,
            color: Raven23PlayerApp.ravenRed,
          ),
        ),
        title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            item.formattedDuration + ' - ' + sizeMb.toStringAsFixed(0) +
                ' MB - ' + item.subtitles.length.toString() + ' subtitle(s)',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'play') onTap();
            if (value == 'transfer') onTransfer();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'play', child: Text('Play')),
            PopupMenuItem(value: 'transfer', child: Text('Transfer')),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 58, color: Colors.white24),
              const SizedBox(height: 14),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60)),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
}
