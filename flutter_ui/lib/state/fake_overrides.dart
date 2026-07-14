import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:flutter_riverpod/misc.dart';

import '../data/fakes/fake_moonlight_repository.dart';
import '../data/native/native_runtime.dart';
import '../data/native/production_native.dart';
import '../data/persistence/persistent_state_store.dart';
import '../domain/domain.dart';
import 'app_state.dart';

final class FakeStateSeed {
  const FakeStateSeed({
    this.settings,
    this.hosts = const <SavedHost>[],
    this.appsByHost = const <String, List<MoonlightApp>>{},
    this.capabilities,
    this.offlineHostIds = const <String>{},
    this.pairingFails = false,
    this.launchFails = false,
  });

  final AppSettings? settings;
  final List<SavedHost> hosts;
  final Map<String, List<MoonlightApp>> appsByHost;
  final PlatformCapabilities? capabilities;
  final Set<String> offlineHostIds;
  final bool pairingFails;
  final bool launchFails;
}

final class FakeOverrideBundle {
  const FakeOverrideBundle({required this.overrides, required this.storage});
  final List<Override> overrides;
  final InMemoryPersistentStateStore storage;
}

/// Deterministic substitute for the Tizen JavaScript bridge.
///
/// Browser runs and widget tests override the same provider as production, so
/// no screen reaches the real TV runtime, network, or filesystem directly.
final class FakeMoonlightNativeRuntime implements MoonlightNativeRuntime {
  FakeMoonlightNativeRuntime({
    Stream<StreamEvent>? events,
    Stream<NativeInputEvent>? inputEvents,
    this.startStreamError,
    this.onStartStream,
    this.onRecoverStreamSurface,
    this.onExitApp,
    this.onStartSyntheticAudioTest,
    this.onPlaySyntheticAudioClick,
    this.onStopSyntheticAudioTest,
    this.onDiagnosticQrSvg,
  }) : _events = events ?? const Stream<StreamEvent>.empty(),
       _inputEvents = inputEvents ?? const Stream<NativeInputEvent>.empty();

  final Stream<StreamEvent> _events;
  final Stream<NativeInputEvent> _inputEvents;
  final Object? startStreamError;
  final Future<StreamEvent> Function(StreamRequest request)? onStartStream;
  final void Function()? onRecoverStreamSurface;
  final bool Function()? onExitApp;
  final Future<void> Function({required bool gameMode})?
  onStartSyntheticAudioTest;
  final Future<int> Function(String inputLabel)? onPlaySyntheticAudioClick;
  final Future<void> Function()? onStopSyntheticAudioTest;
  final String Function(String value)? onDiagnosticQrSvg;

  @override
  bool get isAvailable => true;

  @override
  Stream<StreamEvent> get events => _events;

  @override
  Stream<NativeInputEvent> get inputEvents => _inputEvents;

  @override
  Future<NativeRuntimeInfo> initialize() async => const NativeRuntimeInfo(
    ready: true,
    bridgeVersion: 1,
    capabilities: PlatformCapabilities(),
  );

  @override
  Future<ClientIdentity> makeCertificate({required String clientUid}) async =>
      ClientIdentity(
        clientUid: clientUid,
        certificatePem: 'fake-certificate',
        privateKeyPem: 'fake-private-key',
      );

  @override
  Future<void> httpInit(ClientIdentity identity) async {}

  @override
  Future<String> openText(Uri uri, {String? pinnedCertificate}) async =>
      '{"tag_name":"browser-fake","body":"Simulated browser data."}';

  @override
  Future<Uint8List> openBinary(Uri uri, {String? pinnedCertificate}) async =>
      Uint8List(0);

  @override
  Future<String> pair({
    required int serverMajorVersion,
    required String address,
    required int httpPort,
    required String pin,
    required String uniqueId,
  }) async => 'fake-pairing';

  @override
  Future<String?> stun() async => null;

  @override
  Future<void> wakeOnLan(String macAddress) async {}

  @override
  Future<List<String>> scanLocalSubnet({
    Duration timeout = const Duration(milliseconds: 1800),
  }) async => const <String>[];

  @override
  bool unlockAudio() => true;

  @override
  Future<StreamEvent> startStream(StreamRequest request) async {
    final callback = onStartStream;
    if (callback != null) return callback(request);
    final error = startStreamError;
    if (error != null) throw error;
    return const StreamEvent(
      kind: StreamEventKind.lifecycle,
      name: 'streaming',
    );
  }

