import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_item.dart';

class PlaybackProgress {
  const PlaybackProgress({
    required this.positionMs,
    required this.durationMs,
    required this.updatedAtUtc,
  });

  final int positionMs;
  final int durationMs;
  final DateTime updatedAtUtc;

  Map<String, Object?> toJson() => {
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
      };

  factory PlaybackProgress.fromJson(Map<String, dynamic> json) =>
      PlaybackProgress(
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        updatedAtUtc: DateTime.tryParse(
              json['updatedAtUtc']?.toString() ?? '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}

class PlaybackProgressStore {
  PlaybackProgressStore(this._preferences);

  final SharedPreferences _preferences;

  static Future<PlaybackProgressStore> create() async =>
      PlaybackProgressStore(await SharedPreferences.getInstance());

  String _key(MediaItem item) =>
      'raven23_player.progress.v1.' +
      item.origin.name +
      '.' +
      Uri.encodeComponent(item.id);

  Future<PlaybackProgress?> read(MediaItem item) async {
    final value = _preferences.getString(_key(item));
    if (value == null) return null;
    try {
      return PlaybackProgress.fromJson(
        Map<String, dynamic>.from(jsonDecode(value) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(
    MediaItem item, {
    required int positionMs,
    required int durationMs,
  }) async {
    // All positions remain in this app's private store. Phase 02 will upload
    // only separately validated RAVEN23 identities; deviceLocal never uploads.
    final safePosition = positionMs < 0
        ? 0
        : durationMs > 0 && positionMs > durationMs
            ? durationMs
            : positionMs;
    final payload = PlaybackProgress(
      positionMs: safePosition,
      durationMs: durationMs,
      updatedAtUtc: DateTime.now().toUtc(),
    );
    await _preferences.setString(_key(item), jsonEncode(payload.toJson()));
  }

  Future<void> clear(MediaItem item) => _preferences.remove(_key(item));
}
