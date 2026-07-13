import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonlight_tizen_flutter/app/moonlight_app.dart';
import 'package:moonlight_tizen_flutter/domain/domain.dart';
import 'package:moonlight_tizen_flutter/state/state.dart';
import 'package:moonlight_tizen_flutter/ui/moonlight_ui.dart';

void main() {
  testWidgets('normalized controller direction enters settings options', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bundle = await createFakeOverrideBundle(const FakeStateSeed());
    final navigation = StreamController<String>.broadcast(sync: true);
    addTearDown(navigation.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: bundle.overrides,
        child: _testApp(navigationActions: navigation.stream),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<TvIconButton>(find.byKey(const ValueKey('header-settings')))
        .onPressed();
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Basic Settings');
    navigation.add('right');
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, '1280 × 720');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('only initial discovery displays the hosts loading bar', (
    tester,
  ) async {
    const host = SavedHost(
      id: 'host-1',
      hostname: 'Fake PC',
      address: '192.0.2.1',
    );
    final repository = _ControlledRepository();
    final bundle = await createFakeOverrideBundle(
      const FakeStateSeed(hosts: [host]),
      repository: repository,
    );
    final discovery = _ControlledDiscovery();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...bundle.overrides,
          subnetDiscoveryGatewayProvider.overrideWithValue(discovery),
        ],
        child: _testApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    discovery.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);

    repository.blockNextRefresh();
    tester
        .widget<TvIconButton>(find.byKey(const ValueKey('header-refresh')))
        .onPressed();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);

    repository.completeRefresh();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('successful first pairing opens the paired host apps', (
    tester,
  ) async {
    final bundle = await createFakeOverrideBundle(
      const FakeStateSeed(
        hosts: [
          SavedHost(id: 'host-1', hostname: 'Fake PC', address: '192.0.2.1'),
        ],
        appsByHost: {
          'host-1': [MoonlightApp(id: 1, title: 'Desktop')],
        },
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: bundle.overrides,
        child: MoonlightFlutterApp(
          startNativeStream: (_) async {},
          stopNativeStream: () async {},
          recoverNativeStreamSurface: () {},
          unlockAudio: () {},
          connectedGamepadMask: () => 0,
          inputDevices: () => const [],
          testRumble: (_) => false,
          navigationActions: const Stream<String>.empty(),
          checkForUpdates: () async => (version: '', notes: ''),
          restartApp: () => false,
          exitApp: () => false,
          setDiagnosticLogLevel: (_) {},
          diagnosticStatus: () => const <String, Object?>{},
          clearDiagnosticLogs: () async => const <String, Object?>{},
          startLogExport: () async => '',
          stopLogExport: () async {},
          diagnosticQrSvg: (_) => '',
          probeCodecs: (_) async => const <String, Object?>{},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pair required'), findsOneWidget);
    await tester.tap(find.text('Fake PC'));
    await tester.pumpAndSettle();

    expect(find.text('Pair required'), findsNothing);
    expect(find.text('Desktop'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);

    // Let the one-shot subnet discovery delay complete before ProviderScope
    // is disposed so the widget test does not leave a fake timer pending.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('native stream failure can recover with button and Back', (
    tester,
  ) async {
    final bundle = await createFakeOverrideBundle(
      const FakeStateSeed(
        hosts: [
          SavedHost(id: 'host-1', hostname: 'Fake PC', address: '192.0.2.1'),
        ],
        appsByHost: {
          'host-1': [
            MoonlightApp(id: 1, title: 'Desktop'),
            MoonlightApp(id: 2, title: 'Steam'),
          ],
        },
      ),
    );
    final navigation = StreamController<String>.broadcast(sync: true);
    var recoverCount = 0;
    var exitCount = 0;
    addTearDown(navigation.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: bundle.overrides,
        child: MoonlightFlutterApp(
          startNativeStream: (_) async => throw StateError('native failed'),
          stopNativeStream: () async {},
          recoverNativeStreamSurface: () => recoverCount += 1,
          unlockAudio: () {},
          connectedGamepadMask: () => 0,
          inputDevices: () => const [],
          testRumble: (_) => false,
          navigationActions: navigation.stream,
          checkForUpdates: () async => (version: '', notes: ''),
          restartApp: () => false,
          exitApp: () {
            exitCount += 1;
            return true;
          },
          setDiagnosticLogLevel: (_) {},
          diagnosticStatus: () => const <String, Object?>{},
          clearDiagnosticLogs: () async => const <String, Object?>{},
          startLogExport: () async => '',
          stopLogExport: () async {},
          diagnosticQrSvg: (_) => '',
          probeCodecs: (_) async => const <String, Object?>{},
        ),
      ),
    );
    await tester.pumpAndSettle();

    navigation.add('back');
    await tester.pumpAndSettle();
    expect(find.text('Close Moonlight?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(TvFocusable.activate(FocusManager.instance.primaryFocus), isTrue);
    await tester.pumpAndSettle();
    expect(exitCount, 0);

    navigation.add('back');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.focusInDirection(
      TraversalDirection.right,
    );
    await tester.pump();
    expect(TvFocusable.activate(FocusManager.instance.primaryFocus), isTrue);
    await tester.pumpAndSettle();
    expect(exitCount, 1);

    await tester.tap(find.text('Fake PC'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desktop'));
    await tester.pumpAndSettle();

    expect(find.text('The stream could not start'), findsOneWidget);
    expect(
      find.widgetWithText(TvActionButton, 'Back to games'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TvActionButton, 'Back to games'));
    await tester.pumpAndSettle();
    expect(find.text('Desktop'), findsOneWidget);
    expect(recoverCount, 1);

    // Use another app so this second launch exercises native recovery rather
    // than the coordinator's intentional per-app duplicate-activation guard.
    await tester.tap(find.text('Steam'));
    await tester.pumpAndSettle();
    expect(find.text('The stream could not start'), findsOneWidget);
    navigation.add('back');
    await tester.pumpAndSettle();
    expect(find.text('Desktop'), findsOneWidget);
    expect(recoverCount, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

MoonlightFlutterApp _testApp({
  Stream<String> navigationActions = const Stream<String>.empty(),
}) => MoonlightFlutterApp(
  startNativeStream: (_) async {},
  stopNativeStream: () async {},
  recoverNativeStreamSurface: () {},
  unlockAudio: () {},
  connectedGamepadMask: () => 0,
  inputDevices: () => const [],
  testRumble: (_) => false,
  navigationActions: navigationActions,
  checkForUpdates: () async => (version: '', notes: ''),
  restartApp: () => false,
  exitApp: () => false,
  setDiagnosticLogLevel: (_) {},
  diagnosticStatus: () => const <String, Object?>{},
  clearDiagnosticLogs: () async => const <String, Object?>{},
  startLogExport: () async => '',
  stopLogExport: () async {},
  diagnosticQrSvg: (_) => '',
  probeCodecs: (_) async => const <String, Object?>{},
);

final class _ControlledDiscovery implements SubnetDiscoveryGateway {
  final Completer<List<String>> _scan = Completer<List<String>>();

  void complete() => _scan.complete(const <String>[]);

  @override
  Future<List<String>> scanLocalSubnet({
    Duration timeout = const Duration(milliseconds: 1800),
  }) => _scan.future;
}

final class _ControlledRepository implements MoonlightRepository {
  Completer<void>? _refreshBlock;

  void blockNextRefresh() => _refreshBlock = Completer<void>();
  void completeRefresh() => _refreshBlock?.complete();

  @override
  Future<HostRefreshResult> refreshHost(
    SavedHost host,
    HostStatus status,
  ) async {
    final block = _refreshBlock;
    _refreshBlock = null;
    await block?.future;
    return HostRefreshResult(
      host: host,
      status: status.copyWith(
        online: true,
        paired: true,
        successfulPollCount: status.successfulPollCount + 1,
      ),
      serverInfo: ServerInfo(
        serverUid: host.id,
        hostname: host.hostname,
        paired: true,
      ),
    );
  }

  @override
  Future<List<MoonlightApp>> getAppList(
    SavedHost host,
    HostStatus status,
  ) async => const <MoonlightApp>[];

  @override
  Future<Uint8List> getBoxArt(
    SavedHost host,
    HostStatus status,
    int appId,
  ) async => Uint8List(0);

  @override
  Future<PairingResult> pair(
    SavedHost host,
    HostStatus status,
    String pin,
  ) async => PairingResult(host: host, status: status, paired: true);

  @override
  Future<SavedHost> updateExternalAddress(SavedHost host) async => host;

  @override
  Future<void> wake(SavedHost host) async {}

  @override
  Future<LaunchResult> launch(
    SavedHost host,
    HostStatus status,
    HostLaunchRequest request,
  ) async => const LaunchResult(statusCode: 200, statusMessage: 'OK');

  @override
  Future<LaunchResult> resume(
    SavedHost host,
    HostStatus status,
    HostLaunchRequest request,
  ) async => const LaunchResult(statusCode: 200, statusMessage: 'OK');

  @override
  Future<void> cancel(SavedHost host, HostStatus status) async {}
}
