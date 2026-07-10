import 'package:flutter/material.dart';

import '../theme/moonlight_theme.dart';
import '../view_models.dart';
import '../widgets/moonlight_shell.dart';
import '../widgets/tv_focusable.dart';

class HostsScreen extends StatelessWidget {
  const HostsScreen({
    required this.hosts,
    required this.onHostSelected,
    required this.onAddHost,
    super.key,
    this.onHostMenu,
    this.headerActions = const [],
    this.loading = false,
    this.autofocusFirst = true,
  });

  final List<HostTileViewModel> hosts;
  final ValueChanged<HostTileViewModel> onHostSelected;
  final VoidCallback onAddHost;
  final ValueChanged<HostTileViewModel>? onHostMenu;
  final List<HeaderActionViewModel> headerActions;
  final bool loading;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
    return MoonlightShell(
      title: 'Hosts',
      actions: headerActions,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final gutter = MoonlightMetrics.horizontalGutter(
            constraints.maxWidth,
          );
          final available = constraints.maxWidth - gutter * 2;
          final columns = MoonlightMetrics.hostColumns(available);
          final items = hosts.length + 1;

          return Stack(
            children: [
              TvFocusTraversalGroup(
                child: GridView.builder(
                  key: const PageStorageKey('hosts-grid'),
                  padding: EdgeInsets.fromLTRB(gutter, 34, gutter, 56),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: 285 / 235,
                    crossAxisSpacing: 42,
                    mainAxisSpacing: 48,
                  ),
                  itemCount: items,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return AddHostCard(
                        autofocus: autofocusFirst,
                        onPressed: onAddHost,
                      );
                    }
                    final host = hosts[index - 1];
                    return HostCard(
                      key: ValueKey('host-${host.id}'),
                      host: host,
                      autofocus: !autofocusFirst && index == 1,
                      onPressed: () => onHostSelected(host),
                      onMenu: onHostMenu == null
                          ? null
                          : () => onHostMenu!(host),
                    );
                  },
                ),
              ),
              if (loading)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 18,
                  child: Center(
                    child: SizedBox(
                      width: 240,
                      child: LinearProgressIndicator(minHeight: 5),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AddHostCard extends StatelessWidget {
  const AddHostCard({
    required this.onPressed,
    super.key,
    this.autofocus = false,
  });

  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      semanticLabel: 'Add Host',
      scaleOnFocus: MoonlightMetrics.cardFocusScale,
      onActivate: onPressed,
      builder: (context, focused) =>
          const _HostCardSurface(title: 'Add Host', icon: Icons.add_to_queue),
    );
  }
}

class HostCard extends StatelessWidget {
  const HostCard({
    required this.host,
    required this.onPressed,
    super.key,
    this.onMenu,
    this.autofocus = false,
  });

  final HostTileViewModel host;
  final VoidCallback onPressed;
  final VoidCallback? onMenu;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final offline = host.availability == HostAvailability.offline;
    final focusColor = offline ? MoonlightColors.offline : MoonlightColors.cyan;
    final status = switch (host.availability) {
      HostAvailability.online => host.isPaired ? 'Online' : 'Not paired',
      HostAvailability.offline => 'Offline',
      HostAvailability.connecting => 'Connecting',
      HostAvailability.unknown => 'Status unknown',
    };

    return TvFocusable(
      autofocus: autofocus,
      semanticLabel: '${host.name}, $status',
      scaleOnFocus: MoonlightMetrics.cardFocusScale,
      focusColor: focusColor,
      onActivate: onPressed,
      onSecondaryActivate: onMenu,
      builder: (context, focused) => DecoratedBox(
        decoration: BoxDecoration(
          color: MoonlightColors.surface,
          border: !focused && offline
              ? Border.all(color: MoonlightColors.offline, width: 2)
              : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Center(
              child: Icon(Icons.tv, size: 64, color: Color(0xCCFFFFFF)),
            ),
            if (host.availability == HostAvailability.connecting)
              const Center(
                child: SizedBox.square(
                  dimension: 88,
                  child: CircularProgressIndicator(strokeWidth: 4),
                ),
              ),
            if (onMenu != null)
              Positioned(
                top: 0,
                right: 0,
                child: _HostMenuButton(onPressed: onMenu!),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                color: const Color(0xA6000000),
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      host.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w300,
                        letterSpacing: .5,
                      ),
                    ),
                    if (host.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        host.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MoonlightColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HostCardSurface extends StatelessWidget {
  const _HostCardSurface({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MoonlightColors.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: Icon(icon, size: 64, color: const Color(0xCCFFFFFF))),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: const Color(0xA6000000),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
              child: Text(
                title.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w300,
                  letterSpacing: .5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HostMenuButton extends StatelessWidget {
  const _HostMenuButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: TvFocusable(
        semanticLabel: 'Host menu',
        onActivate: onPressed,
        builder: (context, focused) => ColoredBox(
          color: focused
              ? MoonlightColors.cyan.withValues(alpha: .8)
              : const Color(0xA6000000),
          child: const Icon(Icons.menu, size: 25),
        ),
      ),
    );
  }
}
