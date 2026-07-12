import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/host_workflows.dart';
import '../domain/domain.dart';
import '../state/state.dart';
import '../ui/moonlight_ui.dart';

typedef StartNativeStream = Future<void> Function(StreamRequest request);
typedef StopNativeStream = Future<void> Function();
typedef NativeAction = void Function();
typedef NativeBoolAction = bool Function();
typedef GamepadMaskReader = int Function();
typedef CheckForUpdates = Future<({String version, String notes})> Function();
typedef DiagnosticStatusReader = Map<String, Object?> Function();
typedef StartLogExport = Future<String> Function();
typedef ClearDiagnosticLogs = Future<Map<String, Object?>> Function();
typedef DiagnosticQrSvg = String Function(String value);
typedef ProbeCodecs =
    Future<Map<String, Object?>> Function(Map<String, Object?> request);

class MoonlightFlutterApp extends StatefulWidget {
  const MoonlightFlutterApp({
    required this.startNativeStream,
    required this.stopNativeStream,
    required this.unlockAudio,
    required this.connectedGamepadMask,
    required this.navigationActions,
    required this.checkForUpdates,
    required this.restartApp,
    required this.setDiagnosticLogLevel,
    required this.diagnosticStatus,
    required this.clearDiagnosticLogs,
    required this.startLogExport,
    required this.stopLogExport,
    required this.diagnosticQrSvg,
    required this.probeCodecs,
    super.key,
  });

  final StartNativeStream startNativeStream;
  final StopNativeStream stopNativeStream;
  final NativeAction unlockAudio;
  final GamepadMaskReader connectedGamepadMask;
  final Stream<String> navigationActions;
  final CheckForUpdates checkForUpdates;
  final NativeBoolAction restartApp;
  final ValueChanged<DiagnosticLogLevel> setDiagnosticLogLevel;
  final DiagnosticStatusReader diagnosticStatus;
  final ClearDiagnosticLogs clearDiagnosticLogs;
  final StartLogExport startLogExport;
  final Future<void> Function() stopLogExport;
  final DiagnosticQrSvg diagnosticQrSvg;
  final ProbeCodecs probeCodecs;

  @override
  State<MoonlightFlutterApp> createState() => _MoonlightFlutterAppState();
}

class _MoonlightFlutterAppState extends State<MoonlightFlutterApp> {
  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _page(state, _Page.hosts),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _page(state, _Page.settings),
      ),
      GoRoute(
        path: '/apps/:hostId',
        pageBuilder: (context, state) =>
            _page(state, _Page.apps, hostId: state.pathParameters['hostId']),
      ),
      GoRoute(
        path: '/stream/:hostId',
        pageBuilder: (context, state) =>
            _page(state, _Page.stream, hostId: state.pathParameters['hostId']),
      ),
    ],
  );

  Page<void> _page(GoRouterState state, _Page page, {String? hostId}) =>
      MaterialPage<void>(
        key: state.pageKey,
        child: _MoonlightExperience(
          page: page,
          hostId: hostId,
          startNativeStream: widget.startNativeStream,
          stopNativeStream: widget.stopNativeStream,
          unlockAudio: widget.unlockAudio,
          connectedGamepadMask: widget.connectedGamepadMask,
          navigationActions: widget.navigationActions,
          checkForUpdates: widget.checkForUpdates,
          restartApp: widget.restartApp,
          setDiagnosticLogLevel: widget.setDiagnosticLogLevel,
          diagnosticStatus: widget.diagnosticStatus,
          clearDiagnosticLogs: widget.clearDiagnosticLogs,
          startLogExport: widget.startLogExport,
          stopLogExport: widget.stopLogExport,
          diagnosticQrSvg: widget.diagnosticQrSvg,
          probeCodecs: widget.probeCodecs,
        ),
      );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Moonlight Flutter',
    debugShowCheckedModeBanner: false,
    theme: buildMoonlightTheme(),
    routerConfig: _router,
  );
}

enum _Page { hosts, apps, settings, stream }

class _MoonlightExperience extends ConsumerStatefulWidget {
  const _MoonlightExperience({
    required this.page,
    required this.startNativeStream,
    required this.stopNativeStream,
    required this.unlockAudio,
    required this.connectedGamepadMask,
    required this.navigationActions,
    required this.checkForUpdates,
    required this.restartApp,
    required this.setDiagnosticLogLevel,
    required this.diagnosticStatus,
    required this.clearDiagnosticLogs,
    required this.startLogExport,
    required this.stopLogExport,
    required this.diagnosticQrSvg,
    required this.probeCodecs,
    this.hostId,
  });

  final _Page page;
  final String? hostId;
  final StartNativeStream startNativeStream;
  final StopNativeStream stopNativeStream;
  final NativeAction unlockAudio;
  final GamepadMaskReader connectedGamepadMask;
  final Stream<String> navigationActions;
  final CheckForUpdates checkForUpdates;
  final NativeBoolAction restartApp;
  final ValueChanged<DiagnosticLogLevel> setDiagnosticLogLevel;
  final DiagnosticStatusReader diagnosticStatus;
  final ClearDiagnosticLogs clearDiagnosticLogs;
  final StartLogExport startLogExport;
  final Future<void> Function() stopLogExport;
  final DiagnosticQrSvg diagnosticQrSvg;
  final ProbeCodecs probeCodecs;

  @override
  ConsumerState<_MoonlightExperience> createState() =>
      _MoonlightExperienceState();
}

