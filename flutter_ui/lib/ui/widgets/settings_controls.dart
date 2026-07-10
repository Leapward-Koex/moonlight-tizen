import 'package:flutter/material.dart';

import '../theme/moonlight_theme.dart';
import '../view_models.dart';
import 'tv_focusable.dart';

class MoonlightSettingOption extends StatelessWidget {
  const MoonlightSettingOption({
    required this.title,
    required this.control,
    super.key,
    this.description,
    this.badge,
    this.visible = true,
  });

  final String title;
  final String? description;
  final String? badge;
  final Widget control;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 24, 25, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (badge != null) SettingBadge(label: badge!),
            ],
          ),
          if (description != null && description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(description!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          control,
        ],
      ),
    );
  }
}

class SettingBadge extends StatelessWidget {
  const SettingBadge({
    required this.label,
    super.key,
    this.kind = BadgeKind.info,
  });

  final String label;
  final BadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final color = switch (kind) {
      BadgeKind.info => MoonlightColors.running,
      BadgeKind.preview => const Color(0xFFB388FF),
      BadgeKind.experimental => const Color(0xFFFFA620),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: MoonlightColors.control,
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

enum BadgeKind { info, preview, experimental }

class TvToggleControl extends StatelessWidget {
  const TvToggleControl({
    required this.value,
    required this.label,
    required this.onChanged,
    super.key,
    this.enabled = true,
    this.autofocus = false,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: TvFocusable(
        autofocus: autofocus,
        enabled: enabled,
        semanticLabel: '$label, ${value ? 'on' : 'off'}',
        onActivate: () => onChanged(!value),
        onDirection: (direction) {
          if (direction == TraversalDirection.left && value) {
            onChanged(false);
            return true;
          }
          if (direction == TraversalDirection.right && !value) {
            onChanged(true);
            return true;
          }
          return false;
        },
        builder: (context, focused) => ColoredBox(
          color: enabled
              ? MoonlightColors.control
              : MoonlightColors.control.withValues(alpha: .45),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 18),
                IgnorePointer(
                  child: Switch(
                    value: value,
                    onChanged: enabled ? (_) {} : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TvChoiceControl<T> extends StatelessWidget {
  const TvChoiceControl({
    required this.value,
    required this.choices,
    required this.onChanged,
    super.key,
    this.enabled = true,
    this.autofocus = false,
    this.semanticLabel,
  });

  final T value;
  final List<ChoiceItem<T>> choices;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final bool autofocus;
  final String? semanticLabel;

  ChoiceItem<T>? get _selected {
    for (final choice in choices) {
      if (choice.value == value) return choice;
    }
    return null;
  }

  void _step(int delta) {
    final enabledChoices = choices.where((choice) => choice.enabled).toList();
    if (enabledChoices.isEmpty) return;
    var index = enabledChoices.indexWhere((choice) => choice.value == value);
    if (index < 0) index = 0;
    final next = (index + delta).clamp(0, enabledChoices.length - 1);
    if (next != index) onChanged(enabledChoices[next].value);
  }

  Future<void> _showChoices(BuildContext context) async {
    final selected = await showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: TvFocusTraversalGroup(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: choices.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final choice = choices[index];
                  final selected = choice.value == value;
                  return SizedBox(
                    height: 58,
                    child: TvFocusable(
                      autofocus: selected || index == 0,
                      enabled: choice.enabled,
                      semanticLabel: choice.label,
                      onActivate: () => Navigator.of(context).pop(choice.value),
                      builder: (context, focused) => ColoredBox(
                        color: selected
                            ? MoonlightColors.cyan.withValues(alpha: .7)
                            : MoonlightColors.control,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  choice.label,
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ),
                              if (selected) const Icon(Icons.check),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final label = _selected?.label ?? value.toString();
    return SizedBox(
      height: 60,
      child: TvFocusable(
        autofocus: autofocus,
        enabled: enabled && choices.any((choice) => choice.enabled),
        semanticLabel: semanticLabel == null ? label : '$semanticLabel, $label',
        onActivate: () => _showChoices(context),
        onDirection: (direction) {
          if (direction == TraversalDirection.left) {
            _step(-1);
            return true;
          }
          if (direction == TraversalDirection.right) {
            _step(1);
            return true;
          }
          return false;
        },
        builder: (context, focused) => ColoredBox(
          color: enabled
              ? MoonlightColors.control
              : MoonlightColors.control.withValues(alpha: .45),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TvSliderControl extends StatelessWidget {
  const TvSliderControl({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    super.key,
    this.step = 1,
    this.enabled = true,
    this.valueLabel,
    this.semanticLabel,
  });

  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final String Function(double value)? valueLabel;
  final String? semanticLabel;

  void _change(double next) {
    onChanged(next.clamp(min, max));
  }

  @override
  Widget build(BuildContext context) {
    final label = valueLabel?.call(value) ?? value.toStringAsFixed(0);
    return SizedBox(
      height: 72,
      child: TvFocusable(
        enabled: enabled,
        semanticLabel: semanticLabel == null ? label : '$semanticLabel, $label',
        onActivate: () {},
        onDirection: (direction) {
          if (direction == TraversalDirection.left) {
            _change(value - step);
            return true;
          }
          if (direction == TraversalDirection.right) {
            _change(value + step);
            return true;
          }
          return false;
        },
        builder: (context, focused) => ColoredBox(
          color: enabled
              ? MoonlightColors.control
              : MoonlightColors.control.withValues(alpha: .45),
          child: Row(
            children: [
              const SizedBox(width: 18),
              Text(min.toStringAsFixed(0)),
              Expanded(
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: step > 0 ? ((max - min) / step).round() : null,
                  label: label,
                  onChanged: enabled ? _change : null,
                ),
              ),
              Text(max.toStringAsFixed(0)),
              const SizedBox(width: 18),
              Container(
                constraints: const BoxConstraints(minWidth: 100),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingInfoPanel extends StatelessWidget {
  const SettingInfoPanel({required this.entries, super.key});

  final List<SystemInfoEntry> entries;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MoonlightColors.control,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 220,
                      child: Text(
                        entry.label,
                        style: const TextStyle(
                          color: MoonlightColors.textMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        entry.value,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
