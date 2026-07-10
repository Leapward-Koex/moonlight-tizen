import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/moonlight_theme.dart';

typedef TvFocusBuilder = Widget Function(BuildContext context, bool focused);

/// A focus primitive that maps TV remote/keyboard arrows and select keys to
/// Flutter focus traversal and activation.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    required this.builder,
    required this.onActivate,
    super.key,
    this.onSecondaryActivate,
    this.onDirection,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.semanticLabel,
    this.scaleOnFocus = 1,
    this.focusColor = MoonlightColors.cyan,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(MoonlightMetrics.controlRadius),
    ),
  });

  final TvFocusBuilder builder;
  final VoidCallback? onActivate;
  final VoidCallback? onSecondaryActivate;
  final bool Function(TraversalDirection direction)? onDirection;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final String? semanticLabel;
  final double scaleOnFocus;
  final Color focusColor;
  final BorderRadius borderRadius;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _setFocusNode(widget.focusNode);
  }

  @override
  void didUpdateWidget(TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _setFocusNode(widget.focusNode);
    }
  }

  void _setFocusNode(FocusNode? node) {
    _ownsFocusNode = node == null;
    _focusNode = node ?? FocusNode(debugLabel: widget.semanticLabel);
  }

  @override
  void dispose() {
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final direction = switch (key) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      _ => null,
    };
    if (direction != null) {
      if (widget.onDirection?.call(direction) ?? false) {
        return KeyEventResult.handled;
      }
      node.focusInDirection(direction);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.numpadEnter) {
      widget.onActivate?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.keyM) {
      widget.onSecondaryActivate?.call();
      return widget.onSecondaryActivate == null
          ? KeyEventResult.ignored
          : KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focused && widget.enabled;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      focusable: widget.enabled,
      focused: focused,
      label: widget.semanticLabel,
      onTap: widget.enabled ? widget.onActivate : null,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) {
          if (widget.enabled) _focusNode.requestFocus();
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          canRequestFocus: widget.enabled,
          skipTraversal: !widget.enabled,
          onFocusChange: (value) {
            if (_focused != value) setState(() => _focused = value);
            if (value) {
              Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
              );
            }
          },
          onKeyEvent: _handleKeyEvent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled ? widget.onActivate : null,
            onSecondaryTap: widget.enabled ? widget.onSecondaryActivate : null,
            child: AnimatedScale(
              scale: focused ? widget.scaleOnFocus : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: focused
                      ? BorderRadius.zero
                      : widget.borderRadius,
                  border: focused
                      ? Border.all(color: widget.focusColor, width: 3)
                      : null,
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: widget.focusColor.withValues(alpha: .42),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: focused
                      ? BorderRadius.zero
                      : widget.borderRadius,
                  child: widget.builder(context, focused),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TvIconButton extends StatelessWidget {
  const TvIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
    this.enabled = true,
    this.autofocus = false,
    this.badge,
    this.size = 50,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool autofocus;
  final String? badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      preferBelow: true,
      textStyle: const TextStyle(color: Colors.white, fontSize: 18),
      decoration: BoxDecoration(
        color: MoonlightColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox.square(
        dimension: size,
        child: TvFocusable(
          autofocus: autofocus,
          enabled: enabled,
          semanticLabel: label,
          onActivate: onPressed,
          builder: (context, focused) => ColoredBox(
            color: enabled
                ? MoonlightColors.control
                : MoonlightColors.control.withValues(alpha: .45),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 32, color: MoonlightColors.text),
                if (badge != null)
                  Positioned(
                    top: -5,
                    right: -5,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 23),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: const BoxDecoration(
                        color: MoonlightColors.warning,
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      child: Text(
                        badge!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
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

class TvActionButton extends StatelessWidget {
  const TvActionButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.enabled = true,
    this.autofocus = false,
    this.destructive = false,
    this.height = 54,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool enabled;
  final bool autofocus;
  final bool destructive;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: TvFocusable(
        autofocus: autofocus,
        enabled: enabled,
        semanticLabel: label,
        focusColor: destructive
            ? MoonlightColors.offline
            : MoonlightColors.cyan,
        onActivate: onPressed,
        builder: (context, focused) => ColoredBox(
          color: enabled
              ? MoonlightColors.control
              : MoonlightColors.control.withValues(alpha: .48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 27),
                  const SizedBox(width: 12),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
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

/// Wrap a screen's controls in this group for predictable row-major movement.
class TvFocusTraversalGroup extends StatelessWidget {
  const TvFocusTraversalGroup({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: child,
    );
  }
}
