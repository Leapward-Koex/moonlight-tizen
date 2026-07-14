import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/host_workflows.dart';
import '../data/persistence/persistent_state_store.dart';
import '../domain/domain.dart';

part 'app_state.g.dart';

@Riverpod(keepAlive: true)
Future<PersistentStateStore> persistentStateStore(Ref ref) =>
    TizenPrivateFilePersistentStateStore.open();

@Riverpod(keepAlive: true)
PlatformCapabilities platformCapabilities(Ref ref) =>
    const PlatformCapabilities();

@Riverpod(keepAlive: true)
MoonlightRepository moonlightRepository(Ref ref) => throw UnsupportedError(
  'moonlightRepositoryProvider must be overridden by the native or fake app.',
);

@Riverpod(keepAlive: true)
SubnetDiscoveryGateway subnetDiscoveryGateway(Ref ref) =>
    const NoopSubnetDiscoveryGateway();

@Riverpod(keepAlive: true)
DiagnosticLogger diagnosticLogger(Ref ref) => const NoopDiagnosticLogger();

@Riverpod(keepAlive: true)
class Settings extends _$Settings {
  @override
  AppSettings build() {
    final capabilities = ref.watch(platformCapabilitiesProvider);
    persist<String, String>(
      ref.watch(persistentStateStoreProvider.future),
      key: 'appSettings.v1',
      encode: (value) => jsonEncode(value.toJson()),
      decode: (source) => AppSettings.fromJson(
        (jsonDecode(source) as Map).cast<String, Object?>(),
      ).normalized(capabilities),
      options: const StorageOptions(
        cacheTime: StorageCacheTime.unsafe_forever,
        destroyKey: 'app-settings-v1',
      ),
    );
    return AppSettings.defaultsFor(capabilities);
  }

  void replace(AppSettings value) {
    state = value.normalized(ref.read(platformCapabilitiesProvider));
  }

  void restoreDefaults() {
    state = AppSettings.defaultsFor(ref.read(platformCapabilitiesProvider));
  }
}

@Riverpod(keepAlive: true)
class ClientIdentityState extends _$ClientIdentityState {
  @override
  ClientIdentity? build() {
    persist<String, String>(
      ref.watch(persistentStateStoreProvider.future),
      key: 'clientIdentity.v1',
      encode: (value) => jsonEncode(value?.toJson()),
      decode: (source) {
        final value = jsonDecode(source);
        return value is Map
            ? ClientIdentity.fromJson(value.cast<String, Object?>())
            : null;
      },
      options: const StorageOptions(
        cacheTime: StorageCacheTime.unsafe_forever,
        destroyKey: 'client-identity-v1',
      ),
    );
    return null;
  }

  void setIdentity(ClientIdentity identity) => state = identity;
}

@Riverpod(keepAlive: true)
class SavedHosts extends _$SavedHosts {
  @override
  List<SavedHost> build() {
    persist<String, String>(
      ref.watch(persistentStateStoreProvider.future),
      key: 'savedHosts.v1',
      encode: (value) => jsonEncode(
        value.map((host) => host.toJson()).toList(growable: false),
      ),
      decode: (source) => (jsonDecode(source) as List)
          .whereType<Map>()
          .map((json) => SavedHost.fromJson(json.cast<String, Object?>()))
          .toList(growable: false),
      options: const StorageOptions(
        cacheTime: StorageCacheTime.unsafe_forever,
        destroyKey: 'saved-hosts-v1',
      ),
    );
    return const <SavedHost>[];
  }

  void upsert(SavedHost host) {
    final index = state.indexWhere((item) => item.id == host.id);
    if (index < 0) {
      state = List.unmodifiable([...state, host]);
      return;
    }
    final updated = [...state]..[index] = host;
    state = List.unmodifiable(updated);
  }

  void remove(String hostId) {
    state = List.unmodifiable(state.where((host) => host.id != hostId));
  }
}

