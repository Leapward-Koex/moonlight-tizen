import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/apps_screen.dart';
import '../screens/hosts_screen.dart';
import '../screens/settings_screen.dart';
import '../theme/moonlight_theme.dart';
import '../view_models.dart';
import '../widgets/diagnostics.dart';
import '../widgets/moonlight_dialog.dart';
import '../widgets/moonlight_shell.dart';
import '../widgets/settings_controls.dart';
import '../widgets/snackbar.dart';
import '../widgets/support_dialogs.dart';
import '../widgets/tv_focusable.dart';

enum FakeUiScenario {
  happyPath('Happy path'),
  offlineHost('Offline hosts'),
  pairingFailure('Pairing failure'),
  emptyApps('Empty app list'),
  appListError('App list error'),
  launchFailure('Launch failure'),
  streamWarnings('Stream warning'),
  streamStatistics('Stream statistics'),
  streamTerminated('Stream terminated');

  const FakeUiScenario(this.label);
  final String label;
}

class FakeMoonlightApp extends StatelessWidget {
  const FakeMoonlightApp({
    super.key,
    this.initialScenario = FakeUiScenario.happyPath,
    this.showScenarioSwitcher = true,
  });

  final FakeUiScenario initialScenario;
  final bool showScenarioSwitcher;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moonlight Flutter — Browser Harness',
      debugShowCheckedModeBanner: false,
      theme: buildMoonlightTheme(),
      home: FakeMoonlightExperience(
        initialScenario: initialScenario,
        showScenarioSwitcher: showScenarioSwitcher,
      ),
    );
  }
}

enum _FakePage { hosts, apps, settings, stream }

class FakeMoonlightExperience extends StatefulWidget {
  const FakeMoonlightExperience({
    super.key,
    this.initialScenario = FakeUiScenario.happyPath,
    this.showScenarioSwitcher = true,
  });

  final FakeUiScenario initialScenario;
  final bool showScenarioSwitcher;

  @override
  State<FakeMoonlightExperience> createState() =>
      _FakeMoonlightExperienceState();
}

class _FakeMoonlightExperienceState extends State<FakeMoonlightExperience> {
  late FakeUiScenario _scenario;
  _FakePage _page = _FakePage.hosts;
  String? _settingsCategory = 'basic';
  bool _framePacing = false;
  bool _rumble = true;
  bool _showStats = false;
  String _resolution = '1280 × 720 (720p)';
  double _bitrate = 10;

  static const _host = HostTileViewModel(
    id: 'fake-gaming-pc',
    name: 'Living Room PC',
    address: '192.168.1.42',
    availability: HostAvailability.online,
    isPaired: true,
    subtitle: 'Online',
  );

  @override
  void initState() {
    super.initState();
    _scenario = widget.initialScenario;
  }

  List<HeaderActionViewModel> get _hostActions => [
    HeaderActionViewModel(
      id: 'settings',
      label: 'Settings',
      icon: Icons.settings,
      onPressed: () => setState(() => _page = _FakePage.settings),
    ),
    HeaderActionViewModel(
      id: 'support',
      label: 'Support',
      icon: Icons.help,
      onPressed: _showSupport,
    ),
    if (widget.showScenarioSwitcher)
      HeaderActionViewModel(
        id: 'scenario',
        label: 'Fake scenario',
        icon: Icons.science_outlined,
        badge: 'FAKE',
        onPressed: _selectScenario,
      ),
  ];

  List<HostTileViewModel> get _hosts {
    if (_scenario == FakeUiScenario.offlineHost) {
      return const [
        HostTileViewModel(
          id: 'fake-gaming-pc',
          name: 'Living Room PC',
          address: '192.168.1.42',
          availability: HostAvailability.offline,
          isPaired: true,
          subtitle: 'Offline',
        ),
      ];
    }
    return const [
      _host,
      HostTileViewModel(
        id: 'fake-office-pc',
        name: 'Office Workstation With A Deliberately Long Name',
        address: '192.168.1.60',
        availability: HostAvailability.offline,
        subtitle: 'Offline',
      ),
    ];
  }

  List<AppTileViewModel> get _apps => const [
    AppTileViewModel(id: 'desktop', title: 'Desktop'),
    AppTileViewModel(id: 'steam', title: 'Steam Big Picture'),
    AppTileViewModel(id: 'game-1', title: 'Adventure Game'),
    AppTileViewModel(id: 'game-2', title: 'Racing Game', isRunning: true),
    AppTileViewModel(id: 'game-3', title: 'Puzzle Collection'),
    AppTileViewModel(id: 'game-4', title: 'Retro Arcade'),
    AppTileViewModel(id: 'game-5', title: 'Co-op Game'),
  ];

