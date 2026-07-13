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
      title: 'Moonlight',
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
                  padding: EdgeInsets.fromLTRB(gutter, 28, gutter, 48),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: 1.02,
                    crossAxisSpacing: 24,
                    mainAxisSpacing: 24,
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
          const _HostCardSurface(title: 'Add host', icon: Icons.add),
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
    const focusColor = MoonlightColors.cyan;
    final status = switch (host.availability) {
      HostAvailability.online =>
        !host.pairingStatusKnown
            ? 'Status unknown'
            : host.isPaired
            ? 'Online'
            : 'Pair required',
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
      builder: (context, focused) => Card(
        clipBehavior: Clip.antiAlias,
        color: MoonlightColors.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Icon(
                Icons.desktop_windows_rounded,
                size: 128,
                color: host.isPaired
                    ? MoonlightColors.cyan
                    : MoonlightColors.cyan.withValues(alpha: .88),
              ),
            ),
            if (host.pairingStatusKnown && !host.isPaired)
              const Center(
                child: CircleAvatar(
                  radius: 38,
                  backgroundColor: Color(0xFF30343A),
                  child: Icon(Icons.lock_outline_rounded, size: 40),
                ),
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      host.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _HostStatusChip(host: host, status: status),
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: Icon(icon, size: 96, color: MoonlightColors.cyan)),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HostStatusChip extends StatelessWidget {
  const _HostStatusChip({required this.host, required this.status});

  final HostTileViewModel host;
  final String status;

  @override
  Widget build(BuildContext context) {
    final online =
        host.pairingStatusKnown &&
        host.availability == HostAvailability.online &&
        host.isPaired;
    final color = online ? MoonlightColors.cyan : MoonlightColors.textMuted;
    final icon = online
        ? Icons.circle
        : !host.pairingStatusKnown
        ? Icons.sync
        : host.isPaired
        ? Icons.cloud_off_outlined
        : Icons.lock_outline_rounded;
    return Chip(
      avatar: Icon(icon, size: online ? 12 : 16, color: color),
      label: Text(status),
      side: BorderSide(color: color.withValues(alpha: .45)),
      backgroundColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      labelStyle: TextStyle(
        color: color,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _HostMenuButton extends StatelessWidget {
  const _HostMenuButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvIconButton(
      icon: Icons.more_vert,
      label: 'Host menu',
      onPressed: onPressed,
    );
  }
}