@Riverpod(keepAlive: true)
class CodecCapabilities extends _$CodecCapabilities {
  @override
  CodecCapabilityCache build() {
    persist<String, String>(
      ref.watch(persistentStateStoreProvider.future),
      key: 'codecCapabilities.v2',
      encode: (value) => jsonEncode(value.toJson()),
      decode: (source) => CodecCapabilityCache.fromJson(
        (jsonDecode(source) as Map).cast<String, Object?>(),
      ),
      options: const StorageOptions(
        cacheTime: StorageCacheTime.unsafe_forever,
        destroyKey: 'codec-capabilities-v2',
      ),
    );
    return const CodecCapabilityCache();
  }

  void replace(CodecCapabilityCache cache) => state = cache;
  void reset() => state = const CodecCapabilityCache();
  void setEnabled(String key, bool enabled) {
    state = state.setEnabled(key, enabled, DateTime.now());
  }
}

@Riverpod(keepAlive: true)
class UpdateCheckTimestamp extends _$UpdateCheckTimestamp {
  @override
  DateTime? build() {
    persist<String, String>(
      ref.watch(persistentStateStoreProvider.future),
      key: 'updateCheckTimestamp.v1',
      encode: (value) => value?.toIso8601String() ?? '',
      decode: (source) => DateTime.tryParse(source),
      options: const StorageOptions(
        cacheTime: StorageCacheTime.unsafe_forever,
        destroyKey: 'update-check-v1',
      ),
    );
    return null;
  }

  void mark(DateTime value) => state = value;
}

@Riverpod(keepAlive: true)
class HostStatuses extends _$HostStatuses {
  @override
  Map<String, HostStatus> build() => const <String, HostStatus>{};

  void set(String hostId, HostStatus status) {
    state = Map.unmodifiable({...state, hostId: status});
  }

  void remove(String hostId) {
    state = Map.unmodifiable({...state}..remove(hostId));
  }
}

final class HostEntry {
  const HostEntry({
    required this.host,
    required this.status,
    required this.statusKnown,
  });
  final SavedHost host;
  final HostStatus status;
  final bool statusKnown;
}

typedef _HostConnectionKey = ({
  String address,
  String userEnteredAddress,
  String localAddress,
  String externalAddress,
  int httpPort,
  int httpsPort,
  int externalPort,
  String pinnedCertificate,
});

_HostConnectionKey? _hostConnectionKey(List<SavedHost> hosts, String hostId) {
  final host = hosts.where((item) => item.id == hostId).firstOrNull;
  if (host == null) return null;
  return (
    address: host.address,
    userEnteredAddress: host.userEnteredAddress,
    localAddress: host.localAddress,
    externalAddress: host.externalAddress,
    httpPort: host.httpPort,
    httpsPort: host.httpsPort,
    externalPort: host.externalPort,
    pinnedCertificate: host.pinnedCertificate,
  );
}

@riverpod
List<HostEntry> hosts(Ref ref) {
  final statuses = ref.watch(hostStatusesProvider);
  return ref
      .watch(savedHostsProvider)
      .map((host) {
        final status = statuses[host.id];
        return HostEntry(
          host: host,
          status: status ?? const HostStatus(),
          statusKnown: status != null,
        );
      })
      .toList(growable: false);
}

