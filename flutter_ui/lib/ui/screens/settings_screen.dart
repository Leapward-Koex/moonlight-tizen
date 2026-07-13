import 'package:flutter/material.dart';

import '../theme/moonlight_theme.dart';
import '../view_models.dart';
import '../widgets/moonlight_shell.dart';
import '../widgets/tv_focusable.dart';

class SettingsScreen extends StatefulWidget {
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

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  final FocusScopeNode _categoriesFocus = FocusScopeNode(
    debugLabel: 'Settings categories',
  );
  final FocusScopeNode _optionsFocus = FocusScopeNode(
    debugLabel: 'Settings options',
  );
  final GlobalKey _optionsFocusKey = GlobalKey();
  final Map<String, FocusNode> _categoryFocusNodes = {};
  bool _isNarrow = false;

  SettingsCategoryViewModel? get _selectedCategory {
    if (widget.categories.isEmpty) return null;
    for (final category in widget.categories) {
      if (category.id == widget.selectedCategoryId) return category;
    }
    return widget.categories.first;
  }

  FocusNode _focusNodeForCategory(SettingsCategoryViewModel category) =>
      _categoryFocusNodes.putIfAbsent(
        category.id,
        () => FocusNode(debugLabel: category.label),
      );

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final categoryIds = widget.categories
        .map((category) => category.id)
        .toSet();
    final removedIds = _categoryFocusNodes.keys
        .where((id) => !categoryIds.contains(id))
        .toList(growable: false);
    for (final id in removedIds) {
      _categoryFocusNodes.remove(id)?.dispose();
    }
  }

  @override
  void dispose() {
    _categoriesFocus.dispose();
    _optionsFocus.dispose();
    for (final node in _categoryFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Handles the TV Back action without losing the user's place in Settings.
  ///
  /// The options pane is one level deeper than the category pane. Back first
  /// returns focus to the selected category; only another Back exits Settings.
  bool handleBack() {
    if (_isNarrow && widget.selectedCategoryId != null) {
      final selected = _selectedCategory;
      widget.onCategorySelected(null);
      if (selected != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusNodeForCategory(selected).requestFocus();
        });
      }
      return true;
    }
    if (!_isNarrow && _optionsFocus.hasFocus) {
      _focusSelectedCategory();
      return true;
    }
    widget.onBack();
    return true;
  }

  void _focusSelectedCategory() {
    final selected = _selectedCategory;
    if (selected == null) return;
    _focusNodeForCategory(selected).requestFocus();
  }

  void _focusFirstOption() {
    final optionsContext = _optionsFocusKey.currentContext;
    if (optionsContext != null) {
      FocusScope.of(optionsContext).nextFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MoonlightShell(
      title: 'Settings',
      onBack: handleBack,
      actions: widget.headerActions,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (widget.categories.isEmpty) {
            return const Center(child: Text('No settings are available.'));
          }
          final narrow =
              constraints.maxWidth < MoonlightMetrics.narrowBreakpoint;
          _isNarrow = narrow;
          if (narrow) {
            if (widget.selectedCategoryId == null) {
              return FocusScope(
                node: _categoriesFocus,
                child: SettingsCategoryList(
                  categories: widget.categories,
                  selectedCategoryId: null,
                  onSelected: (category) =>
                      widget.onCategorySelected(category.id),
                  focusNodeForCategory: _focusNodeForCategory,
                ),
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
                          onPressed: handleBack,
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
          return TvFocusTraversalGroup(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 330,
                  child: FocusScope(
                    node: _categoriesFocus,
                    child: SettingsCategoryList(
                      categories: widget.categories,
                      selectedCategoryId: selected.id,
                      onSelected: (category) =>
                          widget.onCategorySelected(category.id),
                      onMoveRight: _focusFirstOption,
                      focusNodeForCategory: _focusNodeForCategory,
                    ),
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: FocusScope(
                    node: _optionsFocus,
                    child: Builder(
                      key: _optionsFocusKey,
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
    this.focusNodeForCategory,
  });

  final List<SettingsCategoryViewModel> categories;
  final String? selectedCategoryId;
  final ValueChanged<SettingsCategoryViewModel> onSelected;
  final VoidCallback? onMoveRight;
  final FocusNode Function(SettingsCategoryViewModel category)?
  focusNodeForCategory;

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
          focusNode: focusNodeForCategory?.call(category),
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
    this.focusNode,
  });

  final SettingsCategoryViewModel category;
  final bool selected;
  final VoidCallback onPressed;
  final bool autofocus;
  final VoidCallback? onMoveRight;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: TvFocusable(
        focusNode: focusNode,
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
      // Leave enough trailing scroll extent for the focused final option to
      // sit fully above the floating snackbar used throughout Settings.
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 152),
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
