import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('hosts use five columns at the TV reference width', (
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
    expect(delegate.crossAxisCount, 5);
    expect(find.text('ADD HOST'), findsOneWidget);

    await tester.tap(find.text('Gaming PC'));
    expect(selected?.id, 'one');
  });

  testWidgets('apps use six columns and preserve the running state', (
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
    expect(delegate.crossAxisCount, 6);
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

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Second');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activated, 'second');
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
}
