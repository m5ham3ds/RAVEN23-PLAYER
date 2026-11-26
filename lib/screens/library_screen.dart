// ignore_for_file: prefer_const_constructors

import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:raven23/design/app_palette.dart';
import 'package:raven23/design/app_tokens.dart';
import 'package:raven23/mobile/widgets/page_kit.dart';
import 'package:raven23/mobile/widgets/settings_kit.dart';
import 'package:raven23/provider/app_dependency_provider.dart';
import 'package:raven23/provider/settings_provider.dart';

import '../app.dart';
import '../models/media_item.dart';
import '../services/android_media_library.dart';
import '../services/playback_progress_store.dart';
import '../services/transfer_service.dart';
import '../widgets/app_press_feedback.dart';
import 'player_screen.dart';
import 'app_language_choose_screen.dart';
import 'player_settings.dart';
import '../widgets/occasional_theme_choice_tile.dart';

enum LibraryFilter { all, raven23, device }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  final AndroidMediaLibrary _library = AndroidMediaLibrary();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final TransferService _transfer = TransferService(_library);
  final TextEditingController _search = TextEditingController();
  PlaybackProgressStore? _progress;
  Future<List<MediaItem>>? _load;
  Future<List<_RecentMedia>>? _recentLoad;
  LibraryFilter _filter = LibraryFilter.all;
  int _tab = 0;
  bool _searching = false;
  bool _grid = false;
  String _query = '';
  String? _error;
  late final AnimationController _fadeController;
  final Set<int> _builtTabs = <int>{0};
  bool _drawerOpen = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1,
    );
    _load = _initialise();
    _recentLoad = _load!.then(_loadRecent);
    _search.addListener(() {
      if (mounted) setState(() => _query = _search.text.trim());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<List<MediaItem>> _initialise() async {
    _progress = await PlaybackProgressStore.create();
    return _scan();
  }

  Future<List<MediaItem>> _scan() async {
    if (!Platform.isAndroid) {
      _setError('RAVEN23 Player currently targets Android.');
      return const [];
    }
    try {
      // RAVEN23's companion provider is independent of the public MediaStore
      // video permission. Read it first so private app downloads remain visible
      // even when the user denies access to ordinary phone videos.
      final primaryDownloads = await _library.scanPrimaryDownloads();
      var permission = await Permission.videos.request();
      if (!permission.isGranted && !permission.isLimited) {
        permission = await Permission.storage.request();
      }
      final localVideos = permission.isGranted || permission.isLimited
          ? await _library.scanVideos()
          : const <MediaItem>[];
      final byId = <String, MediaItem>{
        for (final item in localVideos) item.id: item,
        for (final item in primaryDownloads) item.id: item,
      };
      final items = byId.values.toList()
        ..sort((a, b) => b.dateAddedSeconds.compareTo(a.dateAddedSeconds));
      if (mounted) {
        setState(() => _error = null);
        if (!permission.isGranted &&
            !permission.isLimited &&
            items.isEmpty) {
          setState(() => _error = 'Allow video access to scan this device.');
        }
      }
      return items;
    } catch (error) {
      _setError(error.toString());
      rethrow;
    }
  }

  void _setError(String value) {
    if (mounted) setState(() => _error = value);
  }

  Future<void> _refresh() async {
    final next = _scan();
    setState(() {
      _error = null;
      _load = next;
      _recentLoad = next.then(_loadRecent);
    });
    await next;
  }

  Future<List<_RecentMedia>> _loadRecent(List<MediaItem> items) async {
    final store = _progress;
    if (store == null || items.isEmpty) return const [];
    final sorted = [...items]
      ..sort((a, b) => b.dateAddedSeconds.compareTo(a.dateAddedSeconds));
    final values = await Future.wait(sorted.take(500).map((item) async {
      final saved = await store.read(item);
      if (saved == null || saved.positionMs < 10000) return null;
      if (saved.durationMs > 0 && saved.positionMs >= saved.durationMs - 5000) {
        return null;
      }
      return _RecentMedia(item, saved);
    }));
    final recent = values.whereType<_RecentMedia>().toList()
      ..sort((a, b) => b.progress.updatedAtUtc.compareTo(a.progress.updatedAtUtc));
    return recent.take(12).toList(growable: false);
  }

  List<MediaItem> _filtered(List<MediaItem> source) {
    final query = _query.toLowerCase();
    final items = source.where((item) {
      if (_filter == LibraryFilter.raven23 &&
          item.origin == MediaOrigin.deviceLocal) {
        return false;
      }
      if (_filter == LibraryFilter.device &&
          item.origin != MediaOrigin.deviceLocal) {
        return false;
      }
      return query.isEmpty || item.title.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => b.dateAddedSeconds.compareTo(a.dateAddedSeconds));
    return items;
  }

  Future<void> _open(MediaItem item) async {
    final saved = await _progress?.read(item);
    if (!mounted || _progress == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        item: item,
        progressStore: _progress!,
        initialPositionMs: saved?.positionMs ?? 0,
      ),
    ));
    if (mounted) setState(() => _recentLoad = _load!.then(_loadRecent));
  }

  Future<void> _share(MediaItem item) async {
    try {
      await _transfer.share(item);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('player_transfer_failed', namedArgs: {'error': error.toString()}))),
      );
    }
  }

  void _selectTab(int value) {
    if (value == 2) {
      _playFeatured();
      return;
    }
    if (value != 1 && value != 3 && _searching) {
      _searching = false;
      _search.clear();
    }
    if (_tab == value) return;
    setState(() {
      _tab = value;
      _builtTabs.add(value);
    });
    _fadeController.forward(from: 0);
  }

  Future<void> _playFeatured() async {
    final recent = await _recentLoad;
    final videos = await _load;
    if (!mounted) return;
    if (videos == null || videos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('player_no_videos_available'))),
      );
      return;
    }
    await _open(recent?.first.item ?? videos.first);
  }

  void _beginSearch() {
    setState(() {
      _searching = true;
      _tab = 1;
      _builtTabs.add(1);
    });
    _fadeController.forward(from: 0);
  }

  void _endSearch() {
    setState(() {
      _searching = false;
      _search.clear();
      _query = '';
    });
  }

  String _count(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 10000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tab == 0 && !_drawerOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_drawerOpen) {
          _scaffoldKey.currentState?.closeDrawer();
        } else {
          _selectTab(0);
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _drawer(),
      onDrawerChanged: (open) {
        if (_drawerOpen != open && mounted) {
          setState(() => _drawerOpen = open);
        }
      },
      appBar: AppBar(
        toolbarHeight: 62,
        leadingWidth: 52,
        titleSpacing: 2,
        leading: Builder(
          builder: (context) => AppPressFeedback(
            child: IconButton(
              onPressed: _searching
                  ? _endSearch
                  : () => Scaffold.of(context).openDrawer(),
              icon: Icon(_searching ? Icons.arrow_back : Icons.menu_rounded),
            ),
          ),
        ),
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                cursorColor: Raven23PlayerApp.ravenRed,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: tr('player_search_videos'),
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              )
            : const _Brand(),
        actions: [
          AppPressFeedback(
            child: IconButton(
              onPressed: _searching ? _endSearch : _beginSearch,
              icon: Icon(_searching ? Icons.close : Icons.search_rounded),
            ),
          ),
          AppPressFeedback(
            child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'refresh') _refresh();
              if (value == 'settings') _selectTab(4);
              if (value == 'about') {
                showAboutDialog(
                  context: context,
                  applicationName: 'RAVEN23 Player',
                  applicationVersion: '0.1.0',
                  children: [Text(tr('player_tagline'))],
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'refresh', child: Text(tr('player_refresh_library'))),
              PopupMenuItem(value: 'settings', child: Text(tr('settings'))),
              PopupMenuItem(value: 'about', child: Text(tr('about'))),
            ],
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<List<MediaItem>>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingView();
          }
          if (snapshot.hasError || _error != null) {
            return _MessageView(
              icon: Icons.video_library_outlined,
              title: tr('player_library_waiting'),
              message: _error ?? snapshot.error.toString(),
              onRefresh: _refresh,
            );
          }
          final videos = snapshot.data ?? const <MediaItem>[];
          return _tabStack(videos);
        },
      ),
        bottomNavigationBar: _BottomBar(selected: _tab, onSelect: _selectTab),
      ),
    );
  }

  Widget _tabStack(List<MediaItem> videos) => Stack(
        fit: StackFit.expand,
        children: [
          for (final tab in const [0, 1, 3, 4])
            if (_builtTabs.contains(tab))
              Offstage(
                offstage: tab != _tab,
                child: TickerMode(
                  enabled: tab == _tab,
                  child: ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: FadeTransition(
                      opacity: tab == _tab
                          ? _fadeController
                          : kAlwaysCompleteAnimation,
                      child: RepaintBoundary(
                        child: switch (tab) {
                          1 => _collection(videos, tr('player_all_videos')),
                          3 => _collection(videos, tr('player_video_library')),
                          4 => _settings(videos),
                          _ => _home(videos),
                        },
                      ),
                    ),
                  ),
                ),
              ),
        ],
      );

  void _selectFilterTab(LibraryFilter filter) {
    setState(() => _filter = filter);
    _selectTab(3);
  }

  Widget _home(List<MediaItem> videos) {
    final raven = videos.where((v) => v.origin == MediaOrigin.raven23Library ||
        v.origin == MediaOrigin.raven23Download).length;
    final device = videos.where((v) => v.origin == MediaOrigin.deviceLocal).length;
    return RefreshIndicator(
      color: Raven23PlayerApp.ravenRed,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          const _HeroBanner(),
          const SizedBox(height: 18),
          SizedBox(
            height: 104,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _Stat(
                  icon: Icons.play_arrow_rounded,
                  label: tr('player_all_videos'),
                  value: _count(videos.length),
                  selected: true,
                  onTap: () => _selectTab(1),
                ),
                const SizedBox(width: 9),
                _Stat(
                  icon: Icons.folder_outlined,
                  label: tr('player_on_device'),
                  value: _count(device),
                  onTap: () => _selectFilterTab(LibraryFilter.device),
                ),
                const SizedBox(width: 9),
                _Stat(
                  icon: Icons.layers_rounded,
                  label: 'RAVEN23',
                  value: _count(raven),
                  onTap: () => _selectFilterTab(LibraryFilter.raven23),
                ),
                const SizedBox(width: 9),
                FutureBuilder<List<_RecentMedia>>(
                  future: _recentLoad,
                  builder: (context, snapshot) => _Stat(
                    icon: Icons.schedule_rounded,
                    label: tr('recent'),
                    value: _count(snapshot.data?.length ?? 0),
                    onTap: () => _selectTab(1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _LibraryShortcut(onTap: () => _selectTab(3)),
          const SizedBox(height: 22),
          FutureBuilder<List<_RecentMedia>>(
            future: _recentLoad,
            builder: (context, snapshot) {
              final recent = snapshot.data ?? const <_RecentMedia>[];
              if (recent.isEmpty) return const SizedBox.shrink();
              return _ContinueSection(
                items: recent,
                onOpen: _open,
                onAll: () => _selectTab(1),
              );
            },
          ),
          const SizedBox(height: 23),
          _SectionTitle(
            icon: Icons.video_library_rounded,
            title: tr('player_all_videos'),
            trailing: _count(videos.length),
            onAll: () => _selectTab(1),
          ),
          const SizedBox(height: 10),
          if (videos.isEmpty)
            const _EmptyVideos()
          else
            ..._filtered(videos).take(4).map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _VideoTile(
                item: item,
                onTap: () => _open(item),
                onTransfer: () => _share(item),
              ),
            )),
          if (videos.isNotEmpty)
            TextButton(
              onPressed: () => _selectTab(1),
              child: Text(tr('player_explore_library')),
            ),
        ],
      ),
    );
  }

  Widget _collection(List<MediaItem> videos, String title) {
    final items = _filtered(videos);
    final raven = videos.where((v) => v.origin == MediaOrigin.raven23Library ||
        v.origin == MediaOrigin.raven23Download).length;
    final device = videos.where((v) => v.origin == MediaOrigin.deviceLocal).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 5),
              Text(tr('player_videos_available', namedArgs: {'count': items.length.toString()}),
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
              if (_tab == 3) ...[
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _FilterChip(label: tr('filter_all'), count: videos.length,
                      selected: _filter == LibraryFilter.all,
                      onTap: () => setState(() => _filter = LibraryFilter.all)),
                    const SizedBox(width: 8),
                    _FilterChip(label: tr('player_on_device'), count: device,
                      selected: _filter == LibraryFilter.device,
                      onTap: () => setState(() => _filter = LibraryFilter.device)),
                    const SizedBox(width: 8),
                    _FilterChip(label: 'RAVEN23', count: raven,
                      selected: _filter == LibraryFilter.raven23,
                      onTap: () => setState(() => _filter = LibraryFilter.raven23)),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Text(tr('player_your_collection'), style: TextStyle(
                  color: Colors.white38, fontSize: 10,
                  fontWeight: FontWeight.w800, letterSpacing: 1.8)),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('manga_list_view'),
                  onPressed: () => setState(() => _grid = false),
                  icon: Icon(Icons.view_list_rounded,
                      color: !_grid ? Raven23PlayerApp.ravenRed : Colors.white54),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('manga_grid_view'),
                  onPressed: () => setState(() => _grid = true),
                  icon: Icon(Icons.grid_view_rounded,
                      color: _grid ? Raven23PlayerApp.ravenRed : Colors.white54),
                ),
              ]),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _MessageView(
                  icon: Icons.movie_filter_outlined,
                  title: _query.isNotEmpty ? tr('player_no_matches_found') : tr('player_no_videos_yet'),
                  message: _query.isNotEmpty
                      ? tr('player_try_another_title')
                      : _filter == LibraryFilter.raven23
                          ? tr('player_raven_downloads_empty')
                          : tr('player_device_videos_empty'),
                  onRefresh: _query.isNotEmpty ? _endSearch : _refresh,
                )
              : _grid
                  ? GridView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 22),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.89,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) => _GridVideo(
                        item: items[index],
                        onTap: () => _open(items[index]),
                        onTransfer: () => _share(items[index]),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 22),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (context, index) => _VideoTile(
                        item: items[index],
                        onTap: () => _open(items[index]),
                        onTransfer: () => _share(items[index]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _settings(List<MediaItem> videos) {
    final settings = context.watch<SettingsProvider>();
    final appDependencies = context.watch<AppDependencyProvider>();
    final occasionalCatalog = appDependencies.occasionalThemeCatalog;
    final occasionalThemes = appDependencies.availableOccasionalThemes;
    final palette = AppPalette.of(context);
    final language = _currentLanguage(settings.appLanguage);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpace.gutter(context),
        AppSpace.sm,
        AppSpace.gutter(context),
        AppSpace.xxxl + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text(
          tr('settings'),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.35,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          tr('player_manage_library'),
          style: AppType.metadata.copyWith(color: palette.mutedText),
        ),
        const SizedBox(height: 18),

        Material(
          color: palette.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          clipBehavior: Clip.antiAlias,
          child: AppPressFeedback(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.card),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AppLanguageChooseScreen(),
                  ),
                );
              },
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpace.gutter(context),
                  vertical: AppSpace.md,
                ),
                child: Row(
                  children: [
                    Icon(
                      PhosphorIcons.translate(),
                      color: palette.mutedText,
                      size: 22,
                    ),
                    const SizedBox(width: AppSpace.lg),
                    Expanded(
                      child: Text(
                        tr('app_language'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.cardTitle.copyWith(
                          fontSize: 15,
                          color: palette.foreground,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * .42,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (language.flag != null)
                            LanguageFlag(
                              'packages/raven23/assets/images/country_flags/${language.flag}.png',
                            )
                          else
                            Icon(
                              PhosphorIcons.deviceMobile(),
                              color: palette.mutedText,
                              size: 20,
                            ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              language.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: AppType.body.copyWith(
                                color: palette.mutedText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: palette.mutedText,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SettingsGroup(
          title: tr('appearance'),
          children: [
            ChoiceRow<String>(
              icon: PhosphorIcons.moon(),
              label: tr('theme_mode'),
              value: settings.appTheme,
              options: {
                'dark': tr('dark'),
                'light': tr('light'),
                'amoled': tr('amoled'),
              },
              onChanged: (value) => settings.appTheme = value,
            ),
            SwitchRow(
              icon: PhosphorIcons.imageSquare(),
              label: tr('ambient_mode'),
              subtitle: tr('ambient_mode_description'),
              value: appDependencies.ambientModeEnabled,
              onChanged: (value) =>
                  appDependencies.ambientModeEnabled = value,
            ),
            if (occasionalCatalog.enabled)
              SwitchRow(
                icon: PhosphorIcons.sparkle(),
                label: tr('seasonal_themes'),
                subtitle: tr('seasonal_themes_description'),
                value: appDependencies.occasionalThemeEnabled,
                onChanged: (value) =>
                    appDependencies.occasionalThemeEnabled = value,
              ),
            if (occasionalCatalog.enabled &&
                appDependencies.occasionalThemeEnabled &&
                occasionalCatalog.allowUserSelection &&
                occasionalThemes.isNotEmpty)
              OccasionalThemeChoiceTile(provider: appDependencies),
            if (occasionalCatalog.enabled &&
                appDependencies.occasionalThemeEnabled &&
                occasionalCatalog.effectsEnabled &&
                occasionalCatalog.allowUserEffectsToggle)
              SwitchRow(
                icon: PhosphorIcons.confetti(),
                label: tr('seasonal_effects'),
                subtitle: tr('seasonal_effects_description'),
                value: appDependencies.occasionalEffectsEnabled,
                onChanged: (value) =>
                    appDependencies.occasionalEffectsEnabled = value,
              ),
            ListRow(
              icon: PhosphorIcons.play(),
              label: tr('player_settings'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PlayerSettings(),
                  ),
                );
              },
            ),
            ListRow(
              icon: Icons.video_library_outlined,
              label: tr('player_media_library'),
              subtitle: tr(
                'player_media_library_subtitle',
                namedArgs: {'count': videos.length.toString()},
              ),
              onTap: _refresh,
              trailing: Icon(Icons.refresh_rounded, color: palette.mutedText),
              showsNext: false,
            ),
            ListRow(
              icon: Icons.folder_shared_outlined,
              label: tr('player_shared_library'),
              subtitle: tr('player_shared_library_subtitle'),
              onTap: () => _selectTab(3),
            ),
            ListRow(
              icon: Icons.history_rounded,
              label: tr('player_playback_history'),
              subtitle: tr('player_playback_history_subtitle'),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: palette.mutedText,
              ),
              showsNext: false,
            ),
            ListRow(
              icon: Icons.swap_horiz_rounded,
              label: tr('player_transfer'),
              subtitle: tr('player_transfer_subtitle'),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: palette.mutedText,
              ),
              showsNext: false,
            ),
          ],
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Raven23PlayerApp.ravenRed.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.play_circle_fill_rounded,
                color: Raven23PlayerApp.ravenRed,
                size: 34,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RAVEN23 Player',
                      style: TextStyle(
                        color: palette.foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tr('player_tagline'),
                      style: TextStyle(color: palette.mutedText, fontSize: 12),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      tr('player_version', namedArgs: {'version': '0.1.0'}),
                      style: TextStyle(color: palette.mutedText, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  ({String? flag, String label}) _currentLanguage(String code) {
    if (code == 'system') {
      return (
        flag: null,
        label: tr('player_system_language'),
      );
    }
    return switch (code) {
      'ar' => (flag: 'united-arab-emirates', label: tr('arabic')),
      _ => (flag: 'united-kingdom', label: tr('english')),
    };
  }

  Drawer _drawer() => Drawer(
    backgroundColor: const Color(0xFF111111),
    child: SafeArea(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 28),
          child: _Brand(),
        ),
        _DrawerItem(icon: Icons.home_rounded, title: tr('home'),
          selected: _tab == 0, onTap: () {
            Navigator.pop(context);
            _selectTab(0);
          }),
        _DrawerItem(icon: Icons.video_library_rounded, title: tr('player_all_videos'),
          selected: _tab == 1, onTap: () {
            Navigator.pop(context);
            _selectTab(1);
          }),
        _DrawerItem(icon: Icons.folder_rounded, title: tr('player_video_library'),
          selected: _tab == 3, onTap: () {
            Navigator.pop(context);
            _selectTab(3);
          }),
        _DrawerItem(icon: Icons.settings_rounded, title: tr('settings'),
          selected: _tab == 4, onTap: () {
            Navigator.pop(context);
            _selectTab(4);
          }),
        const Spacer(),
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('RAVEN23 PLAYER  •  0.1.0',
            style: TextStyle(color: Colors.white24, fontSize: 10,
                letterSpacing: 1.2)),
        ),
      ],
    )),
  );
}

class _RecentMedia {
  const _RecentMedia(this.item, this.progress);
  final MediaItem item;
  final PlaybackProgress progress;
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.play_circle_fill_rounded,
          color: Raven23PlayerApp.ravenRed, size: 30),
      const SizedBox(width: 8),
      Flexible(child: RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: const TextSpan(
          style: TextStyle(color: Colors.white, fontSize: 18,
              fontWeight: FontWeight.w900, letterSpacing: -0.6),
          children: [
            TextSpan(text: 'RAVEN'),
            TextSpan(text: '23', style: TextStyle(
                color: Raven23PlayerApp.ravenRed)),
            TextSpan(text: ' Player', style: TextStyle(
                fontWeight: FontWeight.w500, fontStyle: FontStyle.italic)),
          ],
        ),
      )),
    ],
  );
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) => Container(
    height: 206,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      boxShadow: [
        BoxShadow(
          color: Raven23PlayerApp.ravenRed.withValues(alpha: 0.13),
          blurRadius: 26,
          spreadRadius: -8,
        ),
      ],
    ),
    child: Stack(fit: StackFit.expand, children: [
      const CustomPaint(painter: _HeroPainter()),
      Positioned(
        left: 20,
        top: 28,
        width: MediaQuery.sizeOf(context).width * 0.52,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: 'RAVEN'),
              TextSpan(text: '23', style: TextStyle(
                  color: Raven23PlayerApp.ravenRed)),
            ]), style: TextStyle(color: Colors.white, fontSize: 29,
                fontWeight: FontWeight.w900, height: 1,
                letterSpacing: -1.2, fontStyle: FontStyle.italic)),
            Text('Player', style: TextStyle(color: Colors.white, fontSize: 28,
                fontWeight: FontWeight.w900, height: 1.05,
                fontStyle: FontStyle.italic, letterSpacing: -1)),
            SizedBox(height: 12),
            Text(tr('player_tagline'), style: TextStyle(
                color: Colors.white70, fontSize: 13,
                fontWeight: FontWeight.w500)),
            SizedBox(height: 12),
            SizedBox(width: 54, child: Divider(
                color: Raven23PlayerApp.ravenRed, thickness: 4, height: 4)),
          ],
        ),
      ),
      Positioned(right: 14, bottom: 12, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(children: [
          Icon(Icons.bolt_rounded, color: Raven23PlayerApp.ravenRed, size: 14),
          SizedBox(width: 4),
          Text(tr('player_play_your_way'), style: TextStyle(color: Colors.white70,
              fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        ]),
      )),
    ]),
  );
}

