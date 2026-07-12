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
                    height: 80,
                    child: Row(
                      children: [
                        const SizedBox(width: 20),
                        TvIconButton(
                          icon: Icons.keyboard_arrow_left,
                          label: 'Settings categories',
                          onPressed: () => onCategorySelected(null),
                          autofocus: true,
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
          final optionsFocusKey = GlobalKey();
          void focusFirstOption() {
            final optionsContext = optionsFocusKey.currentContext;
            if (optionsContext != null) {
              FocusScope.of(optionsContext).nextFocus();
            }
          }

          return TvFocusTraversalGroup(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 330,
                  child: SettingsCategoryList(
                    categories: categories,
                    selectedCategoryId: selected.id,
                    onSelected: (category) => onCategorySelected(category.id),
                    onMoveRight: focusFirstOption,
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: FocusScope(
                    child: Builder(
                      key: optionsFocusKey,
                      builder: (context) =>
                          SettingsOptionsPane(category: selected),
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
}

class SettingsCategoryList extends StatelessWidget {
  const SettingsCategoryList({
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelected,
    super.key,
    this.onMoveRight,
  });

  final List<SettingsCategoryViewModel> categories;
  final String? selectedCategoryId;
  final ValueChanged<SettingsCategoryViewModel> onSelected;
  final VoidCallback? onMoveRight;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const PageStorageKey('settings-categories'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      itemCount: categories.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final category = categories[index];
        return SettingsCategoryTile(
          key: ValueKey('settings-category-${category.id}'),
          category: category,
          selected: category.id == selectedCategoryId,
          // Settings normally opens with a selected category. Request focus
          // for that tile so a remote user can immediately move through the
          // category list or into its controls.
          autofocus:
              category.id == selectedCategoryId ||
              (selectedCategoryId == null && index == 0),
          onPressed: () => onSelected(category),
          onMoveRight: onMoveRight,
        );
      },
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
    this.onMoveRight,
  });

  final SettingsCategoryViewModel category;
  final bool selected;
  final VoidCallback onPressed;
  final bool autofocus;
  final VoidCallback? onMoveRight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: TvFocusable(
        autofocus: autofocus,
        semanticLabel: category.label,
        onActivate: onPressed,
        onDirection: (direction) {
          if (direction == TraversalDirection.right && onMoveRight != null) {
            onMoveRight!();
            return true;
          }
          return false;
        },
        builder: (context, focused) => Card(
          color: selected
              ? MoonlightColors.controlFocused
              : focused
              ? MoonlightColors.control
              : MoonlightColors.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(category.icon, size: 28, color: MoonlightColors.text),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    category.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (selected) const Icon(Icons.chevron_right, size: 28),
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
    return ListView.builder(
      key: PageStorageKey('settings-options-${category.id}'),
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
      itemCount: category.options.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.label,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  _categoryDescription(category.id),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: MoonlightColors.textMuted,
                  ),
                ),
              ],
            ),
          );
        }
        return category.options[index - 1];
      },
    );
  }

  static String _categoryDescription(String id) => switch (id) {
    'basic' => 'Picture quality, frame rate, and common streaming behavior.',
    'video' => 'Codec, HDR, color, and frame pacing.',
    'audio' => 'Speaker layout, buffering, and host audio.',
    'input' =>
      'Connected controllers, button layouts, mouse behavior, keyboard capture, and streaming shortcuts.',
    'advanced' => 'Compatibility, diagnostics, and developer options.',
    'about' => 'Version, system information, and support.',
    _ => 'Moonlight preferences.',
  };
}
