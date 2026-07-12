import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/moonlight_app.dart';
import 'data/native/moonlight_native.dart';
import 'data/native/production_native.dart';
import 'data/persistence/persistent_state_store.dart';
import 'data/persistence/persistent_box_art_cache.dart';
import 'domain/domain.dart';
import 'state/state.dart';
import 'ui/moonlight_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MoonlightNativeRuntime? runtime;
  try {
    runtime = createMoonlightNativeRuntime();
    runtime.logDiagnostic('info', 'app.bootstrap.started', {
      'appVersion': '1.13.0',
      'packageId': 'MLFlutter1',
      'applicationId': 'MLFlutter1.MoonlightFlutter',
    });
    _installGlobalErrorLogging(runtime);
    final storage = await TizenPrivateFilePersistentStateStore.open();
    runtime.logDiagnostic('info', 'app.persistence.opened', {
      'backend': 'tizen-private-file',
    });
    final savedIdentity = await _readIdentity(storage);
    final native = await createNativeProductionBundle(
      identity: savedIdentity,
      boxArtCache: await openPersistentBoxArtCache(),
      runtime: runtime,
    );
    native.runtime.logDiagnostic('info', 'app.bootstrap.native_ready', {
      'generatedIdentity': native.generatedIdentity,
      'bridgeVersion': native.runtimeInfo.bridgeVersion,
      'platform': native.capabilities.platform,
      'platformVersion': native.capabilities.platformVersion,
      'maxWidth': native.capabilities.maxWidth,
      'maxHeight': native.capabilities.maxHeight,
      'supportsHdr': native.capabilities.supportsHdr,
      'supportsGameMode': native.capabilities.supportsGameMode,
      'supportsRumble': native.capabilities.supportsRumble,
      'supportedCodecs': native.capabilities.supportedCodecs
          .map((codec) => codec.wireName)
          .toList(growable: false),
    });
    final container = ProviderContainer(
      observers: [DiagnosticProviderObserver(native.runtime)],
      overrides: [
        persistentStateStoreProvider.overrideWith((ref) async => storage),
        ...native.overrides,
      ],
    );
    container
        .read(clientIdentityStateProvider.notifier)
        .setIdentity(native.identity);

    native.runtime.events.listen(
      container.read(streamSessionProvider.notifier).applyEvent,
      onError: (Object error, StackTrace stackTrace) {
        container
            .read(streamSessionProvider.notifier)
            .fail(
              MoonlightRuntimeError(code: 'native-event', message: '$error'),
            );
      },
    );
    native.runtime.inputEvents.listen(
      (event) => _handleNativeInput(native.runtime, event),
    );

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: MoonlightFlutterApp(
          unlockAudio: native.runtime.unlockAudio,
          connectedGamepadMask: native.runtime.connectedGamepadMask,
          inputDevices: native.runtime.inputDevices,
          testRumble: native.runtime.testRumble,
          navigationActions: native.runtime.inputEvents
              .where(
                (event) => event.type == 'action' && event.phase != 'released',
              )
              .map((event) => event.action),
          checkForUpdates: () => _checkForUpdates(native.runtime),
          restartApp: native.runtime.restartApp,
          setDiagnosticLogLevel: (level) =>
              native.runtime.setDiagnosticLogLevel(level.name),
          diagnosticStatus: native.runtime.diagnosticLogStatus,
          clearDiagnosticLogs: native.runtime.clearDiagnosticLogs,
          startLogExport: () => _startLogExport(native.runtime),
          stopLogExport: native.runtime.stopLogExportServer,
          diagnosticQrSvg: native.runtime.diagnosticQrSvg,
          probeCodecs: native.runtime.probeVideoCodecSupport,
          startNativeStream: (request) async {
            final event = await native.runtime.startStream(request);
            container.read(streamSessionProvider.notifier).applyEvent(event);
          },
          stopNativeStream: native.runtime.stopStream,
        ),
      ),
    );
    native.runtime.logDiagnostic('info', 'app.bootstrap.ui_started');
  } catch (error, stackTrace) {
    runtime?.logDiagnostic('error', 'app.bootstrap.failed', {
      'errorType': error.runtimeType.toString(),
      'error': error.toString(),
      'stack': stackTrace.toString(),
    });
    runApp(_StartupFailureApp(error: error));
  }
}

final class DiagnosticProviderObserver extends ProviderObserver {
  const DiagnosticProviderObserver(this.runtime);

  final MoonlightNativeRuntime runtime;