class _HeroPainter extends CustomPainter {
  const _HeroPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..shader = const LinearGradient(
      colors: [Color(0xFF180607), Color(0xFF08090C), Color(0xFF050505)],
      begin: Alignment.topLeft, end: Alignment.bottomRight,
    ).createShader(bounds));

    final moon = Offset(size.width * 0.78, size.height * 0.42);
    final radius = size.height * 0.37;
    canvas.drawCircle(moon, radius * 1.55, Paint()..shader = RadialGradient(
      colors: [
        const Color(0xFFFF171F).withValues(alpha: 0.30),
        const Color(0xFF9B090F).withValues(alpha: 0.12),
        Colors.transparent,
      ],
    ).createShader(Rect.fromCircle(center: moon, radius: radius * 1.55)));
    canvas.drawCircle(moon, radius, Paint()..shader = const RadialGradient(
      colors: [Color(0xFFFF5552), Color(0xFFB10A12), Color(0xFF4C0308)],
      center: Alignment(-0.25, -0.3),
    ).createShader(Rect.fromCircle(center: moon, radius: radius)));
    canvas.drawCircle(moon, radius * 0.94, Paint()
      ..color = const Color(0xFFFF8A7C).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);

    final mountains = Path()
      ..moveTo(0, size.height * 0.79)
      ..lineTo(size.width * 0.18, size.height * 0.52)
      ..lineTo(size.width * 0.34, size.height * 0.76)
      ..lineTo(size.width * 0.51, size.height * 0.59)
      ..lineTo(size.width * 0.68, size.height * 0.81)
      ..lineTo(size.width, size.height * 0.57)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(mountains, Paint()..shader = const LinearGradient(
      colors: [Color(0xFF1B1013), Color(0xFF060608)],
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
    ).createShader(bounds));

    final ridge = Path()
      ..moveTo(0, size.height * 0.89)
      ..lineTo(size.width * 0.2, size.height * 0.77)
      ..lineTo(size.width * 0.42, size.height * 0.88)
      ..lineTo(size.width * 0.60, size.height * 0.74)
      ..lineTo(size.width * 0.78, size.height * 0.87)
      ..lineTo(size.width, size.height * 0.76)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(ridge, Paint()..color = const Color(0xFF030304));
    _drawRaven(canvas, size);
    canvas.drawRect(bounds, Paint()..shader = RadialGradient(
      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.2),
        Colors.black.withValues(alpha: 0.58)],
      stops: const [0.4, 0.78, 1],
    ).createShader(bounds));
  }

  void _drawRaven(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width * 0.78, size.height * 0.78);
    canvas.scale(size.height / 206);
    final dark = Paint()..color = const Color(0xFF050609);
    final wing = Paint()..color = const Color(0xFF171B23);
    final tail = Path()
      ..moveTo(-15, -28)..lineTo(-62, 3)..lineTo(-25, -10)
      ..lineTo(-66, 20)..lineTo(-8, 1)..close();
    canvas.drawPath(tail, dark);
    canvas.drawOval(Rect.fromCenter(center: const Offset(-1, -15),
        width: 76, height: 38), dark);
    final feathers = Path()
      ..moveTo(-29, -31)
      ..quadraticBezierTo(-58, -74, -11, -72)
      ..quadraticBezierTo(31, -67, 42, -28)
      ..quadraticBezierTo(10, -38, -29, -31)
      ..close();
    canvas.drawPath(feathers, wing);
    final neck = Path()
      ..moveTo(5, -31)
      ..quadraticBezierTo(11, -63, 27, -70)
      ..lineTo(42, -61)..lineTo(36, -39)..close();
    canvas.drawPath(neck, dark);
    canvas.drawCircle(const Offset(35, -69), 12, dark);
    final beak = Path()
      ..moveTo(44, -69)..lineTo(67, -62)..lineTo(45, -57)..close();
    canvas.drawPath(beak, dark);
    canvas.drawCircle(const Offset(39, -72), 2.6,
        Paint()..color = Raven23PlayerApp.ravenRed);
    canvas.drawCircle(const Offset(39, -72), 6,
        Paint()..color = Raven23PlayerApp.ravenRed.withValues(alpha: 0.24));
    final branch = Path()
      ..moveTo(-77, 12)
      ..quadraticBezierTo(-24, -1, 26, 13)
      ..quadraticBezierTo(55, 17, 83, 8);
    canvas.drawPath(branch, Paint()
      ..color = const Color(0xFF171417)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value,
    required this.onTap, this.selected = false});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? Raven23PlayerApp.ravenRed.withValues(alpha: 0.78)
        : Colors.white.withValues(alpha: 0.12);
    return AppPressFeedback(
      child: SizedBox(width: 108, child: Material(
        color: selected ? const Color(0xFF381013) : const Color(0xFF151515),
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: border, width: selected ? 1.4 : 1),
              boxShadow: selected ? [BoxShadow(
                color: Raven23PlayerApp.ravenRed.withValues(alpha: 0.12),
                blurRadius: 18)] : null,
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: Colors.white, size: 25),
              const SizedBox(height: 5),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(
                  color: Colors.white70, fontSize: 12)),
            ]),
          ),
        ),
      )),
    );
  }
}
class _LibraryShortcut extends StatelessWidget {
  const _LibraryShortcut({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppPressFeedback(
    child: Material(
      color: const Color(0xFF211415),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Raven23PlayerApp.ravenRed.withValues(alpha: 0.24)),
          ),
          child: Row(children: [
            const Icon(Icons.folder_open_rounded,
                color: Raven23PlayerApp.ravenRed, size: 36),
            const SizedBox(width: 15),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('player_video_library'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(tr('player_browse_manage_videos'),
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            )),
            const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
          ]),
        ),
      ),
    ),
  );
}
class _ContinueSection extends StatelessWidget {
  const _ContinueSection({required this.items, required this.onOpen,
    required this.onAll});

