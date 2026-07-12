import 'dart:typed_data';

import '../../domain/contracts.dart';
import '../../domain/errors.dart';
import '../../domain/host_models.dart';
import '../../domain/stream_models.dart';

final class FakeMoonlightRepository implements MoonlightRepository {
  FakeMoonlightRepository({
    Map<String, List<MoonlightApp>>? appsByHost,
    Set<String>? offlineHostIds,
    this.pairingFails = false,
    this.launchFails = false,
    DateTime? now,
  }) : appsByHost = appsByHost ?? const {},
       offlineHostIds = offlineHostIds ?? const {},
       now = now ?? DateTime.utc(2026, 1, 1);

  final Map<String, List<MoonlightApp>> appsByHost;
  final Set<String> offlineHostIds;
  final bool pairingFails;
  final bool launchFails;
  final DateTime now;

  @override
  Future<void> cancel(SavedHost host, HostStatus status) async {}

  @override
  Future<Uint8List> getBoxArt(
    SavedHost host,
    HostStatus status,
    int appId,
  ) async => Uint8List(0);

  @override
  Future<List<MoonlightApp>> getAppList(
    SavedHost host,
    HostStatus status,
  ) async => List.unmodifiable(appsByHost[host.id] ?? const []);

  @override
  Future<LaunchResult> launch(
    SavedHost host,
    HostStatus status,
    HostLaunchRequest request,
  ) async => _launchResult();

  @override
  Future<PairingResult> pair(
    SavedHost host,
    HostStatus status,
    String pin,
  ) async {
    if (pairingFails || pin.isEmpty) {
      return PairingResult(host: host, status: status, paired: false);
    }
    return PairingResult(
      host: host.copyWith(pinnedCertificate: 'FAKE PINNED CERTIFICATE'),
      status: status.copyWith(paired: true, online: true),
      paired: true,
    );
  }

  @override
  Future<HostRefreshResult> refreshHost(
    SavedHost host,
    HostStatus status,
  ) async {
    if (offlineHostIds.contains(host.id)) {
      throw MoonlightException('${host.hostname} is offline.');
    }
    final next = status.copyWith(
      online: true,
      consecutivePollFailures: 0,
      successfulPollCount: status.successfulPollCount + 1,
      lastSeenAt: now,
    );
    final info = ServerInfo(
      serverUid: host.serverUid.isEmpty ? 'fake-${host.id}' : host.serverUid,
      hostname: host.hostname,
      paired: next.paired,
      currentGameId: next.currentGameId,
      appVersion: next.appVersion,
      gfeVersion: next.gfeVersion,
      serverMajorVersion: next.serverMajorVersion,
      serverCodecModeSupport: next.serverCodecModeSupport,
      numberOfApps: appsByHost[host.id]?.length ?? 0,
    );
    return HostRefreshResult(
      host: host.copyWith(serverUid: info.serverUid),
      status: next,
      serverInfo: info,
    );
  }

  @override
  Future<LaunchResult> resume(
    SavedHost host,
    HostStatus status,
    HostLaunchRequest request,
  ) async => _launchResult();

  @override
  Future<SavedHost> updateExternalAddress(SavedHost host) async => host;

  @override
  Future<void> wake(SavedHost host) async {}

  LaunchResult _launchResult() => launchFails
      ? const LaunchResult(
          statusCode: 503,
          statusMessage: 'Fake launch failure',
        )
      : const LaunchResult(
          statusCode: 200,
          statusMessage: 'OK',
          sessionUrl: 'rtsp://fake/session',
        );
}
