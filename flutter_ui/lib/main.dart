import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
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

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const MoonlightFlutterApp(),
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