  final List<_RecentMedia> items;
  final ValueChanged<MediaItem> onOpen;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionTitle(icon: Icons.play_arrow_rounded,
        title: tr('continue_watching'), onAll: onAll),
      const SizedBox(height: 12),
      SizedBox(height: 174, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 11),
        itemBuilder: (context, index) {
          final recent = items[index];
          return _ContinueCard(recent: recent,
              onTap: () => onOpen(recent.item));
        },
      )),
    ],
  );
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.recent, required this.onTap});
  final _RecentMedia recent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = recent.progress.durationMs;
    final fraction = duration <= 0 ? 0.0 :
        (recent.progress.positionMs / duration).clamp(0.0, 1.0).toDouble();
    return AppPressFeedback(
      child: SizedBox(width: 168, child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Stack(fit: StackFit.expand, children: [
            _MediaThumbnail(item: recent.item),
            Container(decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white24))),
            const Center(child: CircleAvatar(
              radius: 20, backgroundColor: Color(0x99000000),
              child: Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 27))),
            Positioned(left: 8, right: 8, bottom: 8, child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: fraction, minHeight: 4,
                backgroundColor: Colors.white24,
                color: Raven23PlayerApp.ravenRed))),
          ])),
          const SizedBox(height: 7),
          Text(recent.item.title, maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(tr('player_watched_percent', namedArgs: {'percent': (fraction * 100).round().toString()}),
            style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ]),
      )),
    );
  }
}
class _MediaThumbnail extends StatelessWidget {
  const _MediaThumbnail({
    required this.item,
    this.width,
    this.height,
    this.radius = 13,
  });