@riverpod
class Apps extends _$Apps {
  @override
  Future<List<MoonlightApp>> build(String hostId) async {
    final connection = ref.watch(
      savedHostsProvider.select((hosts) => _hostConnectionKey(hosts, hostId)),
    );
    final readiness = ref.watch(
      hostStatusesProvider.select((statuses) {
        final status = statuses[hostId];
        return (
          online: status?.online ?? false,
          paired: status?.paired ?? false,
        );
      }),
    );
    if (connection == null || !readiness.online || !readiness.paired) {
      return const <MoonlightApp>[];
    }
    final host = ref
        .read(savedHostsProvider)
        .where((item) => item.id == hostId)
        .firstOrNull;
    final status = ref.read(hostStatusesProvider)[hostId] ?? const HostStatus();
    if (host == null) return const <MoonlightApp>[];
    final apps = await ref
        .watch(moonlightRepositoryProvider)
        .getAppList(host, status);
    final settings = ref.read(settingsProvider);
    if (!settings.sortApps) return apps;
    return [...apps]
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  Future<void> refresh() async => ref.invalidateSelf();
}

@riverpod
Future<Uint8List?> boxArt(Ref ref, String hostId, int appId) async {
  final connection = ref.watch(
    savedHostsProvider.select((hosts) => _hostConnectionKey(hosts, hostId)),
  );
  final readiness = ref.watch(
    hostStatusesProvider.select((statuses) {
      final status = statuses[hostId];
      return (online: status?.online ?? false, paired: status?.paired ?? false);
    }),
  );
  if (connection == null || !readiness.online || !readiness.paired) return null;
  final host = ref
      .read(savedHostsProvider)
      .where((item) => item.id == hostId)
      .firstOrNull;
  final status = ref.read(hostStatusesProvider)[hostId] ?? const HostStatus();
  if (host == null) return null;
  return ref.watch(moonlightRepositoryProvider).getBoxArt(host, status, appId);
}

enum PairingPhase { idle, pairing, paired, failed }

final class PairingState {
  const PairingState({
    this.phase = PairingPhase.idle,
    this.hostId,
    this.message = '',
  });
  final PairingPhase phase;
  final String? hostId;
  final String message;
}

@Riverpod(keepAlive: true)
class Pairing extends _$Pairing {
  @override
  PairingState build() => const PairingState();

  Future<PairingResult> pair(String hostId, String pin) async {
    final logger = ref.read(diagnosticLoggerProvider);
    if (state.phase == PairingPhase.pairing) {
      logger.log('warning', 'state.pairing.busy_rejected');
      throw const PairingBusyException();
    }
    final host = ref
        .read(savedHostsProvider)
        .where((item) => item.id == hostId)
        .firstOrNull;
    if (host == null) throw StateError('Unknown host $hostId');
    final status = ref.read(hostStatusesProvider)[hostId] ?? const HostStatus();
    state = PairingState(phase: PairingPhase.pairing, hostId: hostId);
    logger.log('info', 'state.pairing.started');
    try {
      final result = await ref
          .read(moonlightRepositoryProvider)
          .pair(host, status, pin);
      if (!result.paired) {
        logger.log('warning', 'state.pairing.rejected');
        state = PairingState(
          phase: PairingPhase.failed,
          hostId: hostId,
          message: 'Pairing was rejected by the host.',
        );
        return result;
      }
      ref.read(savedHostsProvider.notifier).upsert(result.host);
      ref.read(hostStatusesProvider.notifier).set(hostId, result.status);
      state = PairingState(phase: PairingPhase.paired, hostId: hostId);
      logger.log('info', 'state.pairing.succeeded');
      return result;
    } catch (error, stackTrace) {
      state = PairingState(
        phase: PairingPhase.failed,
        hostId: hostId,
        message: error.toString(),
      );
      logger.error('state.pairing.failed', error, stackTrace);
      rethrow;
    }
  }

  void reset() => state = const PairingState();
}

@Riverpod(keepAlive: true)
class StreamSession extends _$StreamSession {
  @override
  StreamSessionState build() => const StreamSessionState();

  void begin(StreamRequest request, {String? attemptId}) {
    state = StreamSessionState(
      phase: StreamSessionPhase.connecting,
      request: request,
      attemptId: attemptId,
      message: 'Connecting…',
    );
    ref.read(diagnosticLoggerProvider).log('info', 'state.stream.begin', {
      'appId': request.appId,
      'attemptId': attemptId,
      'width': request.width,
      'height': request.height,
      'frameRate': request.frameRate,
      'codec': request.videoCodec.wireName,
    });
  }

