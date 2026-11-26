import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:raven23/constants/app_constants.dart' show sharedPrefsSingleton;
import 'package:raven23/design/app_palette.dart';
import 'package:raven23/design/app_tokens.dart';
import 'package:raven23/mobile/widgets/page_kit.dart';
import 'package:raven23/mobile/widgets/settings_kit.dart';
import 'package:raven23/provider/settings_provider.dart';

import '../utils/player_language.dart';

class AppLanguageChooseScreen extends StatelessWidget {
  const AppLanguageChooseScreen({super.key});

  static const _languages = <_AppLanguageOption>[
    _AppLanguageOption(PlayerLanguage.system, null),
    _AppLanguageOption('en', 'united-kingdom'),
    _AppLanguageOption('ar', 'united-arab-emirates'),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final palette = AppPalette.of(context);
    final gutter = AppSpace.gutter(context);
    return Scaffold(
      backgroundColor: palette.page,
      appBar: PageAppBar(title: tr('choose_language')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              gutter,
              AppSpace.sm,
              gutter,
              AppSpace.xxxl + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              SettingsGroup(
                title: tr('app_language'),
                children: [
                  for (final language in _languages)
                    SelectableRow(
                      label: language.code == PlayerLanguage.system
                          ? tr('player_system_language')
                          : tr(language.code == 'ar' ? 'arabic' : 'english'),
                      leading: language.flag == null
                          ? Icon(
                              Icons.phone_android_rounded,
                              color: palette.mutedText,
                              size: 20,
                            )
                          : ClipOval(
                              child: Image.asset(
                                'packages/raven23/assets/images/country_flags/${language.flag}.png',
                                width: 24,
                                height: 24,
                                fit: BoxFit.cover,
                              ),
                            ),
                      selected: settings.appLanguage == language.code,
                      onTap: () async {
                        settings.appLanguage = language.code;
                        await sharedPrefsSingleton.setString(
                          PlayerLanguage.preferenceKey,
                          language.code,
                        );
                        EasyLocalization.of(context)!.setLocale(
                          PlayerLanguage.resolve(language.code),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppLanguageOption {
  const _AppLanguageOption(this.code, this.flag);
  final String code;
  final String? flag;
}