  @override
  Future<void> stopStream() async {}

  @override
  Future<void> startSyntheticAudioTest({required bool gameMode}) async {
    await onStartSyntheticAudioTest?.call(gameMode: gameMode);
  }

  @override
  Future<int> playSyntheticAudioClick(String inputLabel) async =>
      await onPlaySyntheticAudioClick?.call(inputLabel) ?? 1;

  @override
  Future<void> stopSyntheticAudioTest() async {
    await onStopSyntheticAudioTest?.call();
  }

  @override
  void recoverStreamSurface() => onRecoverStreamSurface?.call();

  @override
  Future<void> toggleStats() async {}

  @override
  Future<Map<String, Object?>> probeVideoCodecSupport(
    Map<String, Object?> request,
  ) async => const <String, Object?>{};

  @override
  NativeInputMode setInputMode(NativeInputMode mode) => mode;

  @override
  int connectedGamepadMask() => 0;

  @override
  List<NativeInputDevice> inputDevices() => const <NativeInputDevice>[];

  @override
  bool testRumble(int browserIndex) => true;

  @override
  bool sendEscape() => true;

  @override
  bool restartApp() => true;

  @override
  bool exitApp() => onExitApp?.call() ?? true;

  @override
  String setDiagnosticLogLevel(String level) => level;

  @override
  void logDiagnostic(
    String level,
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {}

  @override
  Map<String, Object?> diagnosticLogStatus() => const <String, Object?>{
    'level': 'debug',
    'entryCount': 1,
    'bytes': 64,
  };

  @override
  Future<String> diagnosticLogs() async => 'simulated browser diagnostic log';

  @override
  Future<Map<String, Object?>> clearDiagnosticLogs() async =>
      diagnosticLogStatus();

  @override
  String diagnosticQrSvg(String value) =>
      onDiagnosticQrSvg?.call(value) ?? '<svg></svg>';

  @override
  String getIpAddress() => '127.0.0.1';

  @override
  Future<Map<String, Object?>> startLogExportServer({
    required String payload,
    required String filename,
    required String token,
    int requestedPort = 0,
  }) async => const <String, Object?>{'port': 1234, 'path': '/log'};

  @override
  Future<void> stopLogExportServer() async {}

  @override
  void dispose() {}
}

Future<FakeOverrideBundle> createFakeOverrideBundle(
  FakeStateSeed seed, {
  MoonlightRepository? repository,
  FakeMoonlightNativeRuntime? runtime,
  SubnetDiscoveryGateway? subnetDiscoveryGateway,
}) async {
  final storage = InMemoryPersistentStateStore();
  if (seed.settings != null) {
    await storage.write(
      'appSettings.v1',
      jsonEncode(seed.settings!.toJson()),
      _fakeStorageOptions('app-settings-v1'),
    );
  }
  await storage.write(
    'savedHosts.v1',
    jsonEncode(seed.hosts.map((host) => host.toJson()).toList()),
    _fakeStorageOptions('saved-hosts-v1'),
  );
  final resolvedRepository =
      repository ??
      FakeMoonlightRepository(
        appsByHost: seed.appsByHost,
        offlineHostIds: seed.offlineHostIds,
        pairingFails: seed.pairingFails,
        launchFails: seed.launchFails,
      );
  final resolvedRuntime = runtime ?? FakeMoonlightNativeRuntime();
  return FakeOverrideBundle(
    storage: storage,
    overrides: [
      persistentStateStoreProvider.overrideWith((ref) async => storage),
      platformCapabilitiesProvider.overrideWithValue(
        seed.capabilities ?? const PlatformCapabilities(),
      ),
      moonlightRepositoryProvider.overrideWithValue(resolvedRepository),
      moonlightNativeRuntimeProvider.overrideWithValue(resolvedRuntime),
      subnetDiscoveryGatewayProvider.overrideWithValue(
        subnetDiscoveryGateway ?? const NoopSubnetDiscoveryGateway(),
      ),
      diagnosticLoggerProvider.overrideWithValue(
        NativeDiagnosticLogger(resolvedRuntime),
      ),
    ],
  );
}

StorageOptions _fakeStorageOptions(String destroyKey) => StorageOptions(
  cacheTime: StorageCacheTime.unsafe_forever,
  destroyKey: destroyKey,
);