  void applyEvent(StreamEvent event) {
    if (event.attemptId != null &&
        state.attemptId != null &&
        event.attemptId != state.attemptId) {
      ref
          .read(diagnosticLoggerProvider)
          .log('warning', 'state.stream.stale_event_ignored', {
            'event': event.name,
            'eventAttemptId': event.attemptId,
            'activeAttemptId': state.attemptId,
          });
      return;
    }
    final phase = switch (event.name) {
      'connected' || 'streaming' => StreamSessionPhase.streaming,
      'stopping' => StreamSessionPhase.stopping,
      'stopped' || 'terminated' => StreamSessionPhase.stopped,
      _ => state.phase,
    };
    state = state.copyWith(phase: phase, message: event.message);
    ref.read(diagnosticLoggerProvider).log(
      event.kind == StreamEventKind.warning ? 'warning' : 'info',
      'state.stream.event',
      {
        'kind': event.kind.name,
        'event': event.name,
        'attemptId': event.attemptId,
        'phase': phase.name,
        'message': event.message,
        'data': event.data,
      },
    );
  }

  void stopping() => state = state.copyWith(phase: StreamSessionPhase.stopping);
  void stopped() =>
      state = const StreamSessionState(phase: StreamSessionPhase.stopped);
  void fail(MoonlightRuntimeError error) {
    state = state.copyWith(phase: StreamSessionPhase.failed, error: error);
    ref.read(diagnosticLoggerProvider).log('error', 'state.stream.failed', {
      'code': error.code,
      'message': error.message,
      'details': error.details,
    });
  }

  void reset() => state = const StreamSessionState();
}

final class BootstrapState {
  const BootstrapState({required this.ready});
  final bool ready;
}

enum SubnetDiscoveryPhase { idle, waiting, scanning, complete, failed }

final class SubnetDiscoveryState {
  const SubnetDiscoveryState({
    this.phase = SubnetDiscoveryPhase.idle,
    this.summary = const SubnetDiscoverySummary(),
  });

  final SubnetDiscoveryPhase phase;
  final SubnetDiscoverySummary summary;
}

@Riverpod(keepAlive: true)
Future<BootstrapState> bootstrap(Ref ref) async {
  final logger = ref.read(diagnosticLoggerProvider);
  final stopwatch = Stopwatch()..start();
  logger.log('info', 'state.bootstrap.started');
  await ref.watch(persistentStateStoreProvider.future);
  ref.read(settingsProvider);
  ref.read(savedHostsProvider);
  ref.read(clientIdentityStateProvider);
  ref.read(codecCapabilitiesProvider);
  ref.read(updateCheckTimestampProvider);
  logger.log('info', 'state.bootstrap.completed', {
    'durationMs': stopwatch.elapsedMilliseconds,
    'hostCount': ref.read(savedHostsProvider).length,
    'hasIdentity':
        ref.read(clientIdentityStateProvider)?.hasCertificate == true,
    'codecCacheEntries': ref.read(codecCapabilitiesProvider).entries.length,
  });
  return const BootstrapState(ready: true);
}

@Riverpod(keepAlive: true)
class SubnetDiscovery extends _$SubnetDiscovery {
  bool _started = false;

  @override
  SubnetDiscoveryState build() => const SubnetDiscoveryState();

