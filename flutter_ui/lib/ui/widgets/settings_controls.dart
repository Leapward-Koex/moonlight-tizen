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
    this.fullWidthControl = false,
  });

  final String title;
  final String? description;
  final String? badge;
  final Widget control;
  final bool visible;
  final bool fullWidthControl;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 104),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 680;
                final details = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (badge != null) SettingBadge(label: badge!),
                      ],
                    ),
                    if (description != null && description!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        description!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                );
                if (narrow || fullWidthControl) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [details, const SizedBox(height: 16), control],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: details),
                    const SizedBox(width: 32),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: control,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: MoonlightColors.control,
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 14,
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
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 96,
        height: MoonlightMetrics.minHitTarget,
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
          builder: (context, focused) => Center(
            child: IgnorePointer(
              child: Switch(value: value, onChanged: enabled ? (_) {} : null),
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

  bool _step(int delta) {
    final enabledChoices = choices.where((choice) => choice.enabled).toList();
    if (enabledChoices.isEmpty) return false;
    var index = enabledChoices.indexWhere((choice) => choice.value == value);
    if (index < 0) index = 0;
    final next = (index + delta).clamp(0, enabledChoices.length - 1);
    if (next == index) return false;
    onChanged(enabledChoices[next].value);
    return true;
  }

  Future<void> _showChoices(BuildContext context) async {
    final selected = await showDialog<T>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose an option'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
          child: TvFocusTraversalGroup(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: choices.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final choice = choices[index];
                final selected = choice.value == value;
                return TvFocusable(
                  autofocus: selected || index == 0,
                  enabled: choice.enabled,
                  semanticLabel: choice.label,
                  onActivate: () => Navigator.of(context).pop(choice.value),
                  builder: (context, focused) => ListTile(
                    selected: selected || focused,
                    selectedTileColor: MoonlightColors.controlFocused,
                    minTileHeight: 72,
                    title: Text(choice.label),
                    trailing: selected ? const Icon(Icons.check) : null,
                  ),
                );
              },
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
      width: 320,
      height: MoonlightMetrics.minHitTarget,
      child: TvFocusable(
        autofocus: autofocus,
        enabled: enabled && choices.any((choice) => choice.enabled),
        semanticLabel: semanticLabel == null ? label : '$semanticLabel, $label',
        onActivate: () => _showChoices(context),
        onDirection: (direction) {
          if (direction == TraversalDirection.left) return _step(-1);
          if (direction == TraversalDirection.right) return _step(1);
          return false;
        },
        builder: (context, focused) => ExcludeFocus(
          child: IgnorePointer(
            child: TextButton(
              onPressed: enabled ? () => _showChoices(context) : null,
              style: TextButton.styleFrom(
                foregroundColor: MoonlightColors.cyan,
                alignment: Alignment.centerRight,
              ),
              child: Row(
                children: [
                  Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 12),
                  const Icon(Icons.chevron_right, size: 28),
                ],
              ),
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

  bool _change(double next) {
    final clamped = next.clamp(min, max);
    if (clamped == value) return false;
    onChanged(clamped);
    return true;
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
            return _change(value - step);
          }
          if (direction == TraversalDirection.right) {
            return _change(value + step);
          }
          return false;
        },
        builder: (context, focused) => Row(
          children: [
            Expanded(
              child: ExcludeFocus(
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: step > 0 ? ((max - min) / step).round() : null,
                  label: label,
                  onChanged: enabled ? _change : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 128,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in entries)
          ListTile(
            dense: false,
            contentPadding: EdgeInsets.zero,
            title: Text(entry.label),
            subtitle: SelectableText(entry.value),
          ),
      ],
    );
  }
}
