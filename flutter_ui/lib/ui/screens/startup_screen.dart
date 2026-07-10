import 'package:flutter/material.dart';

import '../theme/moonlight_theme.dart';
import '../widgets/moonlight_shell.dart';
import '../widgets/tv_focusable.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({
    super.key,
    this.message = 'Loading Moonlight…',
    this.progress,
    this.error,
    this.onRetry,
  });

  final String message;
  final double? progress;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MoonlightShell(
      title: 'Moonlight',
      showHeader: false,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _PulsingLogo(),
                const SizedBox(height: 70),
                if (error == null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      minHeight: 10,
                      value: progress,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Semantics(
                    liveRegion: true,
                    label: message,
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                ] else ...[
                  const Icon(
                    Icons.error_outline,
                    color: MoonlightColors.offline,
                    size: 56,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 34),
                    SizedBox(
                      width: 260,
                      child: TvActionButton(
                        label: 'Retry',
                        icon: Icons.refresh,
                        autofocus: true,
                        onPressed: onRetry!,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingLogo extends StatefulWidget {
  const _PulsingLogo();

  @override
  State<_PulsingLogo> createState() => _PulsingLogoState();
}

class _PulsingLogoState extends State<_PulsingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: .82,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: const MoonlightLogo(size: 150),
    );
  }
}
