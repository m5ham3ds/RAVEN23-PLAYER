import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:raven23/provider/app_dependency_provider.dart';
import 'package:raven23/services/ambient_theme_service.dart';

import '../models/media_item.dart';
import 'android_media_library.dart';

/// Applies the original RAVEN23 ambient-color behavior to the artwork of the
/// video currently open in the standalone Player.
class PlayerAmbientThemeController {
  final AndroidMediaLibrary _library = AndroidMediaLibrary();

  AppDependencyProvider? _provider;
  MediaItem? _item;
  int? _scopeId;
  Color? _resolvedColor;
  bool _extracting = false;
  bool _disposed = false;

  void attach(BuildContext context, MediaItem item) {
    if (_provider != null) return;
    _item = item;
    _provider = Provider.of<AppDependencyProvider>(context, listen: false);
    _scopeId = _provider!.pushAmbientScope();
    _provider!.addListener(_onProviderChanged);
    _onProviderChanged();
  }

  void _onProviderChanged() {
    final provider = _provider;
    final scope = _scopeId;
    if (_disposed || provider == null || scope == null) return;

    // The original resolver gives a selected/active seasonal theme priority.
    if (provider.ambientModeEnabled &&
        provider.activeOccasionalTheme == null &&
        _resolvedColor != null) {
      provider.updateAmbientScope(scope, _resolvedColor!);
      return;
    }

    if (!provider.ambientModeEnabled ||
        provider.activeOccasionalTheme != null ||
        _extracting ||
        _resolvedColor != null) {
      return;
    }

    _extracting = true;
    unawaited(_extractColor().then((color) {
      _extracting = false;
      if (_disposed) return;
      _resolvedColor = color;
      if (color != null &&
          provider.ambientModeEnabled &&
          provider.activeOccasionalTheme == null) {
        provider.updateAmbientScope(scope, color);
      }
    }).catchError((Object _) {
      _extracting = false;
    }));
  }

  Future<Color?> _extractColor() async {
    final item = _item;
    if (item == null) return null;

    // Prefer a local thumbnail so Ambient mode also works without a network.
    try {
      final bytes = await _library.videoThumbnail(item.contentUri);
      if (bytes != null && bytes.isNotEmpty) {
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: 64,
          targetHeight: 64,
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            final data = await frame.image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            if (data != null) {
              final color = _fromRgba(
                data.buffer.asUint8List(),
                width: frame.image.width,
                height: frame.image.height,
              );
              if (color != null) return color;
            }
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
    } catch (_) {
      // Missing thumbnails never interrupt local playback.
    }

    final posterUrl = item.posterUrl?.trim() ?? '';
    final uri = Uri.tryParse(posterUrl);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return null;
    }
    try {
      return await DominantImageColor.extract(posterUrl);
    } catch (_) {
      return null;
    }
  }

  static Color? _fromRgba(
    List<int> rgba, {
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      return null;
    }
    final buckets = <int, _AmbientColorBucket>{};
    final xStep = (width / 48).ceil().clamp(1, width).toInt();
    final yStep = (height / 48).ceil().clamp(1, height).toInt();

    for (var y = 0; y < height; y += yStep) {
      for (var x = 0; x < width; x += xStep) {
        final offset = (y * width + x) * 4;
        final alpha = rgba[offset + 3];
        if (alpha < 180) continue;
        final red = rgba[offset];
        final green = rgba[offset + 1];
        final blue = rgba[offset + 2];
        final hsl = HSLColor.fromColor(Color.fromARGB(255, red, green, blue));
        if (hsl.lightness < .08 ||
            hsl.lightness > .92 ||
            hsl.saturation < .12) {
          continue;
        }
        final key = (red >> 5) << 10 | (green >> 5) << 5 | (blue >> 5);
        final bucket = buckets.putIfAbsent(key, _AmbientColorBucket.new);
        final weight = .35 + hsl.saturation * .65;
        bucket
          ..score += weight
          ..red += red
          ..green += green
          ..blue += blue
          ..samples++;
      }
    }
    if (buckets.isEmpty) return null;
    final winner = buckets.values.reduce(
      (a, b) => a.score >= b.score ? a : b,
    );
    final raw = Color.fromARGB(
      255,
      winner.red ~/ winner.samples,
      winner.green ~/ winner.samples,
      winner.blue ~/ winner.samples,
    );
    final hsl = HSLColor.fromColor(raw);
    return hsl
        .withSaturation(hsl.saturation.clamp(.35, .85).toDouble())
        .withLightness(hsl.lightness.clamp(.35, .60).toDouble())
        .toColor();
  }


  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final provider = _provider;
    final scope = _scopeId;
    if (provider != null) {
      provider.removeListener(_onProviderChanged);
      if (scope != null) provider.popAmbientScope(scope);
    }
    _provider = null;
    _item = null;
  }
}


class _AmbientColorBucket {
  double score = 0;
  int red = 0;
  int green = 0;
  int blue = 0;
  int samples = 0;
}