  String _providerName(ProviderObserverContext context) =>
      context.provider.name ?? context.provider.runtimeType.toString();

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    runtime.logDiagnostic('error', 'riverpod.provider_failed', {
      'provider': _providerName(context),
      'errorType': error.runtimeType.toString(),
      'error': error.toString(),
      'stack': stackTrace.toString(),
    });
  }

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    runtime.logDiagnostic('debug', 'riverpod.provider_updated', {
      'provider': _providerName(context),
      'previousType': previousValue.runtimeType.toString(),
      'newType': newValue.runtimeType.toString(),
    });
  }
}

void _installGlobalErrorLogging(MoonlightNativeRuntime runtime) {
  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    runtime.logDiagnostic('error', 'flutter.framework_error', {
      'exceptionType': details.exception.runtimeType.toString(),
      'exception': details.exceptionAsString(),
      'library': details.library,
      'context': details.context?.toDescription(),
      'stack': details.stack?.toString() ?? '',
    });
    if (previousFlutterHandler != null) {
      previousFlutterHandler(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    runtime.logDiagnostic('error', 'flutter.unhandled_error', {
      'errorType': error.runtimeType.toString(),
      'error': error.toString(),
      'stack': stackTrace.toString(),
    });
    return true;
  };
}

Future<({String version, String notes})> _checkForUpdates(
  MoonlightNativeRuntime runtime,
) async {
  final response = await runtime.openText(
    Uri.https(
      'api.github.com',
      '/repos/Leapward-Koex/moonlight-tizen/releases/latest',
    ),
  );
  final json = (jsonDecode(response) as Map).cast<String, Object?>();
  return (
    version: '${json['tag_name'] ?? json['name'] ?? 'Unknown'}',
    notes: '${json['body'] ?? 'No release notes were provided.'}',
  );
}

Future<String> _startLogExport(MoonlightNativeRuntime runtime) async {
  runtime.logDiagnostic('info', 'diagnostics.export_started', {
    'status': runtime.diagnosticLogStatus(),
  });
  final logs = await runtime.diagnosticLogs();
  if (logs.isEmpty) {
    throw StateError('No diagnostic logs are available.');
  }
  final payload =
      '${jsonEncode({
        'time': DateTime.now().toUtc().toIso8601String(),
        'level': 'info',
        'message': 'Moonlight Flutter diagnostic bundle',
        'meta': {'appVersion': '1.13.0', 'packageId': 'MLFlutter1', 'applicationId': 'MLFlutter1.MoonlightFlutter', 'logStatus': runtime.diagnosticLogStatus()},
      })}\n$logs';
  final token = List<int>.generate(
    16,
    (_) => Random.secure().nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  final result = await runtime.startLogExportServer(
    payload: payload,
    filename: 'moonlight-flutter-diagnostics.log',
    token: token,
  );
  final ipAddress = runtime.getIpAddress();
  final port = result['port'];
  final path = result['path'];
  if (ipAddress.isEmpty || port == null || path == null) {
    await runtime.stopLogExportServer();
    throw StateError('The TV network address is unavailable.');
  }
  return 'http://$ipAddress:$port$path';
}

Future<ClientIdentity?> _readIdentity(PersistentStateStore storage) async {
  try {
    final source = await storage.backend.read('clientIdentity.v1');
    if (source == null) return null;
    final envelope = (jsonDecode(source) as Map).cast<String, Object?>();
    final data = envelope['data'];
    if (data is! String || data.isEmpty) return null;
    final decoded = jsonDecode(data);
    return decoded is Map
        ? ClientIdentity.fromJson(decoded.cast<String, Object?>())
        : null;
  } catch (_) {
    return null;
  }
}

void _handleNativeInput(
  MoonlightNativeRuntime runtime,
  NativeInputEvent event,
) {
  if (event.type != 'action' || event.phase == 'released') return;
  if (event.action == 'stop') {
    unawaited(runtime.stopStream());
    return;
  }
  if (event.action == 'toggleStats') {
    unawaited(runtime.toggleStats());
    return;
  }
  final keys = switch (event.action) {
    'up' => (PhysicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowUp),
    'down' => (PhysicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowDown),
    'left' => (PhysicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowLeft),
    'right' => (PhysicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowRight),
    'accept' => (PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter),
    'back' => (PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape),
    _ => null,
  };
  if (keys == null) return;
  final timeStamp = Duration(
    microseconds: DateTime.now().microsecondsSinceEpoch,
  );
  HardwareKeyboard.instance.handleKeyEvent(
    KeyDownEvent(
      physicalKey: keys.$1,
      logicalKey: keys.$2,
      timeStamp: timeStamp,
    ),
  );
  HardwareKeyboard.instance.handleKeyEvent(
    KeyUpEvent(physicalKey: keys.$1, logicalKey: keys.$2, timeStamp: timeStamp),
  );
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Moonlight Flutter',
    debugShowCheckedModeBanner: false,
    theme: buildMoonlightTheme(),
    home: StartupScreen(error: 'Native startup failed: $error'),
  );
}