  final MediaItem item;
  final double? width;
  final double? height;
  final double radius;

  static final AndroidMediaLibrary _library = AndroidMediaLibrary();
  static final Map<String, Future<Uint8List?>> _thumbnailFutures =
      <String, Future<Uint8List?>>{};

  String? get _posterUrl {
    final direct = item.posterUrl?.trim();
    if (direct != null && direct.isNotEmpty) {
      final parsed = Uri.tryParse(direct);
      if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
        return direct;
      }
    }
    var path = (item.posterPath ?? '').trim();
    if (path.isEmpty) path = (item.backdropPath ?? '').trim();
    if (path.isEmpty) return null;
    final parsed = Uri.tryParse(path);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      return path;
    }
    path = path.replaceFirst(RegExp(r'^/+'), '');
    path = path.replaceFirst(RegExp(r'^w\d+/'), '');
    return 'https://image.tmdb.org/t/p/w500/$path';
  }

  Future<Uint8List?> _thumbnailFuture() {
    final uri = item.contentUri.trim();
    if (uri.isEmpty) return Future<Uint8List?>.value(null);
    final cached = _thumbnailFutures[uri];
    if (cached != null) return cached;
    if (_thumbnailFutures.length >= 128) {
      _thumbnailFutures.remove(_thumbnailFutures.keys.first);
    }
    final future = _library.videoThumbnail(uri);
    _thumbnailFutures[uri] = future;
    return future;
  }

  Widget _placeholder() => DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF171717)),
        child: Center(
          child: Icon(
            item.origin == MediaOrigin.raven23Download
                ? Icons.movie_outlined
                : Icons.video_file_outlined,
            color: Colors.white30,
            size: 30,
          ),
        ),
      );

  Widget _posterFallback() {
    final poster = _posterUrl;
    if (poster == null) return _placeholder();
    return Image.network(
      poster,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _frame(Uint8List bytes) => Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _posterFallback(),
      );

  @override
  Widget build(BuildContext context) {
    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: FutureBuilder<Uint8List?>(
        future: _thumbnailFuture(),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) return _frame(bytes);
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _placeholder();
          }
          // Prefer the decoded frame; poster artwork is only the fallback.
          return _posterFallback();
        },
      ),
    );
    if (width != null || height != null) {
      return SizedBox(width: width, height: height, child: clipped);
    }
    return SizedBox.expand(child: clipped);
  }
}
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title,
    this.trailing, this.onAll});

  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback? onAll;

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: Raven23PlayerApp.ravenRed, size: 24),
    const SizedBox(width: 8),
    Expanded(child: Text(title, maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800,
          letterSpacing: -0.35))),
    if (trailing != null)
      Text(trailing!, style: const TextStyle(
          color: Colors.white54, fontSize: 12)),
    if (onAll != null)
      AppPressFeedback(
        child: TextButton(
          onPressed: onAll,
          style: TextButton.styleFrom(
            foregroundColor: Raven23PlayerApp.ravenRed,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 5)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('view_all'), style: TextStyle(fontWeight: FontWeight.w700)),
            Icon(Icons.chevron_right_rounded, size: 18),
          ]),
        ),
      ),
  ]);
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.item, required this.onTap,
    required this.onTransfer});

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    final sizeMb = item.sizeBytes / (1024 * 1024);
    final sourceLabel = item.origin == MediaOrigin.raven23Download
        ? 'RAVEN23 DOWNLOAD'
        : item.origin == MediaOrigin.raven23Library
            ? 'RAVEN23 LIBRARY'
            : 'ON THIS DEVICE';
    return AppPressFeedback(
      child: Material(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: item.isPlayable ? onTap : null,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 3, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
            ),
            child: Row(children: [
              _MediaThumbnail(item: item, width: 56, height: 56, radius: 14),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w700)),
                  const SizedBox(height: 7),
                  Wrap(spacing: 11, runSpacing: 4, children: [
                    _Metadata(icon: Icons.play_circle_outline_rounded,
                        text: item.formattedDuration),
                    _Metadata(icon: Icons.storage_rounded,
                        text: '${sizeMb.toStringAsFixed(0)} MB'),
                    _Metadata(icon: Icons.subtitles_outlined,
                        text: '${item.subtitles.length} subtitle(s)'),
                  ]),
                  const SizedBox(height: 5),
                  Text(
                    sourceLabel,
                    style: TextStyle(
                      color: item.origin == MediaOrigin.deviceLocal
                          ? Colors.white38 : Raven23PlayerApp.ravenRed,
                      fontSize: 9, fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
                ],
              )),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                onSelected: (value) {
                  if (value == 'play' && item.isPlayable) onTap();
                  if (value == 'transfer') onTransfer();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'play',
                    enabled: item.isPlayable,
                    child: Text(tr('play')),
                  ),
                  PopupMenuItem(value: 'transfer', child: Text(tr('player_transfer'))),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
