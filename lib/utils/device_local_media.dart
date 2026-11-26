import '../models/media_item.dart';

/// Restrict the local-player playlist to files indexed directly from this phone.
/// Companion-app library entries and private RAVEN23 downloads are excluded.
List<MediaItem> deviceLocalMedia(Iterable<MediaItem> items) =>
    List<MediaItem>.unmodifiable(
      items.where(
        (item) => item.origin == MediaOrigin.deviceLocal && item.isPlayable,
      ),
    );
