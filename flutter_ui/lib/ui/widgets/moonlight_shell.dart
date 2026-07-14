import 'package:flutter/material.dart';

import '../theme/moonlight_theme.dart';
import '../view_models.dart';
import 'tv_focusable.dart';

class MoonlightShell extends StatelessWidget {
  const MoonlightShell({
    required this.title,
    required this.body,
    super.key,
    this.actions = const [],
    this.onBack,
    this.backFocusNode,
    this.onBackMoveRight,
    this.showHeader = true,
    this.logo,
    this.overlay,
  });

  final String title;
  final Widget body;
  final List<HeaderActionViewModel> actions;
  final VoidCallback? onBack;
  final FocusNode? backFocusNode;
  final VoidCallback? onBackMoveRight;
  final bool showHeader;
  final Widget? logo;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MoonlightColors.background,
      appBar: showHeader
          ? PreferredSize(
              preferredSize: const Size.fromHeight(
                MoonlightMetrics.headerHeight,
              ),
              child: MoonlightHeader(
                title: title,
                actions: actions,
                onBack: onBack,
                backFocusNode: backFocusNode,
                onBackMoveRight: onBackMoveRight,
                logo: logo,
              ),
            )
          : null,
      body: Stack(fit: StackFit.expand, children: [body, ?overlay]),
    );
  }
}

class MoonlightHeader extends StatelessWidget {
  const MoonlightHeader({
    required this.title,
    super.key,
    this.actions = const [],
    this.onBack,
    this.backFocusNode,
    this.onBackMoveRight,
    this.logo,
  });

  final String title;
  final List<HeaderActionViewModel> actions;
  final VoidCallback? onBack;
  final FocusNode? backFocusNode;
  final VoidCallback? onBackMoveRight;
  final Widget? logo;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      leadingWidth: onBack == null ? 0 : 80,
      leading: onBack == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TvIconButton(
                icon: Icons.arrow_back,
                label: 'Back',
                onPressed: onBack!,
                focusNode: backFocusNode,
                onDirection: (direction) {
                  if (direction == TraversalDirection.right &&
                      onBackMoveRight != null) {
                    onBackMoveRight!();
                    return true;
                  }
                  return false;
                },
              ),
            ),
      titleSpacing: onBack == null ? 24 : 8,
      title: Row(
        children: [
          if (logo != null) ...[logo!, const SizedBox(width: 16)],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.displaySmall,
            ),
          ),
        ],
      ),
      actions: [
        TvFocusTraversalGroup(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final action in actions)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TvIconButton(
                    key: ValueKey('header-${action.id}'),
                    icon: action.icon,
                    label: action.label,
                    onPressed: action.onPressed,
                    enabled: action.enabled,
                    autofocus: action.autofocus,
                    badge: action.badge,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }
}

class MoonlightLogo extends StatelessWidget {
  const MoonlightLogo({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF65D5F1), MoonlightColors.cyan],
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Icon(
        Icons.nights_stay_rounded,
        size: size * .62,
        color: Colors.white,
      ),
    );
  }
}