  @override
  Widget build(BuildContext context) {
    return switch (_page) {
      _FakePage.hosts => HostsScreen(
        hosts: _hosts,
        headerActions: _hostActions,
        onAddHost: _showAddHost,
        onHostSelected: _openHost,
        onHostMenu: _showHostMenu,
      ),
      _FakePage.apps => AppsScreen(
        hostName: _host.name,
        apps: _scenario == FakeUiScenario.emptyApps ? const [] : _apps,
        error: _scenario == FakeUiScenario.appListError
            ? 'The fake host returned malformed XML.'
            : null,
        onRetry: () =>
            showMoonlightSnackBar(context, 'Fake app list refreshed.'),
        onBack: () => setState(() => _page = _FakePage.hosts),
        onAppSelected: _launchApp,
        headerActions: [
          HeaderActionViewModel(
            id: 'quit',
            label: 'Quit running app',
            icon: Icons.highlight_off,
            onPressed: () => _showConfirm(
              title: 'Quit running app?',
              message: 'This ends the application on the fake host.',
            ),
          ),
        ],
      ),
      _FakePage.settings => SettingsScreen(
        categories: _settingsCategories(),
        selectedCategoryId: _settingsCategory,
        onCategorySelected: (id) => setState(() => _settingsCategory = id),
        onBack: () => setState(() => _page = _FakePage.hosts),
        headerActions: [
          HeaderActionViewModel(
            id: 'restore',
            label: 'Restore defaults',
            icon: Icons.settings_backup_restore,
            onPressed: () => _showConfirm(
              title: 'Restore default settings?',
              message: 'All fake settings will return to their defaults.',
            ),
          ),
        ],
      ),
      _FakePage.stream => _buildFakeStream(),
    };
  }