class _Metadata extends StatelessWidget {
  const _Metadata({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: Colors.white38, size: 13),
      const SizedBox(width: 3),
      Text(text, style: const TextStyle(color: Colors.white54, fontSize: 10)),
    ],
  );
}

class _GridVideo extends StatelessWidget {
  const _GridVideo({required this.item, required this.onTap,
    required this.onTransfer});

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) => AppPressFeedback(
    child: Material(
      color: const Color(0xFF171717),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: item.isPlayable ? onTap : null,
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Stack(fit: StackFit.expand, children: [
              _MediaThumbnail(item: item),
              if (item.isPlayable)
                const Center(child: Icon(Icons.play_circle_fill_rounded,
                    color: Colors.white, size: 38)),
              Positioned(right: 3, top: 3,
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                  onSelected: (value) {
                    if (value == 'play' && item.isPlayable) onTap();
                    if (value == 'transfer') onTransfer();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'play', enabled: item.isPlayable,
                      child: Text(tr('play')),
                    ),
                    const PopupMenuItem(
                      value: 'transfer', child: Text(tr('player_transfer'))),
                  ],
                )),
            ])),
            const SizedBox(height: 9),
            Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text(tr('player_subtitle_count', namedArgs: {'duration': item.formattedDuration, 'count': item.subtitles.length.toString()}),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ]),
        ),
      ),
    ),
  );
}
class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.count,
    required this.selected, required this.onTap});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppPressFeedback(
    child: Material(
      color: selected ? const Color(0xFF3A1115) : const Color(0xFF171717),
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: selected
                ? Raven23PlayerApp.ravenRed.withValues(alpha: 0.65)
                : Colors.white12)),
          child: Text('$label  $count', style: TextStyle(
            color: selected ? Colors.white : Colors.white60,
            fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ),
    ),
  );
}
class _DrawerItem extends StatelessWidget {
  const _DrawerItem({required this.icon, required this.title,
    required this.selected, required this.onTap});

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppPressFeedback(
    child: ListTile(
      selected: selected,
      selectedTileColor: Raven23PlayerApp.ravenRed.withValues(alpha: 0.12),
      leading: Icon(icon,
          color: selected ? Raven23PlayerApp.ravenRed : Colors.white60),
      title: Text(title, style: TextStyle(
        color: selected ? Colors.white : Colors.white70,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
      onTap: onTap,
    ),
  );
}
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 82,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Positioned.fill(
              top: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: palette.surface,
                  border: Border(top: BorderSide(color: palette.hairline)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 18,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _NavItem(
                        icon: Icons.home_rounded,
                        label: tr('home'),
                        active: selected == 0,
                        onTap: () => onSelect(0),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.video_library_rounded,
                        label: tr('videos'),
                        active: selected == 1,
                        onTap: () => onSelect(1),
                      ),
                    ),
                    const SizedBox(width: 68),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.folder_outlined,
                        label: tr('player_library'),
                        active: selected == 3,
                        onTap: () => onSelect(3),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.settings_outlined,
                        label: tr('settings'),
                        active: selected == 4,
                        onTap: () => onSelect(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              child: Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF343B), Color(0xFFB9000B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: const Color(0xFFFF8A8D),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Raven23PlayerApp.ravenRed.withValues(alpha: 0.42),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: AppPressFeedback(
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => onSelect(2),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = active ? Raven23PlayerApp.ravenRed : palette.mutedText;
    return AppPressFeedback(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: active ? 24 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: Raven23PlayerApp.ravenRed,
                borderRadius: BorderRadius.circular(2),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: Raven23PlayerApp.ravenRed.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _EmptyVideos extends StatelessWidget {
  const _EmptyVideos();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(children: [
      const Icon(Icons.video_collection_outlined,
          color: Colors.white24, size: 42),
      const SizedBox(height: 8),
      Text(tr('player_no_videos_found'),
          style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 4),
      Text(tr('player_refresh_after_adding'),
          style: const TextStyle(color: Colors.white38, fontSize: 11)),
    ]),
  );
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(width: 34, height: 34,
        child: CircularProgressIndicator(
          strokeWidth: 3, color: Raven23PlayerApp.ravenRed)),
      const SizedBox(height: 14),
      Text(tr('player_scanning_library'),
          style: const TextStyle(color: Colors.white60, fontSize: 12)),
    ],
  ));
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.icon, required this.title,
    required this.message, required this.onRefresh});

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 58, color: Raven23PlayerApp.ravenRed),
      const SizedBox(height: 15),
      Text(title, style: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(message, textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, height: 1.5)),
      const SizedBox(height: 18),
      AppPressFeedback(
        child: FilledButton.icon(
          onPressed: onRefresh,
          style: FilledButton.styleFrom(
            backgroundColor: Raven23PlayerApp.ravenRed,
            foregroundColor: Colors.white),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(tr('player_refresh_library')),
        ),
      ),
    ]),
  ));
}
