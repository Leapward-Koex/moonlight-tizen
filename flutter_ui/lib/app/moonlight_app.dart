import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/host_workflows.dart';
import '../data/native/native_runtime.dart';
import '../domain/domain.dart';
import '../state/state.dart';
import '../ui/moonlight_ui.dart';

typedef StartNativeStream = Future<void> Function(StreamRequest request);
typedef StopNativeStream = Future<void> Function();
typedef RecoverNativeStreamSurface = void Function();
typedef NativeAction = void Function();
typedef NativeBoolAction = bool Function();
typedef GamepadMaskReader = int Function();
typedef InputDevicesReader = List<NativeInputDevice> Function();
typedef TestRumble = bool Function(int browserIndex);
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
    required this.recoverNativeStreamSurface,
    required this.unlockAudio,
    required this.connectedGamepadMask,
    required this.inputDevices,
    required this.testRumble,
    required this.navigationActions,
    required this.checkForUpdates,
    required this.restartApp,
    required this.exitApp,
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
  final RecoverNativeStreamSurface recoverNativeStreamSurface;
  final NativeAction unlockAudio;
  final GamepadMaskReader connectedGamepadMask;
  final InputDevicesReader inputDevices;
  final TestRumble testRumble;
  final Stream<String> navigationActions;
  final CheckForUpdates checkForUpdates;
  final NativeBoolAction restartApp;
  final NativeBoolAction exitApp;
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
          recoverNativeStreamSurface: widget.recoverNativeStreamSurface,
          unlockAudio: widget.unlockAudio,
          connectedGamepadMask: widget.connectedGamepadMask,
          inputDevices: widget.inputDevices,
          testRumble: widget.testRumble,
          navigationActions: widget.navigationActions,
          checkForUpdates: widget.checkForUpdates,
          restartApp: widget.restartApp,
          exitApp: widget.exitApp,
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
    required this.recoverNativeStreamSurface,
    required this.unlockAudio,
    required this.connectedGamepadMask,
    required this.inputDevices,
    required this.testRumble,
    required this.navigationActions,
    required this.checkForUpdates,
    required this.restartApp,
    required this.exitApp,
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
  final RecoverNativeStreamSurface recoverNativeStreamSurface;
  final NativeAction unlockAudio;
  final GamepadMaskReader connectedGamepadMask;
  final InputDevicesReader inputDevices;
  final TestRumble testRumble;
  final Stream<String> navigationActions;
  final CheckForUpdates checkForUpdates;
  final NativeBoolAction restartApp;
  final NativeBoolAction exitApp;
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
  final GlobalKey<SettingsScreenState> _settingsScreenKey = GlobalKey();

  DiagnosticLogger get _logger => ref.read(diagnosticLoggerProvider);

  @override
  void initState() {
    super.initState();
    unawaited(
      Future<void>.microtask(
        () => ref.read(subnetDiscoveryProvider.notifier).start(),
      ),
    );
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
      final ended = next.phase == StreamSessionPhase.stopped;
      if (widget.page == _Page.stream && ended) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.page == _Page.stream) {
            _goApps(widget.hostId);
          }
        });
      }
    });
    ref.listen(subnetDiscoveryProvider, (previous, next) {
      if (widget.page != _Page.hosts || previous?.phase == next.phase) return;
      final message = switch (next.phase) {
        SubnetDiscoveryPhase.scanning =>
          'Scanning the local network for Moonlight hosts…',
        SubnetDiscoveryPhase.complete when next.summary.changedHostCount > 0 =>
          _subnetDiscoveryMessage(next.summary),
        _ => null,
      };
      if (message != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.page == _Page.hosts) {
            showMoonlightSnackBar(context, message);
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
    final discovery = ref.watch(subnetDiscoveryProvider);
    final refreshing =
        _polling || discovery.phase == SubnetDiscoveryPhase.scanning;
    final initialDiscoveryInProgress = switch (discovery.phase) {
      SubnetDiscoveryPhase.idle || SubnetDiscoveryPhase.waiting => _polling,
      SubnetDiscoveryPhase.scanning => true,
      _ => false,
    };
    return HostsScreen(
      loading: initialDiscoveryInProgress,
      hosts: entries.map(_hostViewModel).toList(growable: false),
      onAddHost: _showAddHost,
      onHostSelected: _openHost,
      onHostMenu: _showHostMenu,
      headerActions: [
        HeaderActionViewModel(
          id: 'refresh',
          label: 'Refresh hosts',
          icon: Icons.refresh,
          enabled: !refreshing,
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
    key: _settingsScreenKey,
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

  Widget _buildStream() {
    final session = ref.watch(streamSessionProvider);
    if (session.phase == StreamSessionPhase.failed) {
      final hasHost = widget.hostId != null && widget.hostId!.isNotEmpty;
      return MoonlightShell(
        title: 'Streaming error',
        onBack: _recoverFromStreamError,
        body: AppListMessage(
          icon: Icons.error_outline,
          title: 'The stream could not start',
          message: session.error?.message.isNotEmpty ?? false
              ? session.error!.message
              : 'Moonlight encountered a native streaming error.',
          actionLabel: hasHost ? 'Back to games' : 'Back to hosts',
          onAction: _recoverFromStreamError,
        ),
      );
    }
    return MoonlightShell(
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
  }

  HostTileViewModel _hostViewModel(HostEntry entry) => HostTileViewModel(
    id: entry.host.id,
    name: entry.host.hostname,
    address: entry.host.address,
    isPaired: entry.status.paired,
    pairingStatusKnown: entry.statusKnown,
    availability: !entry.statusKnown
        ? HostAvailability.unknown
        : entry.status.online
        ? HostAvailability.online
        : entry.status.consecutivePollFailures == 0
        ? HostAvailability.unknown
        : HostAvailability.offline,
    subtitle: !entry.statusKnown
        ? 'Checking status…'
        : entry.status.online
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
    setState(() => _polling = true);
    try {
      try {
        await ref.read(bootstrapProvider.future);
      } catch (_) {
        // Bootstrap failures are rendered by bootstrapProvider in build().
        return;
      }
      // Persistence restores provider state asynchronously after the backing
      // store opens. Let that state update land before the startup poll reads
      // the saved host list.
      await Future<void>.delayed(Duration.zero);
      if (!mounted || ref.read(streamSessionProvider).isActive) return;
      final hostIds = ref
          .read(savedHostsProvider)
          .map((host) => host.id)
          .toList();
      if (hostIds.isEmpty) return;
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
    BuildContext? pairingContext;
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
        final dialogContext = pairingContext;
        if (dialogContext != null && dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        if (!mounted) return;
        if (result.paired) {
          showMoonlightSnackBar(context, 'Pairing complete.');
          _goApps(result.host.id);
          return;
        }
        showMoonlightSnackBar(context, 'The host rejected pairing.');
      } catch (error, stackTrace) {
        _logger.error('ui.pairing.failed', error, stackTrace);
        final dialogContext = pairingContext;
        if (dialogContext != null && dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
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

  void _recoverFromStreamError() {
    widget.recoverNativeStreamSurface();
    ref.read(appCoordinatorProvider).stopStreamOnly();
    _goApps(widget.hostId);
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
        icon: Icons.tv,
        options: [
          MoonlightSettingOption(
            title: 'Video resolution',
            description:
                'Increase for a clearer image, or decrease for better performance on lower-end devices and slower networks.',
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
            title: 'Video frame rate',
            description:
                'Increase for smoother video, or decrease for better performance on lower-end devices.',
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
                'Increase for better image quality, or decrease to improve performance on slower connections.',
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
            'Video frame pacing',
            settings.framePacing,
            (value) {
              update(settings.copyWith(framePacing: value));
            },
            description:
                'Helps reduce micro-stutter by delaying frames that arrive too early while streaming.',
            controlLabel:
                'Balance video latency and smoothness with frame pacing',
          ),
        ],
      ),
      SettingsCategoryViewModel(
        id: 'host',
        label: 'Host Settings',
        icon: Icons.desktop_windows,
        options: [
          _toggle(
            'IP address field mode',
            settings.showIpAddressField,
            (value) => update(settings.copyWith(showIpAddressField: value)),
            description:
                'Recommended for devices that have trouble using the TV keyboard to enter a host IP address.',
            controlLabel: 'Use a numeric input field for host IP addresses',
          ),
          _toggle(
            'Sort the list of apps',
            settings.sortApps,
            (value) => update(settings.copyWith(sortApps: value)),
            description:
                'Sorts host apps and games by title. Enable for descending order (Z to A).',
            controlLabel: 'Sort apps and games in descending order',
          ),
          _toggle(
            'Optimize game settings',
            settings.optimizeGameSettings,
            (value) => update(settings.copyWith(optimizeGameSettings: value)),
            description:
                'Adjusts the host resolution to match the client resolution when the display device is configured in Sunshine.',
            controlLabel:
                'Allow the host to modify game settings for optimal streaming',
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
          MoonlightSettingOption(
            title: 'Connected controllers',
            description:
                'Live device status, input testing, per-device layouts, and rumble capability.',
            fullWidthControl: true,
            control: InputDevicesControl(
              devicesReader: widget.inputDevices,
              defaultLayout: settings.controllerLayout,
              profiles: settings.controllerProfiles,
              onLayoutChanged: (fingerprint, layout) {
                final profiles = Map<String, ControllerLayout>.of(
                  settings.controllerProfiles,
                );
                if (layout == ControllerLayout.automatic) {
                  profiles.remove(fingerprint);
                } else {
                  profiles[fingerprint] = layout;
                }
                update(settings.copyWith(controllerProfiles: profiles));
              },
              onResetDevice: (fingerprint) {
                final profiles = Map<String, ControllerLayout>.of(
                  settings.controllerProfiles,
                )..remove(fingerprint);
                update(settings.copyWith(controllerProfiles: profiles));
              },
              onTestRumble: (browserIndex) {
                if (!widget.testRumble(browserIndex)) {
                  showMoonlightSnackBar(context, 'Rumble is unavailable.');
                }
              },
            ),
          ),
          MoonlightSettingOption(
            title: 'Default controller layout',
            description:
                'Used by controllers without a device-specific override. Automatic preserves the legacy face-button swaps.',
            control: TvChoiceControl<ControllerLayout>(
              value: settings.controllerLayout,
              choices: const [
                ChoiceItem(
                  value: ControllerLayout.automatic,
                  label: 'Automatic',
                ),
                ChoiceItem(value: ControllerLayout.xbox, label: 'Xbox'),
                ChoiceItem(value: ControllerLayout.nintendo, label: 'Nintendo'),
                ChoiceItem(
                  value: ControllerLayout.playStation,
                  label: 'PlayStation',
                ),
                ChoiceItem(
                  value: ControllerLayout.custom,
                  label: 'Custom swaps',
                ),
              ],
              onChanged: (value) =>
                  update(settings.copyWith(controllerLayout: value)),
            ),
          ),
          _toggle(
            'Rumble feedback',
            settings.rumbleFeedback,
            (value) {
              update(settings.copyWith(rumbleFeedback: value));
            },
            enabled: capabilities.supportsRumble,
            description: capabilities.supportsRumble
                ? 'Forwards host force feedback to controllers with a supported vibration actuator.'
                : 'Rumble is unavailable on this platform.',
            controlLabel: 'Allow gamepad rumble feedback while streaming',
          ),
          MoonlightSettingOption(
            title: 'Stick deadzone',
            description:
                'Ignores small stick movement to prevent drift. Increase only as much as your controller needs.',
            control: TvSliderControl(
              value: settings.stickDeadzone,
              min: 0,
              max: .5,
              step: .01,
              valueLabel: (value) => '${(value * 100).round()}%',
              onChanged: (value) =>
                  update(settings.copyWith(stickDeadzone: value)),
            ),
          ),
          MoonlightSettingOption(
            title: 'Trigger threshold',
            description:
                'Ignores light trigger pressure and rescales the remaining analog range.',
            control: TvSliderControl(
              value: settings.triggerThreshold,
              min: 0,
              max: .5,
              step: .01,
              valueLabel: (value) => '${(value * 100).round()}%',
              onChanged: (value) =>
                  update(settings.copyWith(triggerThreshold: value)),
            ),
          ),
          MoonlightSettingOption(
            title: 'Controller sensitivity',
            description:
                'Changes the response curve after the deadzone without reducing the maximum range.',
            control: TvSliderControl(
              value: settings.controllerSensitivity,
              min: .5,
              max: 2,
              step: .05,
              valueLabel: (value) => '${value.toStringAsFixed(2)}×',
              onChanged: (value) =>
                  update(settings.copyWith(controllerSensitivity: value)),
            ),
          ),
          _toggle(
            'Invert controller Y axis',
            settings.invertControllerYAxis,
            (value) => update(settings.copyWith(invertControllerYAxis: value)),
            description: 'Inverts both vertical stick axes while streaming.',
          ),
          _toggle(
            'Mouse emulation',
            settings.mouseEmulation,
            (value) {
              update(settings.copyWith(mouseEmulation: value));
            },
            description:
                'Turns one controller into a mouse without affecting other connected controllers.',
            controlLabel: 'Hold Start to switch the gamepad to mouse mode',
          ),
          MoonlightSettingOption(
            title: 'Mouse-mode activation button',
            description:
                'Hold the selected button for one second. The mode toggles once per press.',
            control: TvChoiceControl<MouseActivationButton>(
              value: settings.mouseActivationButton,
              choices: const [
                ChoiceItem(value: MouseActivationButton.start, label: 'Start'),
                ChoiceItem(value: MouseActivationButton.back, label: 'Back'),
                ChoiceItem(
                  value: MouseActivationButton.leftStick,
                  label: 'Left stick click',
                ),
                ChoiceItem(
                  value: MouseActivationButton.rightStick,
                  label: 'Right stick click',
                ),
              ],
              onChanged: (value) =>
                  update(settings.copyWith(mouseActivationButton: value)),
            ),
          ),
          MoonlightSettingOption(
            title: 'Mouse-emulation speed',
            description: 'Controls pointer speed for the left stick.',
            control: TvSliderControl(
              value: settings.mouseEmulationSpeed,
              min: .25,
              max: 3,
              step: .05,
              valueLabel: (value) => '${value.toStringAsFixed(2)}×',
              onChanged: (value) =>
                  update(settings.copyWith(mouseEmulationSpeed: value)),
            ),
          ),
          MoonlightSettingOption(
            title: 'Mouse-emulation acceleration',
            description:
                'Adjusts fine control near the center while retaining full-stick speed.',
            control: TvSliderControl(
              value: settings.mouseAcceleration,
              min: .5,
              max: 2.5,
              step: .05,
              valueLabel: (value) => value.toStringAsFixed(2),
              onChanged: (value) =>
                  update(settings.copyWith(mouseAcceleration: value)),
            ),
          ),
          MoonlightSettingOption(
            title: 'Mouse-emulation scroll speed',
            description:
                'Controls continuous horizontal and vertical scrolling for the right stick.',
            control: TvSliderControl(
              value: settings.mouseScrollSpeed,
              min: .25,
              max: 5,
              step: .25,
              valueLabel: (value) => '${value.toStringAsFixed(2)}×',
              onChanged: (value) =>
                  update(settings.copyWith(mouseScrollSpeed: value)),
            ),
          ),
          MoonlightSettingOption(
            title: 'Physical mouse sensitivity',
            description:
                'Scales relative mouse movement before it is sent to the host.',
            control: TvSliderControl(
              value: settings.physicalMouseSensitivity,
              min: .25,
              max: 3,
              step: .05,
              valueLabel: (value) => '${value.toStringAsFixed(2)}×',
              onChanged: (value) =>
                  update(settings.copyWith(physicalMouseSensitivity: value)),
            ),
          ),
          _toggle(
            'Invert physical mouse scrolling',
            settings.invertMouseScroll,
            (value) => update(settings.copyWith(invertMouseScroll: value)),
            description: 'Reverses vertical wheel direction on the host.',
          ),
          MoonlightSettingOption(
            title: 'Pointer capture',
            description:
                'Capture on stream start is best effort because some platforms require a click.',
            control: TvChoiceControl<PointerCaptureMode>(
              value: settings.pointerCaptureMode,
              choices: const [
                ChoiceItem(
                  value: PointerCaptureMode.firstClick,
                  label: 'First click',
                ),
                ChoiceItem(
                  value: PointerCaptureMode.streamStart,
                  label: 'Stream start',
                ),
                ChoiceItem(
                  value: PointerCaptureMode.disabled,
                  label: 'Disabled',
                ),
              ],
              onChanged: (value) =>
                  update(settings.copyWith(pointerCaptureMode: value)),
            ),
          ),
          _toggle(
            'Keyboard capture without pointer lock',
            settings.keyboardCaptureWithoutPointerLock,
            (value) => update(
              settings.copyWith(keyboardCaptureWithoutPointerLock: value),
            ),
            description:
                'Lets a physical keyboard control the host even when no mouse is captured.',
          ),
          MoonlightSettingOption(
            title: 'Stop-stream controller shortcut',
            description:
                'Standard: Back + Start + LB + RB. Simplified: Back + Start.',
            control: TvChoiceControl<ControllerShortcutPreset>(
              value: settings.stopControllerShortcut,
              choices: const [
                ChoiceItem(
                  value: ControllerShortcutPreset.standard,
                  label: 'Standard',
                ),
                ChoiceItem(
                  value: ControllerShortcutPreset.simplified,
                  label: 'Simplified',
                ),
                ChoiceItem(
                  value: ControllerShortcutPreset.disabled,
                  label: 'Disabled',
                ),
              ],
              onChanged: (value) =>
                  update(settings.copyWith(stopControllerShortcut: value)),
            ),
          ),
          MoonlightSettingOption(
            title: 'Statistics controller shortcut',
            description: 'Standard: Back + LB + RB + X. Simplified: Back + X.',
            control: TvChoiceControl<ControllerShortcutPreset>(
              value: settings.statsControllerShortcut,
              choices: const [
                ChoiceItem(
                  value: ControllerShortcutPreset.standard,
                  label: 'Standard',
                ),
                ChoiceItem(
                  value: ControllerShortcutPreset.simplified,
                  label: 'Simplified',
                ),
                ChoiceItem(
                  value: ControllerShortcutPreset.disabled,
                  label: 'Disabled',
                ),
              ],
              onChanged: (value) =>
                  update(settings.copyWith(statsControllerShortcut: value)),
            ),
          ),
          MoonlightSettingOption(
            title: 'Stop-stream keyboard shortcut',
            description:
                'Full: Ctrl + Alt + Shift + Q. Compact: Ctrl + Shift + Q.',
            control: TvChoiceControl<KeyboardShortcutPreset>(
              value: settings.stopKeyboardShortcut,
              choices: const [
                ChoiceItem(value: KeyboardShortcutPreset.full, label: 'Full'),
                ChoiceItem(
                  value: KeyboardShortcutPreset.compact,
                  label: 'Compact',
                ),
                ChoiceItem(
                  value: KeyboardShortcutPreset.disabled,
                  label: 'Disabled',
                ),
              ],
              onChanged: (value) =>
                  update(settings.copyWith(stopKeyboardShortcut: value)),
            ),
          ),
          MoonlightSettingOption(
            title: 'Statistics keyboard shortcut',
            description:
                'Full: Ctrl + Alt + Shift + S. Compact: Ctrl + Shift + S.',
            control: TvChoiceControl<KeyboardShortcutPreset>(
              value: settings.statsKeyboardShortcut,
              choices: const [
                ChoiceItem(value: KeyboardShortcutPreset.full, label: 'Full'),
                ChoiceItem(
                  value: KeyboardShortcutPreset.compact,
                  label: 'Compact',
                ),
                ChoiceItem(
                  value: KeyboardShortcutPreset.disabled,
                  label: 'Disabled',
                ),
              ],
              onChanged: (value) =>
                  update(settings.copyWith(statsKeyboardShortcut: value)),
            ),
          ),
          _toggle(
            'Flip A/B face buttons',
            settings.flipAbButtons,
            (value) {
              update(settings.copyWith(flipAbButtons: value));
            },
            description:
                'Used by Automatic and Custom layouts. Device-specific layout profiles take precedence.',
            controlLabel: 'Swap the A and B face buttons while streaming',
          ),
          _toggle(
            'Flip X/Y face buttons',
            settings.flipXyButtons,
            (value) {
              update(settings.copyWith(flipXyButtons: value));
            },
            description:
                'Used by Automatic and Custom layouts. Device-specific layout profiles take precedence.',
            controlLabel: 'Swap the X and Y face buttons while streaming',
          ),
          MoonlightSettingOption(
            title: 'Reset input settings',
            description:
                'Restores controller, keyboard, mouse, shortcut, and device-profile defaults.',
            control: TvActionButton(
              label: 'Reset input settings',
              icon: Icons.settings_backup_restore,
              onPressed: () => update(settings.withDefaultInputSettings()),
            ),
          ),
        ],
      ),
      SettingsCategoryViewModel(
        id: 'audio',
        label: 'Audio Settings',
        icon: Icons.volume_up,
        options: [
          MoonlightSettingOption(
            title: 'Audio backend',
            description:
                'Choose the audio output implementation. Web Audio is recommended; Native EMSS is experimental.',
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
            title: 'Audio configuration',
            description:
                'Choose 5.1 or 7.1 surround sound for home-theater systems, or Stereo for general compatibility.',
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
            description:
                'Controls the size of each Opus packet. Smaller packets reduce latency but increase network overhead. Auto uses 10 ms.',
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
              title: 'Audio jitter buffer',
              description:
                  'Controls how far ahead audio is scheduled. A larger buffer smooths network gaps but adds audio delay. The default is 100 ms.',
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
          _toggle(
            'Play audio on host',
            settings.playAudioOnHost,
            (value) {
              update(settings.copyWith(playAudioOnHost: value));
            },
            controlLabel: 'Play audio on both the computer and this device',
          ),
        ],
      ),
      SettingsCategoryViewModel(
        id: 'video',
        label: 'Video Settings',
        icon: Icons.high_quality,
        options: [
          MoonlightSettingOption(
            title: 'Video codec',
            description:
                'Newer codecs improve compression and quality, but may perform worse on lower-end devices.',
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
            'Video HDR',
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
            description:
                'Requires an HDR10-capable display, a GPU that can encode HEVC Main 10, and an HDR10-enabled game.',
            controlLabel:
                'Use high dynamic range for richer colors and enhanced contrast',
          ),
          _toggle(
            'Color range',
            settings.fullColorRange,
            (value) {
              update(settings.copyWith(fullColorRange: value));
            },
            description:
                'May lose detail in bright and dark areas if your TV does not properly display full-range video.',
            controlLabel:
                'Use full color range for more detail in dark and bright areas',
          ),
          _toggle(
            'Game mode',
            settings.gameMode,
            (value) {
              update(settings.copyWith(gameMode: value));
            },
            enabled: capabilities.supportsGameMode,
            description:
                'Enable for ultra-low latency, or disable to retain post-processing video enhancements.',
            controlLabel:
                'Use game mode for optimal streaming latency and performance',
          ),
        ],
      ),
      SettingsCategoryViewModel(
        id: 'advanced',
        label: 'Advanced Settings',
        icon: Icons.build,
        options: [
          _toggle(
            'Unlock all frame rates',
            settings.unlockAllFrameRates,
            (value) {
              update(settings.copyWith(unlockAllFrameRates: value));
            },
            description:
                'Higher frame rates can reduce latency on high-end devices, but may cause lag or instability on unsupported devices.',
            controlLabel:
                'Unlock all possible frame-rate options for this device',
          ),
          _toggle(
            'Optimize bitrate presets',
            settings.optimizeBitrate,
            (value) {
              update(
                settings.withPresetInputs(
                  optimizeBitrate: value,
                  capabilities: capabilities,
                ),
              );
            },
            description:
                'Calculates a bitrate from the selected resolution, frame rate, codec, and HDR settings.',
            controlLabel:
                'Balance stream quality, performance, and bandwidth usage',
          ),
          _toggle(
            'Connection warnings',
            settings.disableConnectionWarnings,
            (value) {
              update(settings.copyWith(disableConnectionWarnings: value));
            },
            controlLabel:
                'Disable on-screen connection warnings while streaming',
          ),
          _toggle(
            'Performance statistics',
            settings.showPerformanceStats,
            (value) {
              update(settings.copyWith(showPerformanceStats: value));
            },
            controlLabel:
                'Display real-time stream performance information while streaming',
          ),
          MoonlightSettingOption(
            title: 'TV codec profile cache',
            description:
                'Tracks codec profiles this TV has accepted or rejected during stream startup.',
            fullWidthControl: true,
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
            description:
                'Controls how much diagnostic information Moonlight stores on this TV.',
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
            fullWidthControl: true,
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
            fullWidthControl: true,
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
            description:
                'Useful if you need help navigating Moonlight with a remote, gamepad, keyboard, or mouse.',
            control: TvActionButton(
              label: 'Open navigation guide',
              icon: Icons.tv,
              onPressed: _showNavigationGuide,
            ),
          ),
          MoonlightSettingOption(
            title: 'Check for updates',
            description: 'Find out if a new application update is available.',
            control: TvActionButton(
              label: 'Check for new Moonlight updates',
              icon: Icons.system_update_alt,
              onPressed: () => unawaited(_checkForUpdates()),
            ),
          ),
          MoonlightSettingOption(
            title: 'Restart the application',
            description:
                'Restart Moonlight if you encounter an issue that may be resolved by reloading the app.',
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
    String? description,
    String? controlLabel,
  }) => MoonlightSettingOption(
    title: title,
    description: description,
    control: TvToggleControl(
      value: value,
      label: controlLabel ?? title,
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

  void _confirmExit() {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Close Moonlight?',
        message: 'Do you want to close the application?',
        confirmLabel: 'Close',
        destructive: true,
        onCancel: () => Navigator.of(dialogContext).pop(),
        onConfirm: () {
          Navigator.of(dialogContext).pop();
          if (!widget.exitApp()) {
            showMoonlightSnackBar(context, 'Closing the app is unavailable.');
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
    const supportUrl = SupportDialog.repositoryUrl;
    final qrSvg = widget.diagnosticQrSvg(supportUrl);
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => SupportDialog(
        version: '1.13.0',
        supportUrl: supportUrl,
        qrCode: qrSvg.isEmpty
            ? null
            : DiagnosticQrCode(
                svg: qrSvg,
                semanticLabel: 'Moonlight Tizen repository QR code',
              ),
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
      if (widget.page == _Page.settings) {
        final settingsState = _settingsScreenKey.currentState;
        if (settingsState != null) {
          settingsState.handleBack();
        } else {
          _goHosts();
        }
        return;
      }
      if (widget.page == _Page.stream &&
          ref.read(streamSessionProvider).phase == StreamSessionPhase.failed) {
        _recoverFromStreamError();
        return;
      }
      if (widget.page == _Page.apps) {
        _goHosts();
        return;
      }
      if (widget.page == _Page.hosts) _confirmExit();
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
      TvFocusable.move(focus, direction);
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

String _subnetDiscoveryMessage(SubnetDiscoverySummary summary) {
  final parts = <String>[];
  if (summary.addedHostCount > 0) {
    parts.add(
      '${summary.addedHostCount} new host${summary.addedHostCount == 1 ? '' : 's'}',
    );
  }
  if (summary.updatedHostCount > 0) {
    parts.add(
      '${summary.updatedHostCount} updated address${summary.updatedHostCount == 1 ? '' : 'es'}',
    );
  }
  return 'Local network scan found ${parts.join(' and ')}.';
}
