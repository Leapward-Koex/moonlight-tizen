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
    this.showHeader = true,
    this.logo,
    this.overlay,
  });

  final String title;
  final Widget body;
  final List<HeaderActionViewModel> actions;
  final VoidCallback? onBack;
  final bool showHeader;
  final Widget? logo;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MoonlightColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              if (showHeader)
                MoonlightHeader(
                  title: title,
                  actions: actions,
                  onBack: onBack,
                  logo: logo,
                ),
              Expanded(child: body),
            ],
          ),
          ?overlay,
        ],
      ),
    );
  }
}

class MoonlightHeader extends StatelessWidget {
  const MoonlightHeader({
    required this.title,
    super.key,
    this.actions = const [],
    this.onBack,
    this.logo,
  });

  final String title;
  final List<HeaderActionViewModel> actions;
  final VoidCallback? onBack;
  final Widget? logo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MoonlightColors.header,
      elevation: 4,
      shadowColor: Colors.black,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: MoonlightMetrics.headerHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gutter = MoonlightMetrics.horizontalGutter(
                constraints.maxWidth,
              );
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: TvFocusTraversalGroup(
                  child: Row(
                    children: [
                      if (onBack != null) ...[
                        TvIconButton(
                          icon: Icons.keyboard_arrow_left,
                          label: 'Back',
                          onPressed: onBack!,
                        ),
                        const SizedBox(width: 28),
                      ],
                      logo ?? const MoonlightLogo(),
                      const SizedBox(width: 30),
                      Expanded(
                        child: Text(
                          title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                      ),
                      for (final action in actions) ...[
                        const SizedBox(width: 20),
                        TvIconButton(
                          key: ValueKey('header-${action.id}'),
                          icon: action.icon,
                          label: action.label,
                          onPressed: action.onPressed,
                          enabled: action.enabled,
                          autofocus: action.autofocus,
                          badge: action.badge,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
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
