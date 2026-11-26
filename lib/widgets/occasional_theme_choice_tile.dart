import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:raven23/design/app_palette.dart';
import 'package:raven23/design/app_tokens.dart';
import 'package:raven23/provider/app_dependency_provider.dart';
import 'package:raven23/mobile/widgets/page_kit.dart';
import 'package:raven23/mobile/widgets/settings_kit.dart';

import 'app_press_feedback.dart';

/// Uses the same seasonal-theme selector and visual treatment as RAVEN23.
class OccasionalThemeChoiceTile extends StatelessWidget {
  const OccasionalThemeChoiceTile({super.key, required this.provider});

  final AppDependencyProvider provider;

  String get _selectedLabel {
    if (provider.selectedOccasionalThemeId == 'automatic') {
      return tr('automatic');
    }
    for (final theme in provider.availableOccasionalThemes) {
      if (theme.id == provider.selectedOccasionalThemeId) {
        return theme.displayName;
      }
    }
    return tr('automatic');
  }

  @override
  Widget build(BuildContext context) {
    return ListRow(
      onTap: () => _showChoices(context),
      icon: PhosphorIcons.sparkle(),
      label: tr('occasional_theme'),
      subtitle: tr('seasonal_theme_selection_description'),
      value: _selectedLabel,
    );
  }

  Future<void> _showChoices(BuildContext context) {
    return showAppSheet<void>(
      context,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .78,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(sheetContext).bottom + AppSpace.lg,
          ),
          children: [
            SheetTitle(tr('occasional_theme')),
            _OccasionalThemeOption(
              title: tr('automatic'),
              description: tr('automatic_theme_description'),
              colors: const [],
              selected: provider.selectedOccasionalThemeId == 'automatic',
              onTap: () {
                provider.selectOccasionalTheme('automatic');
                Navigator.pop(sheetContext);
              },
            ),
            for (final theme in provider.availableOccasionalThemes)
              _OccasionalThemeOption(
                title: theme.displayName,
                description: theme.description.isEmpty
                    ? tr('active_seasonal_theme')
                    : theme.description,
                colors: [
                  theme.primaryColor,
                  theme.secondaryColor,
                  theme.tertiaryColor,
                ],
                selected: provider.selectedOccasionalThemeId == theme.id,
                onTap: () {
                  provider.selectOccasionalTheme(theme.id);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _OccasionalThemeOption extends StatelessWidget {
  const _OccasionalThemeOption({
    required this.title,
    required this.description,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final gutter = AppSpace.gutter(context);
    final titleColor = selected ? palette.onFocus : palette.foreground;
    final detailColor =
        selected ? palette.onFocus.withValues(alpha: .72) : palette.mutedText;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, AppSpace.sm),
      child: Material(
        color: selected ? palette.focusFill : palette.idleFill,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: AppPressFeedback(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.card),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 34,
                    child: colors.isEmpty
                        ? Icon(
                            PhosphorIcons.magicWand(),
                            color:
                                selected ? palette.onFocus : palette.mutedText,
                          )
                        : Stack(
                            children: [
                              for (var index = 0;
                                  index < colors.length;
                                  index++)
                                Positioned(
                                  left: index * 11.0,
                                  top: index.isOdd ? 7 : 1,
                                  child: Container(
                                    width: 25,
                                    height: 25,
                                    decoration: BoxDecoration(
                                      color: colors[index],
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: selected
                                            ? palette.focusFill
                                            : palette.surface,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppType.cardTitle.copyWith(
                            fontSize: 15,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              AppType.metadata.copyWith(color: detailColor),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(PhosphorIcons.check(), color: palette.onFocus),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
