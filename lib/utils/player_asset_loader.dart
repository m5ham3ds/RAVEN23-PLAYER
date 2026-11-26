import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';

/// Loads the full RAVEN23 package catalogue and overlays Player-owned strings.
class PlayerAssetLoader extends AssetLoader {
  const PlayerAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    const loader = RootBundleAssetLoader();
    final packageTranslations = await loader.load(
      'packages/raven23/assets/translations',
      locale,
    );
    final playerTranslations = await loader.load(path, locale);
    return mergeTranslations(
      packageTranslations ?? const <String, dynamic>{},
      playerTranslations ?? const <String, dynamic>{},
    );
  }

  static Map<String, dynamic> mergeTranslations(
    Map<String, dynamic> base,
    Map<String, dynamic> overrides,
  ) {
    final merged = <String, dynamic>{...base};
    for (final entry in overrides.entries) {
      final current = merged[entry.key];
      final value = entry.value;
      if (current is Map && value is Map) {
        merged[entry.key] = mergeTranslations(
          Map<String, dynamic>.from(current),
          Map<String, dynamic>.from(value),
        );
      } else {
        merged[entry.key] = value;
      }
    }
    return merged;
  }
}
