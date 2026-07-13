import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonlight_tizen_flutter/app/moonlight_app.dart';
import 'package:moonlight_tizen_flutter/domain/domain.dart';
import 'package:moonlight_tizen_flutter/state/state.dart';
import 'package:moonlight_tizen_flutter/ui/moonlight_ui.dart';

void main() {
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
