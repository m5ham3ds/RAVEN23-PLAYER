import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:raven23/design/app_palette.dart';
import 'package:raven23/design/app_tokens.dart';
import 'package:raven23/mobile/widgets/page_kit.dart';
import 'package:raven23/mobile/widgets/settings_kit.dart';
import 'package:raven23/provider/settings_provider.dart';

class AppLanguageChooseScreen extends StatelessWidget {
  const AppLanguageChooseScreen({super.key});

  static const _languages = <_AppLanguageOption>[
    _AppLanguageOption('en', 'english', 'united-kingdom'),
    _AppLanguageOption('ar', 'arabic', 'united-arab-emirates'),
    _AppLanguageOption('es', 'spanish', 'spain'),
    _AppLanguageOption('hi', 'hindi', 'india'),
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
                      label: tr(language.translationKey),
                      leading: ClipOval(
                        child: Image.asset(
                          'packages/raven23/assets/images/country_flags/${language.flag}.png',
                          width: 30,
                          height: 30,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => DecoratedBox(
                            decoration: BoxDecoration(
                              color: palette.idleFill,
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox.square(
                              dimension: 30,
                              child: Icon(Icons.language, size: 18),
                            ),
                          ),
                        ),
                      ),
                      selected: settings.appLanguage == language.code,
                      onTap: () {
                        settings.appLanguage = language.code;
                        EasyLocalization.of(context)!
                            .setLocale(Locale(language.code));
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
  const _AppLanguageOption(this.code, this.translationKey, this.flag);
  final String code;
  final String translationKey;
  final String flag;
}
