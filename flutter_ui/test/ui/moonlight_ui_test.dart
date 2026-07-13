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

  testWidgets('unknown host status does not claim pairing is required', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        HostsScreen(
          hosts: const [
            HostTileViewModel(
              id: 'saved',
              name: 'Saved PC',
              pairingStatusKnown: false,
            ),
          ],
          onAddHost: () {},
          onHostSelected: (_) {},
        ),
      ),
    );

    expect(find.bySemanticsLabel('Saved PC, Status unknown'), findsOneWidget);
    expect(find.text('Pair required'), findsNothing);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.sync), findsOneWidget);

    await tester.pumpWidget(
      themed(
        HostsScreen(
          hosts: const [
            HostTileViewModel(
              id: 'saved',
              name: 'Saved PC',
              availability: HostAvailability.online,
            ),
          ],
          onAddHost: () {},
          onHostSelected: (_) {},
        ),
      ),
    );
    expect(find.text('Pair required'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
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

  testWidgets('offscreen TV focus scrolls smoothly with trailing space', (
    tester,
  ) async {
    setViewport(tester, const Size(800, 300));
    final controller = ScrollController();
    final nodes = List.generate(8, (index) => FocusNode(debugLabel: '$index'));
    addTearDown(() {
      controller.dispose();
      for (final node in nodes) {
        node.dispose();
      }
    });

    await tester.pumpWidget(
      themed(
        Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              key: const Key('focus-scroll-viewport'),
              height: 240,
              child: SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.only(bottom: 100),
                child: Column(
                  children: List.generate(
                    nodes.length,
                    (index) => SizedBox(
                      key: Key('focus-item-$index'),
                      height: 64,
                      child: TvFocusable(
                        focusNode: nodes[index],
                        autofocus: index == 0,
                        onActivate: () {},
                        builder: (context, focused) => Text('Item $index'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    nodes[1].requestFocus();
    await tester.pumpAndSettle();
    expect(controller.offset, 0, reason: 'visible controls should stay put');

    nodes[7].requestFocus();
    await tester.pump();
    expect(controller.offset, 0, reason: 'focus scrolling should animate');
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, greaterThan(0));
    expect(controller.offset, lessThan(controller.position.maxScrollExtent));
    await tester.pumpAndSettle();

    final viewportBottom = tester
        .getBottomLeft(find.byKey(const Key('focus-scroll-viewport')))
        .dy;
    final focusedBottom = tester
        .getBottomLeft(find.byKey(const Key('focus-item-7')))
        .dy;
    expect(viewportBottom - focusedBottom, greaterThan(24));
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
    final settingsKey = GlobalKey<SettingsScreenState>();
    String? selected;
    var backCount = 0;
    await tester.pumpWidget(
      themed(
        StatefulBuilder(
          builder: (context, setState) => SettingsScreen(
            key: settingsKey,
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
            onBack: () => backCount += 1,
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

    settingsKey.currentState!.handleBack();
    await tester.pumpAndSettle();
    expect(find.text('Video resolution'), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Basic Settings');
    expect(backCount, 0);

    settingsKey.currentState!.handleBack();
    expect(backCount, 1);
  });

  testWidgets('wide settings give the selected category remote focus', (
    tester,
  ) async {
    setViewport(tester, const Size(1600, 900));
    final settingsKey = GlobalKey<SettingsScreenState>();
    String? selected = 'basic';
    var backCount = 0;
    await tester.pumpWidget(
      themed(
        StatefulBuilder(
          builder: (context, setState) => SettingsScreen(
            key: settingsKey,
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
            onBack: () => backCount += 1,
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

    settingsKey.currentState!.handleBack();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Basic Settings');
    expect(backCount, 0);

    settingsKey.currentState!.handleBack();
    expect(backCount, 1);
  });

  testWidgets('controller direction enters the settings options pane', (
    tester,
  ) async {
    setViewport(tester, const Size(1600, 900));
    await tester.pumpWidget(
      themed(
        SettingsScreen(
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
          selectedCategoryId: 'basic',
          onCategorySelected: (_) {},
          onBack: () {},
        ),
      ),
    );
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Basic Settings');
    expect(
      TvFocusable.move(
        FocusManager.instance.primaryFocus,
        TraversalDirection.right,
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, '1280 × 720');
  });

  testWidgets('launching app card retains focus', (tester) async {
    setViewport(tester, const Size(1280, 720));
    var launching = false;
    late StateSetter update;
    await tester.pumpWidget(
      themed(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return AppsScreen(
              hostName: 'Gaming PC',
              apps: [
                AppTileViewModel(
                  id: 'desktop',
                  title: 'Desktop',
                  isLoading: launching,
                ),
                const AppTileViewModel(id: 'steam', title: 'Steam'),
              ],
              onAppSelected: (_) {},
              onBack: () {},
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Desktop');

    update(() => launching = true);
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Desktop');
  });

  testWidgets('settings options reserve snackbar-safe trailing scroll space', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        SettingsOptionsPane(
          category: SettingsCategoryViewModel(
            id: 'advanced',
            label: 'Advanced',
            icon: Icons.build,
            options: [
              MoonlightSettingOption(
                title: 'Last option',
                control: TvActionButton(label: 'Change', onPressed: () {}),
              ),
            ],
          ),
        ),
      ),
    );

    final list = tester.widget<ListView>(
      find.byKey(const PageStorageKey('settings-options-advanced')),
    );
    final padding = list.padding! as EdgeInsets;
    expect(padding.bottom, greaterThanOrEqualTo(152));
  });
}