  Future<void> start({
    Duration delay = const Duration(milliseconds: 1500),
  }) async {
    if (_started) return;
    _started = true;
    state = const SubnetDiscoveryState(phase: SubnetDiscoveryPhase.waiting);
    await ref.read(bootstrapProvider.future);
    await Future<void>.delayed(delay);
    if (ref.read(streamSessionProvider).isActive) {
      state = const SubnetDiscoveryState(phase: SubnetDiscoveryPhase.complete);
      return;
    }

    state = const SubnetDiscoveryState(phase: SubnetDiscoveryPhase.scanning);
    final logger = ref.read(diagnosticLoggerProvider);
    try {
      final addresses = await ref
          .read(subnetDiscoveryGatewayProvider)
          .scanLocalSubnet();
      final summary = await ref
          .read(appCoordinatorProvider)
          .discoverHosts(addresses);
      state = SubnetDiscoveryState(
        phase: SubnetDiscoveryPhase.complete,
        summary: summary,
      );
    } catch (error, stackTrace) {
      logger.error('state.subnet_discovery.failed', error, stackTrace);
      state = const SubnetDiscoveryState(phase: SubnetDiscoveryPhase.failed);
    }
  }
}

@Riverpod(keepAlive: true)
AppCoordinator appCoordinator(Ref ref) => AppCoordinator(ref);

final class AppCoordinator {
  AppCoordinator(this.ref);

  final Ref ref;
  final Map<String, OperationGeneration> _hostGenerations = {};
  final Map<String, DateTime> _lastActivation = {};

  DiagnosticLogger get _logger => ref.read(diagnosticLoggerProvider);

  Future<BootstrapState> bootstrap() => ref.read(bootstrapProvider.future);

  Future<HostRefreshResult> addHost(SavedHost host) async {
    _logger.log('info', 'coordinator.host.add_started', {
      'httpPort': host.httpPort,
      'addressKind': host.address.contains(':')
          ? 'ipv6'
          : RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host.address)
          ? 'ipv4'
          : 'hostname',
    });
    ref.read(savedHostsProvider.notifier).upsert(host);
    final result = await pollHost(host.id);
    _logger.log('info', 'coordinator.host.add_completed', {
      'online': result.status.online,
      'paired': result.status.paired,
    });
    return result;
  }

  Future<SubnetDiscoverySummary> discoverHosts(
    Iterable<String> responderAddresses,
  ) async {
    final addresses = responderAddresses
        .map((address) => address.trim())
        .where(_isIpv4Address)
        .toSet()
        .toList(growable: false);
    final knownAddresses = ref
        .read(savedHostsProvider)
        .map((host) => host.address.trim())
        .toSet();
    final candidates = addresses
        .where((address) => !knownAddresses.contains(address))
        .toList(growable: false);
    _logger.log('info', 'coordinator.subnet_discovery.started', {
      'responderCount': addresses.length,
      'candidateCount': candidates.length,
    });

    final refreshes = await Future.wait(
      candidates.map(_refreshDiscoveredAddress),
    );
    var added = 0;
    var updated = 0;
    var ignored = addresses.length - candidates.length;

    for (final refresh in refreshes) {
      if (refresh == null || !refresh.status.online) {
        ignored += 1;
        continue;
      }
      final serverUid = refresh.host.serverUid.trim();
      if (serverUid.isEmpty) {
        ignored += 1;
        continue;
      }
      final existing = ref.read(savedHostsProvider).where((host) {
        return host.serverUid == serverUid || host.id == serverUid;
      }).firstOrNull;

      if (existing == null) {
        final discovered = refresh.host.copyWith(
          id: serverUid,
          serverUid: serverUid,
          userEnteredAddress: '',
        );
        ref.read(savedHostsProvider.notifier).upsert(discovered);
        ref
            .read(hostStatusesProvider.notifier)
            .set(discovered.id, refresh.status);
        added += 1;
        continue;
      }

      final existingStatus =
          ref.read(hostStatusesProvider)[existing.id] ?? const HostStatus();
      if (!_isIpv4Address(existing.address) && existingStatus.online) {
        ignored += 1;
        continue;
      }
      if (existing.address == refresh.host.address) {
        ignored += 1;
        continue;
      }

      _hostGenerations[existing.id]?.cancel();
      final discovered = refresh.host;
      final reconciled = existing.copyWith(
        serverUid: serverUid,
        hostname: discovered.hostname,
        address: discovered.address,
        localAddress: discovered.localAddress.isEmpty
            ? existing.localAddress
            : discovered.localAddress,
        externalAddress: discovered.externalAddress.isEmpty
            ? existing.externalAddress
            : discovered.externalAddress,
        macAddress: discovered.macAddress.isEmpty
            ? existing.macAddress
            : discovered.macAddress,
        httpsPort: discovered.httpsPort,
        externalPort: discovered.externalPort,
      );
      ref.read(savedHostsProvider.notifier).upsert(reconciled);
      ref.read(hostStatusesProvider.notifier).set(existing.id, refresh.status);
      updated += 1;
    }

    final summary = SubnetDiscoverySummary(
      responderCount: addresses.length,
      addedHostCount: added,
      updatedHostCount: updated,
      ignoredHostCount: ignored,
    );
    _logger.log('info', 'coordinator.subnet_discovery.completed', {
      'responderCount': summary.responderCount,
      'addedHostCount': summary.addedHostCount,
      'updatedHostCount': summary.updatedHostCount,
      'ignoredHostCount': summary.ignoredHostCount,
    });
    return summary;
  }