class _MoonlightExperienceState extends ConsumerState<_MoonlightExperience> {
  String? _settingsCategory = 'basic';
  Timer? _pollTimer;
  Timer? _updateTimer;
  StreamSubscription<String>? _navigationSubscription;
  bool _polling = false;
  DiagnosticLogLevel? _appliedLogLevel;
  final Set<int> _launchingApps = {};
  final Random _random = Random.secure();

  DiagnosticLogger get _logger => ref.read(diagnosticLoggerProvider);

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(
      HostPoller.pollInterval,
      (_) => unawaited(_pollHosts()),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_pollHosts()),
    );
    _navigationSubscription = widget.navigationActions.listen(
      _handleNavigationAction,
    );
    _updateTimer = Timer(
      const Duration(seconds: 10),
      () => unawaited(_automaticUpdateCheck()),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _updateTimer?.cancel();
    unawaited(_navigationSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diagnosticLevel = ref.watch(
      settingsProvider.select((settings) => settings.diagnosticLogLevel),
    );
    if (_appliedLogLevel != diagnosticLevel) {
      _appliedLogLevel = diagnosticLevel;
      widget.setDiagnosticLogLevel(diagnosticLevel);
    }
    ref.listen(streamSessionProvider, (previous, next) {
      final ended =
          next.phase == StreamSessionPhase.stopped ||
          next.phase == StreamSessionPhase.failed;
      if (widget.page == _Page.stream && ended) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.page == _Page.stream) {
            _goApps(widget.hostId);
          }
        });
      }
    });
    final bootstrap = ref.watch(bootstrapProvider);
    return bootstrap.when(
      loading: () => const StartupScreen(),
      error: (error, _) => StartupScreen(
        error: 'Moonlight could not start: $error',
        onRetry: () => ref.invalidate(bootstrapProvider),
      ),
      data: (_) => switch (widget.page) {
        _Page.hosts => _buildHosts(),
        _Page.apps => _buildApps(),
        _Page.settings => _buildSettings(),
        _Page.stream => _buildStream(),
      },
    );
  }

  Widget _buildHosts() {
    final entries = ref.watch(hostsProvider);
    return HostsScreen(
      loading: _polling,
      hosts: entries.map(_hostViewModel).toList(growable: false),
      onAddHost: _showAddHost,
      onHostSelected: _openHost,
      onHostMenu: _showHostMenu,
      headerActions: [
        HeaderActionViewModel(
          id: 'refresh',
          label: 'Refresh hosts',
          icon: Icons.refresh,
          enabled: !_polling,
          onPressed: () => unawaited(_pollHosts()),
        ),
        HeaderActionViewModel(
          id: 'settings',
          label: 'Settings',
          icon: Icons.settings,
          onPressed: _goSettings,
        ),
        HeaderActionViewModel(
          id: 'support',
          label: 'Support',
          icon: Icons.help_outline,
          onPressed: _showSupport,
        ),
      ],
    );
  }

  Widget _buildApps() {
    final host = _selectedHost;
    if (host == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goHosts());
      return _buildHosts();
    }
    final apps = ref.watch(appsProvider(host.id));
    final status =
        ref.watch(hostStatusesProvider)[host.id] ?? const HostStatus();
    return AppsScreen(
      hostName: host.hostname,
      loading: apps.isLoading,
      error: apps.hasError ? '${apps.error}' : null,
      apps:
          apps.value
              ?.map(
                (app) => AppTileViewModel(
                  id: '${app.id}',
                  title: app.title,
                  artwork: switch (ref.watch(boxArtProvider(host.id, app.id))) {
                    AsyncData(:final value) when value != null => MemoryImage(
                      value,
                    ),
                    _ => null,
                  },
                  isRunning: status.currentGameId == app.id,
                  isLoading: _launchingApps.contains(app.id),
                ),
              )
              .toList(growable: false) ??
          const [],
      onBack: _goHosts,
      onRetry: () => ref.invalidate(appsProvider(host.id)),
      onAppSelected: (viewModel) {
        final app = apps.value
            ?.where((candidate) => '${candidate.id}' == viewModel.id)
            .firstOrNull;
        if (app != null) _activateApp(host, status, app);
      },
      headerActions: [
        if (status.currentGameId != 0)
          HeaderActionViewModel(
            id: 'quit',
            label: 'Quit running app',
            icon: Icons.highlight_off,
            onPressed: () => _confirmQuit(host),
          ),
        HeaderActionViewModel(
          id: 'refresh',
          label: 'Refresh apps',
          icon: Icons.refresh,
          onPressed: () => ref.invalidate(appsProvider(host.id)),
        ),
      ],
    );
  }

  Widget _buildSettings() => SettingsScreen(
    categories: _settingsCategories(ref.watch(settingsProvider)),
    selectedCategoryId: _settingsCategory,
    onCategorySelected: (id) => setState(() => _settingsCategory = id),
    onBack: _goHosts,
    headerActions: [
      HeaderActionViewModel(
        id: 'restore',
        label: 'Restore defaults',
        icon: Icons.settings_backup_restore,
        onPressed: _confirmRestoreDefaults,
      ),
    ],
  );

  Widget _buildStream() => MoonlightShell(
    title: 'Streaming',
    showHeader: false,
    body: Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.transparent),
        Positioned(
          left: 28,
          bottom: 28,
          child: SizedBox(
            width: 250,
            child: TvActionButton(
              label: 'Stop stream',
              icon: Icons.stop,
              autofocus: true,
              onPressed: () => unawaited(_stopStream()),
            ),
          ),
        ),
      ],
    ),
  );

  HostTileViewModel _hostViewModel(HostEntry entry) => HostTileViewModel(
    id: entry.host.id,
    name: entry.host.hostname,
    address: entry.host.address,
    isPaired: entry.status.paired,
    availability: entry.status.online
        ? HostAvailability.online
        : entry.status.consecutivePollFailures == 0
        ? HostAvailability.unknown
        : HostAvailability.offline,
    subtitle: entry.status.online
        ? (entry.status.paired ? 'Online' : 'Pairing required')
        : 'Offline',
  );

  SavedHost? get _selectedHost => ref
      .watch(savedHostsProvider)
      .where((host) => host.id == widget.hostId)
      .firstOrNull;

  void _goHosts() => context.go('/');

  void _goSettings() => context.go('/settings');

  void _goApps(String? hostId) {
    if (hostId == null || hostId.isEmpty) {
      _goHosts();
      return;
    }
    context.go('/apps/${Uri.encodeComponent(hostId)}');
  }

  void _goStream(String hostId) =>
      context.go('/stream/${Uri.encodeComponent(hostId)}');

  Future<void> _pollHosts() async {
    if (!mounted || _polling || ref.read(streamSessionProvider).isActive) {
      return;
    }
    final hostIds = ref
        .read(savedHostsProvider)
        .map((host) => host.id)
        .toList();
    if (hostIds.isEmpty) return;
    setState(() => _polling = true);
    try {
      await Future.wait(
        hostIds.map((hostId) async {
          try {
            await ref.read(appCoordinatorProvider).pollHost(hostId);
          } catch (_) {
            // Reachability failures are reflected in HostStatus.
          }
        }),
      );
    } finally {
      if (mounted) setState(() => _polling = false);
    }
  }

  void _openHost(HostTileViewModel viewModel) {
    final host = ref
        .read(savedHostsProvider)
        .where((candidate) => candidate.id == viewModel.id)
        .firstOrNull;
    final status =
        ref.read(hostStatusesProvider)[viewModel.id] ?? const HostStatus();
    if (host == null || !status.online) {
      showMoonlightSnackBar(context, '${viewModel.name} is offline.');
      return;
    }
    if (!status.paired) {
      _pair(host);
      return;
    }
    _goApps(host.id);
  }

  void _showAddHost() {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => AddHostDialog(
        numericInput: ref.read(settingsProvider).showIpAddressField,
        onCancel: () => Navigator.of(dialogContext).pop(),
        onSubmit: (input) {
          Navigator.of(dialogContext).pop();
          unawaited(_addHost(input));
        },
      ),
    );
  }

  Future<void> _addHost(String input) async {
    final parsed = _parseHostInput(input);
    final host = SavedHost(
      id: parsed.address.toLowerCase(),
      hostname: parsed.address,
      address: parsed.address,
      userEnteredAddress: input.trim(),
      httpPort: parsed.port,
      httpsPort: parsed.port - 5,
    );
    _logger.log('info', 'ui.host.add_submitted', {
      'addressKind': parsed.address.contains(':')
          ? 'ipv6'
          : RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(parsed.address)
          ? 'ipv4'
          : 'hostname',
      'httpPort': parsed.port,
    });
    try {
      final result = await ref.read(appCoordinatorProvider).addHost(host);
      if (!mounted) return;
      if (result.status.paired) {
        showMoonlightSnackBar(context, 'Added ${result.host.hostname}.');
      } else {
        _pair(result.host);
      }
    } catch (error, stackTrace) {
      _logger.error('ui.host.add_failed', error, stackTrace);
      if (mounted) showMoonlightSnackBar(context, 'Could not add host: $error');
    }
  }

  void _pair(SavedHost host) {
    _logger.log('info', 'ui.pairing.dialog_opened');
    final pin = (1000 + _random.nextInt(9000)).toString();
    late BuildContext pairingContext;
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) {
        pairingContext = dialogContext;
        return PairingDialog(
          pin: pin,
          hostName: host.hostname,
          onCancel: () => Navigator.of(dialogContext).pop(),
        );
      },
    );
    unawaited(() async {
      try {
        final result = await ref
            .read(appCoordinatorProvider)
            .pair(host.id, pin);
        if (pairingContext.mounted) Navigator.of(pairingContext).pop();
        if (!mounted) return;
        showMoonlightSnackBar(
          context,
          result.paired ? 'Pairing complete.' : 'The host rejected pairing.',
        );
      } catch (error, stackTrace) {
        _logger.error('ui.pairing.failed', error, stackTrace);
        if (pairingContext.mounted) Navigator.of(pairingContext).pop();
        if (mounted) showMoonlightSnackBar(context, 'Pairing failed: $error');
      }
    }());
  }

  void _activateApp(SavedHost host, HostStatus status, MoonlightApp app) {
    // Browser audio APIs require this to happen synchronously in the input
    // event. Do not move it below an await.
    widget.unlockAudio();
    if (status.currentGameId != 0 && status.currentGameId != app.id) {
      _confirmSwitch(host, app);
      return;
    }
    unawaited(_launch(host, app));
  }

  void _confirmSwitch(SavedHost host, MoonlightApp app) {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Switch running app?',
        message: 'The app currently running on ${host.hostname} will be quit.',
        onCancel: () => Navigator.of(dialogContext).pop(),
        onConfirm: () {
          Navigator.of(dialogContext).pop();
          unawaited(() async {
            try {
              await ref.read(appCoordinatorProvider).quitRunningApp(host.id);
              await _launch(host, app);
            } catch (error) {
              if (mounted) {
                showMoonlightSnackBar(context, 'Switch failed: $error');
              }
            }
          }());
        },
      ),
    );
  }

  Future<void> _launch(SavedHost host, MoonlightApp app) async {
    if (_launchingApps.contains(app.id)) return;
    _logger.log('info', 'ui.stream.launch_selected', {'appId': app.id});
    setState(() => _launchingApps.add(app.id));
    try {
      final request = await ref
          .read(appCoordinatorProvider)
          .prepareStream(
            hostId: host.id,
            app: app,
            remoteInput: _remoteInputCredentials(),
            gamepadMask: widget.connectedGamepadMask(),
          );
      if (!mounted) return;
      _goStream(host.id);
      await widget.startNativeStream(request);
    } catch (error, stackTrace) {
      _logger.error('ui.stream.launch_failed', error, stackTrace, {
        'appId': app.id,
      });
      ref
          .read(streamSessionProvider.notifier)
          .fail(MoonlightRuntimeError(code: 'stream-start', message: '$error'));
      if (mounted) {
        _goApps(host.id);
        showMoonlightSnackBar(context, 'Unable to start ${app.title}: $error');
      }
    } finally {
      if (mounted) setState(() => _launchingApps.remove(app.id));
    }
  }

  Future<void> _stopStream() async {
    ref.read(streamSessionProvider.notifier).stopping();
    try {
      await widget.stopNativeStream();
    } catch (error, stackTrace) {
      _logger.error('ui.stream.stop_failed', error, stackTrace);
      if (mounted) showMoonlightSnackBar(context, 'Stop stream failed: $error');
    } finally {
      ref.read(appCoordinatorProvider).stopStreamOnly();
      if (mounted) _goApps(widget.hostId);
    }
  }

  void _confirmQuit(SavedHost host) {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Quit running app?',
        message: 'This ends the application on ${host.hostname}.',
        onCancel: () => Navigator.of(dialogContext).pop(),
        onConfirm: () {
          Navigator.of(dialogContext).pop();
          unawaited(() async {
            try {
              await ref.read(appCoordinatorProvider).quitRunningApp(host.id);
            } catch (error) {
              if (mounted) {
                showMoonlightSnackBar(context, 'Quit failed: $error');
              }
            }
          }());
        },
      ),
    );
  }

  void _showHostMenu(HostTileViewModel viewModel) {
    final host = ref
        .read(savedHostsProvider)
        .where((candidate) => candidate.id == viewModel.id)
        .firstOrNull;
    if (host == null) return;
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => HostMenuDialog(
        host: viewModel,
        wakeEnabled: host.macAddress.isNotEmpty,
        onWake: () {
          Navigator.of(dialogContext).pop();
          unawaited(_wake(host));
        },
        onDetails: () {
          Navigator.of(dialogContext).pop();
          _showHostDetails(host);
        },
        onDelete: () {
          Navigator.of(dialogContext).pop();
          _confirmRemoveHost(host);
        },
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  Future<void> _wake(SavedHost host) async {
    try {
      await ref.read(moonlightRepositoryProvider).wake(host);
      if (mounted) showMoonlightSnackBar(context, 'Wake-on-LAN packet sent.');
    } catch (error, stackTrace) {
      _logger.error('ui.host.wake_failed', error, stackTrace);
      if (mounted) showMoonlightSnackBar(context, 'Wake failed: $error');
    }
  }

  void _showHostDetails(SavedHost host) {
    final status =
        ref.read(hostStatusesProvider)[host.id] ?? const HostStatus();
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => HostDetailsDialog(
        hostName: host.hostname,
        details: [
          SystemInfoEntry('Address', host.address),
          SystemInfoEntry(
            'Server UID',
            host.serverUid.isEmpty ? 'Unknown' : host.serverUid,
          ),
          SystemInfoEntry('Paired', status.paired ? 'Yes' : 'No'),
          SystemInfoEntry('Server version', status.appVersion),
          SystemInfoEntry(
            'GPU',
            status.gpuType.isEmpty ? 'Unknown' : status.gpuType,
          ),
        ],
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  void _confirmRemoveHost(SavedHost host) {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Remove ${host.hostname}?',
        message:
            'Pairing and cached host information will be removed from this app.',
        onCancel: () => Navigator.of(dialogContext).pop(),
        onConfirm: () {
          ref.read(appCoordinatorProvider).removeHost(host.id);
          Navigator.of(dialogContext).pop();
        },
      ),
    );
  }

  List<SettingsCategoryViewModel> _settingsCategories(AppSettings settings) {
    final capabilities = ref.watch(platformCapabilitiesProvider);
    final codecCache = ref.watch(codecCapabilitiesProvider);
    void update(AppSettings value) =>
        ref.read(settingsProvider.notifier).replace(value);
    return [
      SettingsCategoryViewModel(
        id: 'basic',
        label: 'Basic Settings',
        icon: Icons.tune,
        options: [
          MoonlightSettingOption(
            title: 'Video resolution',
            control: TvChoiceControl<StreamResolution>(
              value: settings.resolution,
              choices: StreamResolution.known
                  .where(
                    (item) =>
                        item.width <= capabilities.maxWidth &&
                        item.height <= capabilities.maxHeight,
                  )
                  .map(
                    (item) => ChoiceItem(
                      value: item,
                      label: '${item.width} × ${item.height}',
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) => update(
                settings.withPresetInputs(
                  resolution: value,
                  capabilities: capabilities,
                ),
              ),
            ),
          ),
          MoonlightSettingOption(
            title: 'Frame rate',
            control: TvChoiceControl<int>(
              value: settings.frameRate,
              choices:
                  (settings.unlockAllFrameRates
                          ? AppSettings.unlockedFrameRates
                          : AppSettings.normalFrameRates)
                      .map(
                        (rate) => ChoiceItem(value: rate, label: '$rate FPS'),
                      )
                      .toList(growable: false),
              onChanged: (value) => update(
                settings.withPresetInputs(
                  frameRate: value,
                  capabilities: capabilities,
                ),
              ),
            ),
          ),
          MoonlightSettingOption(
            title: 'Video bitrate',
            description:
                'Increase image quality or reduce it for slower networks.',
            control: TvSliderControl(
              value: settings.bitrateMbps,
              min: .5,
              max: 150,
              step: .5,
              valueLabel: (value) => '${value.toStringAsFixed(1)} Mbps',
              onChanged: (value) =>
                  update(settings.copyWith(bitrateMbps: value)),
            ),
          ),
          _toggle(
            'IP address field mode',
            settings.showIpAddressField,
            (value) => update(settings.copyWith(showIpAddressField: value)),
          ),
          _toggle(
            'Sort applications',
            settings.sortApps,
            (value) => update(settings.copyWith(sortApps: value)),
          ),
          _toggle(
            'Optimize game settings',
            settings.optimizeGameSettings,
            (value) => update(settings.copyWith(optimizeGameSettings: value)),
          ),
          MoonlightSettingOption(
            title: 'Remove all hosts',
            control: TvActionButton(
              label: 'Remove all hosts',
              icon: Icons.delete_forever,
              destructive: true,
              onPressed: _confirmRemoveAllHosts,
            ),
          ),
        ],
      ),
      SettingsCategoryViewModel(
        id: 'input',
        label: 'Input Settings',
        icon: Icons.sports_esports,
        options: [
          _toggle(
            'Gamepad rumble',
            settings.rumbleFeedback,
            (value) {
              update(settings.copyWith(rumbleFeedback: value));
            },
            enabled: capabilities.supportsRumble,
          ),
          _toggle('Mouse emulation', settings.mouseEmulation, (value) {
            update(settings.copyWith(mouseEmulation: value));
          }),
          _toggle('Swap A/B buttons', settings.flipAbButtons, (value) {
            update(settings.copyWith(flipAbButtons: value));
          }),
          _toggle('Swap X/Y buttons', settings.flipXyButtons, (value) {
            update(settings.copyWith(flipXyButtons: value));
          }),
        ],
      ),
      SettingsCategoryViewModel(
        id: 'audio',
        label: 'Audio Settings',
        icon: Icons.volume_up,
        options: [
          MoonlightSettingOption(
            title: 'Audio backend',
            control: TvChoiceControl<AudioBackend>(
              value: settings.audioBackend,
              choices: [
                const ChoiceItem(
                  value: AudioBackend.webAudio,
                  label: 'Web Audio (recommended)',
                ),
                ChoiceItem(
                  value: AudioBackend.nativeEmss,
                  label: 'Native EMSS (experimental)',
                  enabled: capabilities.supportsNativeAudio,
                ),
              ],
              onChanged: (value) =>
                  update(settings.copyWith(audioBackend: value)),
            ),
          ),
          MoonlightSettingOption(
            title: 'Speaker configuration',
            control: TvChoiceControl<AudioConfiguration>(
              value: settings.audioConfiguration,
              choices: AudioConfiguration.values
                  .map((item) => ChoiceItem(value: item, label: item.name))
                  .toList(growable: false),
              onChanged: (value) =>
                  update(settings.copyWith(audioConfiguration: value)),
            ),
          ),
          MoonlightSettingOption(
            title: 'Audio packet duration',
            control: TvChoiceControl<int>(
              value: settings.audioPacketDurationMs,
              choices: AppSettings.packetDurationsMs
                  .map(
                    (duration) => ChoiceItem(
                      value: duration,
                      label: duration == 0 ? 'Auto' : '$duration ms',
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) =>
                  update(settings.copyWith(audioPacketDurationMs: value)),
            ),
          ),
          if (settings.audioBackend == AudioBackend.webAudio)
            MoonlightSettingOption(
              title: 'Maximum Web Audio buffer',
              control: TvSliderControl(
                value: settings.audioJitterBufferMs.toDouble(),
                min: 10,
                max: 500,
                step: 10,
                valueLabel: (value) => '${value.round()} ms',
                onChanged: (value) => update(
                  settings.copyWith(audioJitterBufferMs: value.round()),
                ),
              ),
            ),
          _toggle('Play audio on host', settings.playAudioOnHost, (value) {
            update(settings.copyWith(playAudioOnHost: value));
          }),
        ],
      ),
      SettingsCategoryViewModel(
        id: 'video',
        label: 'Video Settings',
        icon: Icons.high_quality,
        options: [
          MoonlightSettingOption(
            title: 'Video codec',
            control: TvChoiceControl<VideoCodec>(
              value: settings.videoCodec,
              choices: VideoCodec.values
                  .map(
                    (codec) => ChoiceItem(
                      value: codec,
                      label: codec.wireName,
                      enabled: capabilities.supportedCodecs.contains(codec),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) => update(
                settings.withPresetInputs(
                  videoCodec: value,
                  capabilities: capabilities,
                ),
              ),
            ),
          ),
          _toggle(
            'HDR',
            settings.hdr,
            (value) {
              update(
                settings.withPresetInputs(
                  hdr: value,
                  capabilities: capabilities,
                ),
              );
            },
            enabled:
                capabilities.supportsHdr &&
                settings.videoCodec != VideoCodec.h264,
          ),
          _toggle('Full color range', settings.fullColorRange, (value) {
            update(settings.copyWith(fullColorRange: value));
          }),
          _toggle('Video frame pacing', settings.framePacing, (value) {
            update(settings.copyWith(framePacing: value));
          }),
          _toggle('Optimize bitrate preset', settings.optimizeBitrate, (value) {
            update(
              settings.withPresetInputs(
                optimizeBitrate: value,
                capabilities: capabilities,
              ),
            );
          }),
        ],
      ),
      SettingsCategoryViewModel(
        id: 'advanced',
        label: 'Advanced Settings',
        icon: Icons.build,
        options: [
          _toggle('Game Mode', settings.gameMode, (value) {
            update(settings.copyWith(gameMode: value));
          }, enabled: capabilities.supportsGameMode),
          _toggle('Unlock all frame rates', settings.unlockAllFrameRates, (
            value,
          ) {
            update(settings.copyWith(unlockAllFrameRates: value));
          }),
          _toggle(
            'Disable connection warnings',
            settings.disableConnectionWarnings,
            (value) {
              update(settings.copyWith(disableConnectionWarnings: value));
            },
          ),
          _toggle(
            'Show performance statistics',
            settings.showPerformanceStats,
            (value) {
              update(settings.copyWith(showPerformanceStats: value));
            },
          ),
          MoonlightSettingOption(
            title: 'TV codec profile cache',
            control: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CodecCapabilityTable(
                  capabilities: codecCache.entries.values
                      .map(
                        (entry) => CodecCapabilityViewModel(
                          id: entry.key,
                          codec: entry.codec.wireName,
                          profile: entry.profile.isEmpty
                              ? (entry.mimeType.isEmpty
                                    ? 'Default'
                                    : entry.mimeType)
                              : entry.profile,
                          status: entry.supported == null
                              ? DiagnosticCapabilityStatus.unknown
                              : entry.supported!
                              ? DiagnosticCapabilityStatus.supported
                              : DiagnosticCapabilityStatus.unsupported,
                          enabled: entry.enabled,
                        ),
                      )
                      .toList(growable: false),
                  onEnabledChanged: (entry, enabled) => ref
                      .read(codecCapabilitiesProvider.notifier)
                      .setEnabled(entry.id, enabled),
                ),
                const SizedBox(height: 12),
                TvActionButton(
                  label: 'Probe codec profiles',
                  icon: Icons.fact_check_outlined,
                  onPressed: () => unawaited(_probeCodecProfiles(settings)),
                ),
              ],
            ),
          ),
          MoonlightSettingOption(
            title: 'Diagnostic log level',
            control: TvChoiceControl<DiagnosticLogLevel>(
              value: settings.diagnosticLogLevel,
              choices: DiagnosticLogLevel.values
                  .map(
                    (level) => ChoiceItem(
                      value: level,
                      label: level.name.toUpperCase(),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) =>
                  _setDiagnosticLogLevel(settings, value, update),
            ),
          ),
          MoonlightSettingOption(
            title: 'Diagnostic log storage',
            control: DiagnosticsActionPanel(
              status: _diagnosticStatusLabel(),
              actions: [
                MoonlightDialogAction(
                  label: 'Export diagnostic logs',
                  icon: Icons.file_download_outlined,
                  onPressed: () => unawaited(_exportDiagnosticLogs()),
                ),
                MoonlightDialogAction(
                  label: 'Clear diagnostic logs',
                  icon: Icons.delete_outline,
                  destructive: true,
                  onPressed: _confirmClearDiagnosticLogs,
                ),
              ],
            ),
          ),
        ],
      ),
      SettingsCategoryViewModel(
        id: 'about',
        label: 'About',
        icon: Icons.info_outline,
        options: [
          const MoonlightSettingOption(
            title: 'System information',
            control: SettingInfoPanel(
              entries: [
                SystemInfoEntry('Application', 'Moonlight Flutter 1.13.0'),
                SystemInfoEntry('Package', 'MLFlutter1.MoonlightFlutter'),
                SystemInfoEntry('UI runtime', 'Flutter Web / CanvasKit'),
                SystemInfoEntry('Native runtime', 'Moonlight Emscripten WASM'),
              ],
            ),
          ),
          MoonlightSettingOption(
            title: 'Navigation guide',
            control: TvActionButton(
              label: 'Open navigation guide',
              icon: Icons.tv,
              onPressed: _showNavigationGuide,
            ),
          ),
          MoonlightSettingOption(
            title: 'Check for updates',
            control: TvActionButton(
              label: 'Check for new Moonlight updates',
              icon: Icons.system_update_alt,
              onPressed: () => unawaited(_checkForUpdates()),
            ),
          ),
          MoonlightSettingOption(
            title: 'Restart the application',
            control: TvActionButton(
              label: 'Restart Moonlight Flutter',
              icon: Icons.restart_alt,
              onPressed: _confirmRestart,
            ),
          ),
        ],
      ),
    ];
  }

  MoonlightSettingOption _toggle(
    String title,
    bool value,
    ValueChanged<bool> onChanged, {
    bool enabled = true,
  }) => MoonlightSettingOption(
    title: title,
    control: TvToggleControl(
      value: value,
      label: title,
      enabled: enabled,
      onChanged: onChanged,
    ),
  );

  Future<void> _probeCodecProfiles(AppSettings settings) async {
    try {
      final status = widget.hostId == null
          ? const HostStatus()
          : ref.read(hostStatusesProvider)[widget.hostId] ?? const HostStatus();
      final current = ref.read(codecCapabilitiesProvider);
      final result = await widget.probeCodecs({
        'width': settings.resolution.width,
        'height': settings.resolution.height,
        'frameRate': settings.frameRate,
        'hdrMode': settings.hdr,
        'serverCodecModeSupport': status.serverCodecModeSupport,
        'preferredCodec': settings.videoCodec.wireName,
        'disabledMimeTypes': current.disabledMimeTypes.toList(),
      });
      final rawCandidates = result['candidates'];
      if (rawCandidates is! List) {
        throw const FormatException('The codec probe returned no candidates.');
      }
      final entries = <String, CodecCapabilityEntry>{...current.entries};
      for (final raw in rawCandidates) {
        if (raw is! Map) continue;
        final candidate = raw.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final mimeType = '${candidate['mimeType'] ?? ''}';
        final profile = '${candidate['profile'] ?? ''}';
        final codecName = '${candidate['codec'] ?? 'H264'}';
        final key = mimeType.isNotEmpty
            ? mimeType
            : '$codecName:$profile:${candidate['hdr'] == true}';
        final existing = entries[key];
        entries[key] = CodecCapabilityEntry(
          key: key,
          enabled: existing?.enabled ?? true,
          codec: VideoCodec.fromWireName(codecName) ?? VideoCodec.h264,
          hdr: candidate['hdr'] == true,
          profile: profile,
          mimeType: mimeType,
          supported: candidate['skipped'] == true
              ? existing?.supported
              : candidate['supported'] == true,
          attempts:
              (existing?.attempts ?? 0) +
              (candidate['skipped'] == true ? 0 : 1),
          lastTriedAt: candidate['skipped'] == true
              ? existing?.lastTriedAt
              : DateTime.now(),
          source: '${candidate['source'] ?? result['source'] ?? 'manual'}',
          lastWidth: settings.resolution.width,
          lastHeight: settings.resolution.height,
          lastFps: settings.frameRate,
          lastRequestedCodec: settings.videoCodec.wireName,
          lastRequestedHdrMode: settings.hdr,
        );
      }
      ref
          .read(codecCapabilitiesProvider.notifier)
          .replace(CodecCapabilityCache(entries: Map.unmodifiable(entries)));
      if (mounted) {
        setState(() {});
        showMoonlightSnackBar(context, 'Codec profile probe complete.');
      }
    } catch (error, stackTrace) {
      _logger.error('ui.codec_probe.failed', error, stackTrace);
      if (mounted) {
        showMoonlightSnackBar(context, 'Codec probe failed: $error');
      }
    }
  }

  void _setDiagnosticLogLevel(
    AppSettings settings,
    DiagnosticLogLevel value,
    ValueChanged<AppSettings> update,
  ) {
    widget.setDiagnosticLogLevel(value);
    update(settings.copyWith(diagnosticLogLevel: value));
  }

  String _diagnosticStatusLabel() {
    final status = widget.diagnosticStatus();
    return 'Level: ${status['level'] ?? 'off'} · '
        '${status['entryCount'] ?? 0} entries · ${status['bytes'] ?? 0} bytes';
  }

  Future<void> _exportDiagnosticLogs() async {
    final settings = ref.read(settingsProvider);
    final statuses = ref.read(hostStatusesProvider).values.toList();
    _logger.log('info', 'diagnostics.context_snapshot', {
      'appVersion': '1.13.0',
      'packageId': 'MLFlutter1',
      'savedHostCount': ref.read(savedHostsProvider).length,
      'onlineHostCount': statuses.where((status) => status.online).length,
      'pairedHostCount': statuses.where((status) => status.paired).length,
      'activeStreamPhase': ref.read(streamSessionProvider).phase.name,
      'resolution': settings.resolution.wireName,
      'frameRate': settings.frameRate,
      'bitrateKbps': settings.bitrateKbps,
      'videoCodec': settings.videoCodec.wireName,
      'hdr': settings.hdr,
      'gameMode': settings.gameMode,
      'audioConfiguration': settings.audioConfiguration.wireName,
      'codecCacheEntries': ref.read(codecCapabilitiesProvider).entries.length,
    });
    try {
      final url = await widget.startLogExport();
      if (!mounted) return;
      final qrSvg = widget.diagnosticQrSvg(url);
      showMoonlightDialog<void>(
        context: context,
        builder: (dialogContext) => LogExportDialog(
          url: url,
          status: 'Open this address from a device on the same network.',
          qrCode: qrSvg.isEmpty ? null : DiagnosticQrCode(svg: qrSvg),
          onStop: () {
            unawaited(widget.stopLogExport());
            Navigator.of(dialogContext).pop();
          },
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      );
    } catch (error, stackTrace) {
      _logger.error('diagnostics.export_failed', error, stackTrace);
      if (mounted) {
        showMoonlightSnackBar(context, 'Log export failed: $error');
      }
    }
  }

  void _confirmClearDiagnosticLogs() {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Clear diagnostic logs?',
        message:
            'All diagnostic entries stored by this Flutter app will be removed.',
        onCancel: () => Navigator.of(dialogContext).pop(),
        onConfirm: () {
          Navigator.of(dialogContext).pop();
          unawaited(() async {
            await widget.clearDiagnosticLogs();
            if (mounted) setState(() {});
          }());
        },
      ),
    );
  }

  void _confirmRemoveAllHosts() {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Remove all hosts?',
        message: 'All saved hosts and pairing information will be removed.',
        onCancel: () => Navigator.of(dialogContext).pop(),
        onConfirm: () {
          final coordinator = ref.read(appCoordinatorProvider);
          final hostIds = ref
              .read(savedHostsProvider)
              .map((host) => host.id)
              .toList(growable: false);
          for (final hostId in hostIds) {
            coordinator.removeHost(hostId);
          }
          Navigator.of(dialogContext).pop();
        },
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    showMoonlightSnackBar(context, 'Checking for Moonlight updates…');
    try {
      final release = await widget.checkForUpdates();
      ref.read(updateCheckTimestampProvider.notifier).mark(DateTime.now());
      if (!mounted) return;
      showMoonlightDialog<void>(
        context: context,
        builder: (dialogContext) => MoonlightDialog(
          title: 'Latest release: ${release.version}',
          icon: Icons.system_update_alt,
          actions: [
            MoonlightDialogAction(
              label: 'Close',
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
          child: SelectableText(
            release.notes,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    } catch (error, stackTrace) {
      _logger.error('ui.update_check.failed', error, stackTrace);
      if (mounted) {
        showMoonlightSnackBar(context, 'Update check failed: $error');
      }
    }
  }

  Future<void> _automaticUpdateCheck() async {
    final previous = ref.read(updateCheckTimestampProvider);
    if (previous != null &&
        DateTime.now().difference(previous) < const Duration(hours: 24)) {
      return;
    }
    try {
      final release = await widget.checkForUpdates();
      ref.read(updateCheckTimestampProvider.notifier).mark(DateTime.now());
      if (mounted && _isNewerVersion(release.version, '1.13.0')) {
        showMoonlightSnackBar(
          context,
          'Moonlight ${release.version} is available.',
        );
      }
    } catch (_) {
      // Automatic update checks are intentionally quiet when offline.
    }
  }

  void _confirmRestart() {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Restart Moonlight Flutter?',
        message: 'The application will close and immediately relaunch.',
        onCancel: () => Navigator.of(dialogContext).pop(),
        onConfirm: () {
          Navigator.of(dialogContext).pop();
          if (!widget.restartApp()) {
            showMoonlightSnackBar(context, 'Restart is unavailable.');
          }
        },
      ),
    );
  }

  void _confirmRestoreDefaults() {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Restore default settings?',
        message:
            'All streaming, input, audio, and video preferences will be reset.',
        onCancel: () => Navigator.of(dialogContext).pop(),
        onConfirm: () {
          ref.read(settingsProvider.notifier).restoreDefaults();
          Navigator.of(dialogContext).pop();
        },
      ),
    );
  }

  void _showSupport() {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => SupportDialog(
        version: '1.13.0 (Flutter preview)',
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  void _showNavigationGuide() {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => NavigationGuideDialog(
        bindings: defaultNavigationBindings,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  RemoteInputCredentials _remoteInputCredentials() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final key = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final keyId = ((_random.nextInt(1 << 16) << 16) | _random.nextInt(1 << 16))
        .toSigned(32);
    return RemoteInputCredentials(key: key, keyId: keyId);
  }

  void _handleNavigationAction(String action) {
    if (!mounted) return;
    if (action == 'back') {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
        return;
      }
      if (widget.page == _Page.apps || widget.page == _Page.settings) {
        _goHosts();
      }
      return;
    }

    // Browser keyboard events already move Flutter focus directly. Gamepad
    // actions arrive through the normalized native sink, so mirror those
    // actions onto the current focus node while the app is in UI mode.
    if (widget.page == _Page.stream) return;
    final focus = FocusManager.instance.primaryFocus;
    final direction = switch (action) {
      'up' => TraversalDirection.up,
      'down' => TraversalDirection.down,
      'left' => TraversalDirection.left,
      'right' => TraversalDirection.right,
      _ => null,
    };
    if (direction != null) {
      focus?.focusInDirection(direction);
      return;
    }
    if (action == 'accept') {
      TvFocusable.activate(focus);
    }
  }
}

final class _HostInput {
  const _HostInput(this.address, this.port);
  final String address;
  final int port;
}

_HostInput _parseHostInput(String source) {
  final value = source.trim();
  if (value.isEmpty) throw const FormatException('Host address is empty.');
  final uri = Uri.tryParse(
    value.contains('://') ? value : 'moonlight://$value',
  );
  if (uri == null || uri.host.isEmpty) {
    throw FormatException('Invalid host address: $source');
  }
  return _HostInput(
    uri.host,
    uri.hasPort ? uri.port : SavedHost.defaultHttpPort,
  );
}

bool _isNewerVersion(String candidate, String current) {
  List<int> parts(String value) => RegExp(r'\d+')
      .allMatches(value)
      .take(3)
      .map((match) => int.parse(match.group(0)!))
      .toList(growable: false);
  final left = parts(candidate);
  final right = parts(current);
  for (var index = 0; index < 3; index++) {
    final candidatePart = index < left.length ? left[index] : 0;
    final currentPart = index < right.length ? right[index] : 0;
    if (candidatePart != currentPart) return candidatePart > currentPart;
  }
  return false;
}
