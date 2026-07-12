import 'package:flutter/material.dart';

import '../theme/moonlight_theme.dart';
import '../view_models.dart';
import '../widgets/moonlight_shell.dart';
import '../widgets/tv_focusable.dart';

class AppsScreen extends StatelessWidget {
  const AppsScreen({
    required this.hostName,
    required this.apps,
    required this.onAppSelected,
    required this.onBack,
    super.key,
    this.headerActions = const [],
    this.loading = false,
    this.error,
    this.onRetry,
  });

  final String hostName;
  final List<AppTileViewModel> apps;
  final ValueChanged<AppTileViewModel> onAppSelected;
  final VoidCallback onBack;
  final List<HeaderActionViewModel> headerActions;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MoonlightShell(
      title: hostName,
      onBack: onBack,
      actions: headerActions,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (error != null && apps.isEmpty) {
            return AppListMessage(
              icon: Icons.cloud_off,
              title: 'Could not load apps',
              message: error!,
              actionLabel: onRetry == null ? null : 'Retry',
              onAction: onRetry,
            );
          }
          if (loading && apps.isEmpty) {
            return const AppListMessage(
              icon: Icons.downloading,
              title: 'Loading apps…',
              showProgress: true,
            );
          }
          if (apps.isEmpty) {
            return AppListMessage(
              icon: Icons.sports_esports_outlined,
              title: 'No apps found',
              message:
                  'Add an application in Sunshine, then refresh this host.',
              actionLabel: onRetry == null ? null : 'Refresh',
              onAction: onRetry,
            );
          }

          final gutter = MoonlightMetrics.horizontalGutter(
            constraints.maxWidth,
          );
          final available = constraints.maxWidth - gutter * 2;
          final columns = MoonlightMetrics.appColumns(available);
          return Stack(
            children: [
              TvFocusTraversalGroup(
                child: GridView.builder(
                  key: const PageStorageKey('apps-grid'),
                  padding: EdgeInsets.fromLTRB(gutter, 28, gutter, 48),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: .78,
                    crossAxisSpacing: 28,
                    mainAxisSpacing: 28,
                  ),
                  itemCount: apps.length,
                  itemBuilder: (context, index) {
                    final app = apps[index];
                    return AppCard(
                      key: ValueKey('app-${app.id}'),
                      app: app,
                      autofocus: index == 0,
                      onPressed: () => onAppSelected(app),
                    );
                  },
                ),
              ),
              if (loading)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 15,
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

class AppCard extends StatelessWidget {
  const AppCard({
    required this.app,
    required this.onPressed,
    super.key,
    this.autofocus = false,
  });

  final AppTileViewModel app;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final focusColor = app.isRunning
        ? MoonlightColors.running
        : MoonlightColors.cyan;
    return TvFocusable(
      autofocus: autofocus,
      enabled: app.enabled && !app.isLoading,
      semanticLabel: app.isRunning ? '${app.title}, running' : app.title,
      scaleOnFocus: MoonlightMetrics.cardFocusScale,
      focusColor: focusColor,
      onActivate: onPressed,
      builder: (context, focused) => Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (app.artwork != null)
              Image(
                image: app.artwork!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const _ArtworkPlaceholder(),
              )
            else
              const _ArtworkPlaceholder(),
            if (!app.enabled) const ColoredBox(color: Color(0x88000000)),
            if (app.isLoading)
              const ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: SizedBox.square(
                    dimension: 52,
                    child: CircularProgressIndicator(strokeWidth: 4),
                  ),
                ),
              ),
            if (app.isRunning)
              const Positioned(
                top: 16,
                left: 16,
                child: Chip(
                  avatar: Icon(
                    Icons.play_arrow_rounded,
                    size: 20,
                    color: MoonlightColors.running,
                  ),
                  label: Text('Running'),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 48, 20, 22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xE6000000)],
                  ),
                ),
                child: Text(
                  app.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: MoonlightColors.surfaceRaised,
      child: Center(
        child: Icon(
          Icons.sports_esports_rounded,
          size: 96,
          color: MoonlightColors.textMuted,
        ),
      ),
    );
  }
}

class AppListMessage extends StatelessWidget {
  const AppListMessage({
    required this.icon,
    required this.title,
    super.key,
    this.message,
    this.showProgress = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final bool showProgress;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 88, color: MoonlightColors.textMuted),
              const SizedBox(height: 26),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (message != null) ...[
                const SizedBox(height: 16),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              if (showProgress) ...[
                const SizedBox(height: 30),
                const SizedBox(
                  width: 260,
                  child: LinearProgressIndicator(minHeight: 8),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 30),
                SizedBox(
                  width: 260,
                  child: TvActionButton(
                    label: actionLabel!,
                    autofocus: true,
                    onPressed: onAction!,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