  Future<HostRefreshResult?> _refreshDiscoveredAddress(String address) async {
    final provisional = SavedHost(
      id: 'discovered:$address',
      hostname: address,
      address: address,
    );
    try {
      return await ref
          .read(moonlightRepositoryProvider)
          .refreshHost(provisional, const HostStatus());
    } catch (error, stackTrace) {
      _logger.error(
        'coordinator.subnet_discovery.responder_rejected',
        error,
        stackTrace,
      );
      return null;
    }
  }

  void removeHost(String hostId) {
    _logger.log('info', 'coordinator.host.removed');
    _hostGenerations[hostId]?.cancel();
    ref.read(savedHostsProvider.notifier).remove(hostId);
    ref.read(hostStatusesProvider.notifier).remove(hostId);
    ref.invalidate(appsProvider(hostId));
  }

  Future<HostRefreshResult> pollHost(String hostId) async {
    final host = _host(hostId);
    final status = ref.read(hostStatusesProvider)[hostId] ?? const HostStatus();
    final guard = _hostGenerations.putIfAbsent(hostId, OperationGeneration.new);
    final generation = guard.begin();
    final stopwatch = Stopwatch()..start();
    _logger.log('debug', 'coordinator.host.poll_started', {
      'generation': generation,
      'previouslyOnline': status.online,
      'failureCount': status.consecutivePollFailures,
    });
    try {
      final result = await ref
          .read(moonlightRepositoryProvider)
          .refreshHost(host, status);
      if (!guard.isCurrent(generation)) throw const StaleOperationException();
      ref.read(savedHostsProvider.notifier).upsert(result.host);
      ref.read(hostStatusesProvider.notifier).set(hostId, result.status);
      _logger.log('debug', 'coordinator.host.poll_completed', {
        'generation': generation,
        'durationMs': stopwatch.elapsedMilliseconds,
        'online': result.status.online,
        'paired': result.status.paired,
        'successfulPollCount': result.status.successfulPollCount,
      });
      return result;
    } catch (error, stackTrace) {
      if (guard.isCurrent(generation)) {
        ref
            .read(hostStatusesProvider.notifier)
            .set(hostId, status.afterFailure());
      }
      _logger.error('coordinator.host.poll_failed', error, stackTrace, {
        'generation': generation,
        'durationMs': stopwatch.elapsedMilliseconds,
      });
      rethrow;
    }
  }

  Future<PairingResult> pair(String hostId, String pin) =>
      ref.read(pairingProvider.notifier).pair(hostId, pin);

  Future<List<MoonlightApp>> apps(String hostId) =>
      ref.read(appsProvider(hostId).future);

