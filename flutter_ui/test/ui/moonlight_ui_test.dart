import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonlight_tizen_flutter/data/native/native_runtime.dart';
import 'package:moonlight_tizen_flutter/domain/app_settings.dart';
import 'package:moonlight_tizen_flutter/ui/moonlight_ui.dart';

void main() {
  Widget themed(Widget child) {
    return MaterialApp(theme: buildMoonlightTheme(), home: child);
  }

  void setViewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
  }

  testWidgets('hosts use four TV-scale columns at the reference width', (
    tester,
  ) async {
    setViewport(tester, const Size(1920, 1080));
    HostTileViewModel? selected;
    await tester.pumpWidget(
      themed(
        HostsScreen(
          hosts: const [
            HostTileViewModel(
              id: 'one',
              name: 'Gaming PC',
              availability: HostAvailability.online,
              isPaired: true,
            ),
          ],
          onAddHost: () {},
          onHostSelected: (host) => selected = host,
        ),
      ),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);
    expect(find.text('Add host'), findsOneWidget);
    final addHostSize = tester.getSize(find.byType(AddHostCard));
    expect(addHostSize.width, greaterThan(350));
    expect(addHostSize.height, greaterThan(350));

    await tester.tap(find.text('Gaming PC'));
    expect(selected?.id, 'one');
  });

  testWidgets('input device panel shows live state and tests rumble', (
    tester,
  ) async {
    setViewport(tester, const Size(1280, 720));
    var rumbleIndex = -1;
    final device = NativeInputDevice(
      slot: 0,
      browserIndex: 2,
      fingerprint: 'deadbeef',
      id: 'Test Controller',
      mapping: 'standard',
      buttonCount: 17,
      axisCount: 4,
      supportsRumble: true,
      pressedButtons: const [0, 9],
      axes: const [.25, -.5, 0, 1],
    );
    await tester.pumpWidget(
      themed(
        Scaffold(
          body: SingleChildScrollView(
            child: InputDevicesControl(
              devicesReader: () => [device],
              defaultLayout: ControllerLayout.xbox,
              profiles: const {'deadbeef': ControllerLayout.nintendo},
              onLayoutChanged: (_, _) {},
              onResetDevice: (_) {},
              onTestRumble: (index) => rumbleIndex = index,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Player 1: Test Controller'), findsOneWidget);
    expect(find.textContaining('buttons 0, 9'), findsOneWidget);
    expect(find.text('Default layout: xbox'), findsOneWidget);
    final rumbleButton = find.widgetWithText(TvActionButton, 'Test rumble');
    await tester.ensureVisible(rumbleButton);
    await tester.tap(rumbleButton);
    expect(rumbleIndex, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('apps use five TV-scale columns and preserve the running state', (
    tester,
  ) async {
    setViewport(tester, const Size(1920, 1080));
    await tester.pumpWidget(
      themed(
        AppsScreen(
          hostName: 'Gaming PC',
          apps: const [
            AppTileViewModel(id: 'desktop', title: 'Desktop', isRunning: true),
          ],
          onAppSelected: (_) {},
          onBack: () {},
        ),
      ),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 5);
    expect(find.bySemanticsLabel('Desktop, running'), findsOneWidget);
  });

  testWidgets('arrow keys move focus and Enter activates a TV control', (
    tester,
  ) async {
    setViewport(tester, const Size(900, 400));
    var activated = '';
    await tester.pumpWidget(
      themed(
        Scaffold(
          body: Center(
            child: TvFocusTraversalGroup(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    child: TvActionButton(
                      label: 'First',
                      autofocus: true,
                      onPressed: () => activated = 'first',
                    ),
                  ),
                  const SizedBox(width: 40),
                  SizedBox(
                    width: 220,
                    child: TvActionButton(
                      label: 'Second',
                      onPressed: () => activated = 'second',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'First');
    expect(tester.getSize(find.byType(TvActionButton).first).height, 64);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Second');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activated, 'second');

    activated = '';
    expect(TvFocusable.activate(FocusManager.instance.primaryFocus), isTrue);
    expect(activated, 'second');
  });

  testWidgets('dialog actions remain activatable by normalized gamepad input', (
    tester,
  ) async {
    var cancelled = false;
    await tester.pumpWidget(
      themed(
        ConfirmationDialog(
          title: 'Remove host?',
          message: 'This host will be removed.',
          onConfirm: () {},
          onCancel: () => cancelled = true,
        ),
      ),
    );
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Cancel');
    expect(TvFocusable.activate(FocusManager.instance.primaryFocus), isTrue);
    expect(cancelled, isTrue);
  });

  testWidgets('add-host field releases vertical remote focus to actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(AddHostDialog(onSubmit: (_) {}, onCancel: () {})),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('add-host-address')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Cancel');
  });

  testWidgets('narrow settings open options on a separate page', (
    tester,
  ) async {
    setViewport(tester, const Size(800, 900));
    String? selected;
    await tester.pumpWidget(
      themed(
        StatefulBuilder(
          builder: (context, setState) => SettingsScreen(
            categories: [
              SettingsCategoryViewModel(
                id: 'basic',
                label: 'Basic Settings',
                icon: Icons.tune,
                options: [
                  MoonlightSettingOption(
                    title: 'Video resolution',
                    control: TvActionButton(
                      label: '1280 × 720',
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ],
            selectedCategoryId: selected,
            onCategorySelected: (value) {
              setState(() => selected = value);
            },
            onBack: () {},
          ),
        ),
      ),
    );

    expect(find.text('Basic Settings'), findsOneWidget);
    expect(find.text('Video resolution'), findsNothing);

    await tester.tap(find.text('Basic Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Video resolution'), findsOneWidget);
    expect(find.bySemanticsLabel('Settings categories'), findsOneWidget);
  });

  testWidgets('wide settings give the selected category remote focus', (
    tester,
  ) async {
    setViewport(tester, const Size(1600, 900));
    String? selected = 'basic';
    await tester.pumpWidget(
      themed(
        StatefulBuilder(
          builder: (context, setState) => SettingsScreen(
            categories: [
              SettingsCategoryViewModel(
                id: 'basic',
                label: 'Basic Settings',
                icon: Icons.tune,
                options: [
                  MoonlightSettingOption(
                    title: 'Video resolution',
                    control: TvActionButton(
                      label: '1280 × 720',
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
              SettingsCategoryViewModel(
                id: 'input',
                label: 'Input Settings',
                icon: Icons.gamepad,
                options: [
                  MoonlightSettingOption(
                    title: 'Rumble',
                    control: TvActionButton(label: 'Enabled', onPressed: () {}),
                  ),
                ],
              ),
            ],
            selectedCategoryId: selected,
            onCategorySelected: (value) {
              setState(() => selected = value);
            },
            onBack: () {},
            headerActions: [
              HeaderActionViewModel(
                id: 'refresh',
                label: 'Refresh settings',
                icon: Icons.refresh,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Basic Settings');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Input Settings');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'input');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Basic Settings');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'basic');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, '1280 × 720');
  });
}
