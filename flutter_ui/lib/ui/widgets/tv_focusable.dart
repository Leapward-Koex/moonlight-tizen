import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  static final Map<FocusNode, VoidCallback> _activationCallbacks = {};
  static final Map<FocusNode, bool Function(TraversalDirection direction)>
  _directionCallbacks = {};

  /// Invokes the control currently represented by [node]. This is used by
  /// normalized gamepad input, which does not arrive as a browser key event.
  static bool activate(FocusNode? node) {
    final callback = node == null ? null : _activationCallbacks[node];
    if (callback == null) return false;
    callback();
    return true;
  }

  /// Moves focus for normalized gamepad input while preserving any
  /// control-specific directional behavior used by keyboard/remote input.
  static bool move(FocusNode? node, TraversalDirection direction) {
    if (node == null) return false;
    if (_directionCallbacks[node]?.call(direction) ?? false) return true;
    return node.focusInDirection(direction);
  }

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  static const _focusScrollDuration = Duration(milliseconds: 220);
  static const _focusScrollAlignment = 0.5;
  static const _focusScrollTolerance = 1.0;

  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  _TvVerticalFocusTraversalState? _verticalTraversal;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _setFocusNode(widget.focusNode);
    _syncActivationCallback();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final verticalTraversal = TvVerticalFocusTraversal._maybeOf(context);
    if (_verticalTraversal != verticalTraversal) {
      _verticalTraversal?.unregister(_focusNode);
      _verticalTraversal = verticalTraversal;
      _verticalTraversal?.register(_focusNode);
    }
    _syncDirectionCallback();
  }

  @override
  void didUpdateWidget(TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _verticalTraversal?.unregister(_focusNode);
      _removeActivationCallback();
      _removeDirectionCallback();
      if (_ownsFocusNode) _focusNode.dispose();
      _setFocusNode(widget.focusNode);
      _verticalTraversal?.register(_focusNode);
    }
    _syncActivationCallback();
  }

  void _setFocusNode(FocusNode? node) {
    _ownsFocusNode = node == null;
    _focusNode = node ?? FocusNode(debugLabel: widget.semanticLabel);
  }

  void _syncActivationCallback() {
    if (widget.enabled && widget.onActivate != null) {
      TvFocusable._activationCallbacks[_focusNode] = widget.onActivate!;
    } else {
      _removeActivationCallback();
    }
    _syncDirectionCallback();
  }

  void _syncDirectionCallback() {
    if (widget.enabled) {
      TvFocusable._directionCallbacks[_focusNode] = _moveFocus;
    } else {
      _removeDirectionCallback();
    }
  }

  void _removeActivationCallback() {
    TvFocusable._activationCallbacks.remove(_focusNode);
  }

  void _removeDirectionCallback() {
    TvFocusable._directionCallbacks.remove(_focusNode);
  }

  @override
  void dispose() {
    _verticalTraversal?.unregister(_focusNode);
    _removeActivationCallback();
    _removeDirectionCallback();
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
      _moveFocus(direction);
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

  bool _moveFocus(TraversalDirection direction) {
    if (widget.onDirection?.call(direction) ?? false) return true;
    if (TvVerticalFocusTraversal.maybeHandle(
      context,
      _focusNode,
      direction,
    )) {
      return true;
    }
    return _focusNode.focusInDirection(direction);
  }

  void _ensureComfortablyVisible() {
    final object = context.findRenderObject();
    final scrollable = Scrollable.maybeOf(context);
    if (object == null || scrollable == null) return;

    final viewport = RenderAbstractViewport.maybeOf(object);
    if (viewport == null) return;

    final position = scrollable.position;
    final leadingOffset = viewport
        .getOffsetToReveal(object, 0, axis: position.axis)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    final trailingOffset = viewport
        .getOffsetToReveal(object, 1, axis: position.axis)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    final centeredOffset = viewport
        .getOffsetToReveal(
          object,
          _focusScrollAlignment,
          axis: position.axis,
        )
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    final visibleFrom = leadingOffset < trailingOffset
        ? leadingOffset
        : trailingOffset;
    final visibleThrough = leadingOffset > trailingOffset
        ? leadingOffset
        : trailingOffset;

    final fullyVisible =
        position.pixels >= visibleFrom && position.pixels <= visibleThrough;

    // A TV user needs context in the direction they are travelling. Move a
    // fully visible control toward the center whether it was reached with Up
    // or Down. Clamping keeps the first and final controls naturally aligned
    // when the list has no more scroll extent in that direction.
    if (fullyVisible &&
        (centeredOffset - position.pixels).abs() <=
            _focusScrollTolerance) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      duration: _focusScrollDuration,
      curve: Curves.easeOutCubic,
      alignment: _focusScrollAlignment,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
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
              _ensureComfortablyVisible();
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
                  borderRadius: widget.borderRadius,
                  border: Border.all(
                    color: focused ? widget.focusColor : Colors.transparent,
                    width: MoonlightMetrics.focusStroke,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: widget.focusColor.withValues(alpha: .28),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                padding: const EdgeInsets.all(MoonlightMetrics.focusStroke),
                child: ClipRRect(
                  borderRadius: widget.borderRadius,
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

/// Makes Up and Down follow reading order within a TV list.
///
/// Directional focus normally chooses the geometrically nearest control. That
/// works well for grids, but mixed-width settings cards can make focus jump
/// backward. Controls may still consume Left and Right themselves; otherwise
/// an optional Left callback lets a containing pane expose its parent level.
class TvVerticalFocusTraversal extends StatefulWidget {
  const TvVerticalFocusTraversal({
    required this.child,
    super.key,
    this.onExitLeft,
  });

  final Widget child;
  final VoidCallback? onExitLeft;

  static _TvVerticalFocusTraversalState? _maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_TvVerticalFocusTraversalScope>()
          ?.state;

  static bool maybeHandle(
    BuildContext context,
    FocusNode node,
    TraversalDirection direction,
  ) {
    return _maybeOf(context)?.move(node, direction) ?? false;
  }

  @override
  State<TvVerticalFocusTraversal> createState() =>
      _TvVerticalFocusTraversalState();
}

class _TvVerticalFocusTraversalState
    extends State<TvVerticalFocusTraversal> {
  final Set<FocusNode> _nodes = {};
  final ReadingOrderTraversalPolicy _policy = ReadingOrderTraversalPolicy();

  void register(FocusNode node) => _nodes.add(node);

  void unregister(FocusNode node) => _nodes.remove(node);

  bool move(FocusNode currentNode, TraversalDirection direction) {
    if (direction == TraversalDirection.left && widget.onExitLeft != null) {
      widget.onExitLeft!();
      return true;
    }
    final delta = switch (direction) {
      TraversalDirection.up => -1,
      TraversalDirection.down => 1,
      TraversalDirection.left || TraversalDirection.right => 0,
    };
    if (delta == 0) return false;

    final ordered = _policy
        .sortDescendants(
          _nodes.where(
            (node) =>
                node.context != null &&
                node.canRequestFocus &&
                !node.skipTraversal,
          ),
          currentNode,
        )
        .toList(growable: false);
    final currentIndex = ordered.indexOf(currentNode);
    final nextIndex = currentIndex + delta;
    if (currentIndex < 0 || nextIndex < 0 || nextIndex >= ordered.length) {
      return false;
    }
    ordered[nextIndex].requestFocus();
    return true;
  }

  @override
  Widget build(BuildContext context) => _TvVerticalFocusTraversalScope(
    state: this,
    child: widget.child,
  );
}

class _TvVerticalFocusTraversalScope extends InheritedWidget {
  const _TvVerticalFocusTraversalScope({
    required this.state,
    required super.child,
  });

  final _TvVerticalFocusTraversalState state;

  @override
  bool updateShouldNotify(_TvVerticalFocusTraversalScope oldWidget) => false;
}

class TvIconButton extends StatelessWidget {
  const TvIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.onDirection,
    this.badge,
    this.size = MoonlightMetrics.minHitTarget,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool Function(TraversalDirection direction)? onDirection;
  final String? badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      preferBelow: true,
      textStyle: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: BoxDecoration(
        color: MoonlightColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox.square(
        dimension: size,
        child: TvFocusable(
          focusNode: focusNode,
          autofocus: autofocus,
          enabled: enabled,
          semanticLabel: label,
          onDirection: onDirection,
          borderRadius: BorderRadius.circular(size / 2),
          onActivate: onPressed,
          builder: (context, focused) => Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              ExcludeFocus(
                child: IgnorePointer(
                  child: IconButton(
                    onPressed: enabled ? onPressed : null,
                    icon: Icon(icon, size: 30),
                    style: IconButton.styleFrom(
                      minimumSize: Size.square(size),
                      foregroundColor: MoonlightColors.text,
                      backgroundColor: focused
                          ? MoonlightColors.cyan.withValues(alpha: .16)
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
              if (badge != null)
                Positioned(top: 0, right: 0, child: Badge(label: Text(badge!))),
            ],
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
    this.height = MoonlightMetrics.minHitTarget,
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
        builder: (context, focused) => ExcludeFocus(
          child: IgnorePointer(
            child: FilledButton.tonalIcon(
              onPressed: enabled ? onPressed : null,
              style: FilledButton.styleFrom(
                minimumSize: Size(double.infinity, height),
                backgroundColor: destructive
                    ? MoonlightColors.offline.withValues(alpha: .18)
                    : null,
                foregroundColor: destructive ? const Color(0xFFFFB4AB) : null,
              ),
              icon: icon == null ? const SizedBox.shrink() : Icon(icon),
              label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
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