  Future<StreamRequest> prepareStream({
    required String hostId,
    required MoonlightApp app,
    required RemoteInputCredentials remoteInput,
    required int gamepadMask,
  }) async {
    final activationKey = '$hostId:${app.id}';
    final now = DateTime.now();
    final previous = _lastActivation[activationKey];
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 2)) {
      _logger.log('warning', 'coordinator.stream.duplicate_activation', {
        'appId': app.id,
      });
      throw const MoonlightException(
        'Please wait before activating this game again.',
      );
    }
    _lastActivation[activationKey] = now;

    final host = _host(hostId);
    final status = ref.read(hostStatusesProvider)[hostId] ?? const HostStatus();
    if (status.currentGameId != 0 && status.currentGameId != app.id) {
      _logger.log('info', 'coordinator.stream.switch_confirmation_required', {
        'requestedAppId': app.id,
        'currentGameId': status.currentGameId,
      });
      throw const ProtocolException(
        'Another app is running. Confirmation is required before switching.',
      );
    }
    final settings = ref.read(settingsProvider);
    final launch = HostLaunchRequest(
      appId: app.id,
      mode: settings.streamMode,
      optimizeGameSettings: settings.optimizeGameSettings,
      remoteInput: remoteInput,
      hdr: settings.hdr,
      playAudioOnHost: settings.playAudioOnHost,
      gamepadMask: gamepadMask,
    );
    _logger.log('info', 'coordinator.stream.prepare_started', {
      'appId': app.id,
      'resume': status.currentGameId == app.id,
      'mode': settings.streamMode,
      'bitrateKbps': settings.bitrateKbps,
      'codec': settings.videoCodec.wireName,
      'hdr': settings.hdr,
      'gameMode': settings.gameMode,
      'gamepadMask': gamepadMask,
    });
    final repository = ref.read(moonlightRepositoryProvider);
    final result = status.currentGameId == app.id
        ? await repository.resume(host, status, launch)
        : await repository.launch(host, status, launch);
    if (!result.isSuccess) {
      _logger.log('error', 'coordinator.stream.host_rejected', {
        'appId': app.id,
        'statusCode': result.statusCode,
        'statusMessage': result.statusMessage,
      });
      throw ProtocolException(
        'Unable to start ${app.title}: ${result.statusMessage}',
        statusCode: result.statusCode,
        statusMessage: result.statusMessage,
      );
    }
    final request = StreamRequest.fromSettings(
      app: app,
      host: host,
      hostStatus: status,
      settings: settings,
      remoteInput: remoteInput,
      sessionUrl: result.sessionUrl,
      disabledCodecMimeTypes: ref
          .read(codecCapabilitiesProvider)
          .disabledMimeTypes,
    );
    ref.read(streamSessionProvider.notifier).begin(request);
    _logger.log('info', 'coordinator.stream.prepare_completed', {
      'appId': app.id,
      'hasSessionUrl': result.sessionUrl.isNotEmpty,
      'disabledCodecCount': request.disabledCodecMimeTypes.length,
    });
    return request;
  }

  Future<void> quitRunningApp(String hostId) async {
    final host = _host(hostId);
    final status = ref.read(hostStatusesProvider)[hostId] ?? const HostStatus();
    _logger.log('info', 'coordinator.stream.quit_started', {
      'currentGameId': status.currentGameId,
    });
    final result = await AppSwitchWorkflow(
      ref.read(moonlightRepositoryProvider),
    ).quitAndWait(host, status);
    ref.read(savedHostsProvider.notifier).upsert(result.host);
    ref.read(hostStatusesProvider.notifier).set(hostId, result.status);
    ref.invalidate(appsProvider(hostId));
    _logger.log('info', 'coordinator.stream.quit_completed', {
      'currentGameId': result.status.currentGameId,
    });
  }

  void stopStreamOnly() => ref.read(streamSessionProvider.notifier).stopped();

  SavedHost _host(String hostId) => ref
      .read(savedHostsProvider)
      .firstWhere(
        (host) => host.id == hostId,
        orElse: () => throw StateError('Unknown host $hostId'),
      );
}

bool _isIpv4Address(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return false;
  return parts.every((part) {
    final octet = int.tryParse(part);
    return octet != null && octet >= 0 && octet <= 255;
  });
}
