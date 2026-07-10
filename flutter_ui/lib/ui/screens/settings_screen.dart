import 'package:flutter/material.dart';

import '../theme/moonlight_theme.dart';
import '../view_models.dart';
import '../widgets/moonlight_shell.dart';
import '../widgets/tv_focusable.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.categories,
    required this.selectedCategoryId,
    required this.onCategorySelected,
    required this.onBack,
    super.key,
    this.headerActions = const [],
  });

  final List<SettingsCategoryViewModel> categories;
  final String? selectedCategoryId;
  final ValueChanged<String?> onCategorySelected;
  final VoidCallback onBack;
  final List<HeaderActionViewModel> headerActions;

  SettingsCategoryViewModel? get _selectedCategory {
    if (categories.isEmpty) return null;
    for (final category in categories) {
      if (category.id == selectedCategoryId) return category;
    }
    return categories.first;
  }

  @override
  Widget build(BuildContext context) {
    return MoonlightShell(
      title: 'Settings',
      onBack: onBack,
      actions: headerActions,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (categories.isEmpty) {
            return const Center(child: Text('No settings are available.'));
          }
          final narrow =
              constraints.maxWidth < MoonlightMetrics.narrowBreakpoint;
          if (narrow) {
            if (selectedCategoryId == null) {
              return SettingsCategoryList(
                categories: categories,
                selectedCategoryId: null,
                onSelected: (category) => onCategorySelected(category.id),
              );
            }
            final selected = _selectedCategory!;
            return Column(
              children: [
                Material(
                  color: MoonlightColors.header.withValues(alpha: .55),
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        const SizedBox(width: 20),
                        TvIconButton(
                          icon: Icons.keyboard_arrow_left,
                          label: 'Settings categories',
                          onPressed: () => onCategorySelected(null),
                          autofocus: true,
                          size: 46,
                        ),
                        const SizedBox(width: 18),
                        Icon(selected.icon, color: MoonlightColors.textMuted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            selected.label,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(child: SettingsOptionsPane(category: selected)),
              ],
            );
          }

          final selected = _selectedCategory!;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: constraints.maxWidth * .3,
                child: SettingsCategoryList(
                  categories: categories,
                  selectedCategoryId: selected.id,
                  onSelected: (category) => onCategorySelected(category.id),
                ),
              ),
              const VerticalDivider(width: 4, thickness: 4),
              Expanded(child: SettingsOptionsPane(category: selected)),
            ],
          );
        },
      ),
    );
  }
}

class SettingsCategoryList extends StatelessWidget {
  const SettingsCategoryList({
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelected,
    super.key,
  });

  final List<SettingsCategoryViewModel> categories;
  final String? selectedCategoryId;
  final ValueChanged<SettingsCategoryViewModel> onSelected;

  @override
  Widget build(BuildContext context) {
    return TvFocusTraversalGroup(
      child: ListView.separated(
        key: const PageStorageKey('settings-categories'),
        padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 28),
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final category = categories[index];
          return SettingsCategoryTile(
            key: ValueKey('settings-category-${category.id}'),
            category: category,
            selected: category.id == selectedCategoryId,
            autofocus: selectedCategoryId == null ? index == 0 : false,
            onPressed: () => onSelected(category),
          );
        },
      ),
    );
  }
}

class SettingsCategoryTile extends StatelessWidget {
  const SettingsCategoryTile({
    required this.category,
    required this.selected,
    required this.onPressed,
    super.key,
    this.autofocus = false,
  });

  final SettingsCategoryViewModel category;
  final bool selected;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: TvFocusable(
        autofocus: autofocus,
        semanticLabel: category.label,
        onActivate: onPressed,
        builder: (context, focused) => DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? MoonlightColors.cyan.withValues(alpha: .8)
                : focused
                ? MoonlightColors.controlFocused
                : Colors.transparent,
            border: const Border(
              bottom: BorderSide(color: Color(0xFF666666), width: 2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Icon(category.icon, size: 32, color: MoonlightColors.textMuted),
                const SizedBox(width: 28),
                Expanded(
                  child: Text(
                    category.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (selected) const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsOptionsPane extends StatelessWidget {
  const SettingsOptionsPane({required this.category, super.key});

  final SettingsCategoryViewModel category;

  @override
  Widget build(BuildContext context) {
    if (category.options.isEmpty) {
      return const Center(child: Text('No options in this category.'));
    }
    return TvFocusTraversalGroup(
      child: ListView.builder(
        key: PageStorageKey('settings-options-${category.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 12),
        itemCount: category.options.length,
        itemBuilder: (context, index) => category.options[index],
      ),
    );
  }
}