  Widget _buildFakeStream() {
    final warning = _scenario == FakeUiScenario.streamWarnings
        ? 'Slow connection to PC\nReduce your bitrate'
        : null;
    final statistics =
        _scenario == FakeUiScenario.streamStatistics || _showStats
        ? 'Resolution: 1920 × 1080\nFPS: 59.94\nNetwork latency: 3 ms\nDecode: 4.2 ms'
        : null;
    return MoonlightShell(
      title: 'Fake stream',
      showHeader: false,
      overlay: StreamStatusOverlay(
        warning: warning,
        statistics: statistics,
        message: _scenario == FakeUiScenario.streamTerminated
            ? 'The fake stream was terminated by the host.'
            : null,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [Color(0xFF324F65), Color(0xFF070A0D)],
                radius: 1.2,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.videogame_asset,
                size: 170,
                color: Color(0x445CCEEA),
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 32,
            child: SizedBox(
              width: 250,
              child: TvActionButton(
                label: 'Stop fake stream',
                icon: Icons.stop,
                autofocus: true,
                onPressed: () => setState(() => _page = _FakePage.apps),
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            right: 32,
            child: SizedBox(
              width: 250,
              child: TvActionButton(
                label: 'Toggle statistics',
                icon: Icons.query_stats,
                onPressed: () => setState(() => _showStats = !_showStats),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<SettingsCategoryViewModel> _settingsCategories() => [
    SettingsCategoryViewModel(
      id: 'basic',
      label: 'Basic Settings',
      icon: Icons.tune,
      options: [
        MoonlightSettingOption(
          title: 'Video resolution',
          description:
              'Increase image clarity or reduce it for lower-end devices and slower networks.',
          control: TvChoiceControl<String>(
            value: _resolution,
            choices: const [
              ChoiceItem(
                value: '1280 × 720 (720p)',
                label: '1280 × 720 (720p)',
              ),
              ChoiceItem(
                value: '1920 × 1080 (1080p)',
                label: '1920 × 1080 (1080p)',
              ),
              ChoiceItem(value: '3840 × 2160 (4K)', label: '3840 × 2160 (4K)'),
            ],
            onChanged: (value) => setState(() => _resolution = value),
          ),
        ),
        MoonlightSettingOption(
          title: 'Video bitrate',
          description:
              'Increase for image quality or reduce for slower connections.',
          control: TvSliderControl(
            value: _bitrate,
            min: .5,
            max: 150,
            step: .5,
            valueLabel: (value) => '${value.toStringAsFixed(1)} Mbps',
            onChanged: (value) => setState(() => _bitrate = value),
          ),
        ),
        MoonlightSettingOption(
          title: 'Video frame pacing',
          control: TvToggleControl(
            value: _framePacing,
            label: 'Balance video latency and smoothness',
            onChanged: (value) => setState(() => _framePacing = value),
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
          title: 'Rumble feedback',
          control: TvToggleControl(
            value: _rumble,
            label: 'Allow gamepad rumble feedback while streaming',
            onChanged: (value) => setState(() => _rumble = value),
          ),
        ),
      ],
    ),
    SettingsCategoryViewModel(
      id: 'about',
      label: 'About',
      icon: Icons.info,
      options: [
        MoonlightSettingOption(
          title: 'System information',
          control: const SettingInfoPanel(
            entries: [
              SystemInfoEntry(
                'Application',
                'Moonlight Flutter browser harness',
              ),
              SystemInfoEntry('Platform', 'Browser fake (no Tizen APIs)'),
              SystemInfoEntry('Native runtime', 'Stubbed'),
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
      ],
    ),
  ];

  void _openHost(HostTileViewModel host) {
    if (!host.isOnline) {
      showMoonlightSnackBar(context, '${host.name} is offline.');
      return;
    }
    setState(() => _page = _FakePage.apps);
  }

  void _launchApp(AppTileViewModel app) {
    if (_scenario == FakeUiScenario.launchFailure) {
      showMoonlightSnackBar(context, 'The fake host rejected ${app.title}.');
      return;
    }
    setState(() => _page = _FakePage.stream);
  }

  void _showAddHost() {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => AddHostDialog(
        onCancel: () => Navigator.of(dialogContext).pop(),
        onSubmit: (address) {
          Navigator.of(dialogContext).pop();
          _showPairing(address);
        },
      ),
    );
  }

  void _showPairing(String address) {
    late BuildContext pairingContext;
    showMoonlightDialog<void>(
      context: context,
      builder: (context) {
        pairingContext = context;
        return PairingDialog(
          pin: '4821',
          hostName: address,
          onCancel: () => Navigator.of(context).pop(),
        );
      },
    );
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!pairingContext.mounted) return;
        Navigator.of(pairingContext).pop();
        if (!mounted) return;
        final failed = _scenario == FakeUiScenario.pairingFailure;
        showMoonlightSnackBar(
          context,
          failed ? 'Fake pairing failed.' : 'Fake host paired successfully.',
        );
      }),
    );
  }

  void _showHostMenu(HostTileViewModel host) {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => HostMenuDialog(
        host: host,
        wakeEnabled: !host.isOnline,
        onWake: () {
          Navigator.of(dialogContext).pop();
          showMoonlightSnackBar(context, 'Fake Wake-on-LAN packet sent.');
        },
        onDetails: () {
          Navigator.of(dialogContext).pop();
          _showHostDetails(host);
        },
        onDelete: () {
          Navigator.of(dialogContext).pop();
          _showConfirm(
            title: 'Remove ${host.name}?',
            message: 'This only changes the in-memory browser harness.',
          );
        },
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  void _showHostDetails(HostTileViewModel host) {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => HostDetailsDialog(
        hostName: host.name,
        details: [
          SystemInfoEntry('Address', host.address ?? 'Unknown'),
          SystemInfoEntry('State', host.availability.name),
          SystemInfoEntry('Paired', host.isPaired ? 'Yes' : 'No'),
        ],
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  void _showSupport() {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => SupportDialog(
        version: 'browser fake',
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

  void _showConfirm({required String title, required String message}) {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: title,
        message: message,
        onCancel: () => Navigator.of(dialogContext).pop(),
        onConfirm: () {
          Navigator.of(dialogContext).pop();
          showMoonlightSnackBar(context, 'Fake action completed.');
        },
      ),
    );
  }

  void _selectScenario() {
    showMoonlightDialog<void>(
      context: context,
      builder: (dialogContext) => MoonlightDialog(
        title: 'Browser Harness Scenario',
        icon: Icons.science_outlined,
        // Kept beside the title to make this large scenario body readable.
        // ignore: sort_child_properties_last
        child: TvFocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final scenario in FakeUiScenario.values) ...[
                TvActionButton(
                  label: scenario.label,
                  icon: scenario == _scenario
                      ? Icons.check
                      : Icons.chevron_right,
                  autofocus: scenario == _scenario,
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    setState(() {
                      _scenario = scenario;
                      _page = _FakePage.hosts;
                    });
                  },
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        actions: [
          MoonlightDialogAction(
            label: 'Close',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }
}
