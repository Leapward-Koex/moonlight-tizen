import 'dart:typed_data';

import 'host_models.dart';
import 'stream_models.dart';

abstract interface class MoonlightHttpTransport {
  Future<String> openText(Uri uri, {String? pinnedCertificate});
  Future<Uint8List> openBinary(Uri uri, {String? pinnedCertificate});
}

abstract interface class PairingGateway {
  Future<String> pair({
    required int serverMajorVersion,
    required String address,
    required int httpPort,
    required String pin,
    required String uniqueId,
  });
}

abstract interface class NetworkDiscoveryGateway {
  Future<String?> stun();
  Future<void> wakeOnLan(String macAddress);
}

/// Browser-backed local-network discovery used on Tizen where mDNS replies are
/// not available to the WebAssembly sandbox.
abstract interface class SubnetDiscoveryGateway {
  Future<List<String>> scanLocalSubnet({
    Duration timeout = const Duration(milliseconds: 1800),
  });
}

final class NoopSubnetDiscoveryGateway implements SubnetDiscoveryGateway {
  const NoopSubnetDiscoveryGateway();

  @override
  Future<List<String>> scanLocalSubnet({
    Duration timeout = const Duration(milliseconds: 1800),
  }) async => const <String>[];
}

abstract interface class BoxArtCache {
  Future<Uint8List?> read(SavedHost host, int appId);
  Future<void> write(SavedHost host, int appId, Uint8List bytes);
  Future<void> clear(SavedHost host);
}

/// High-level host protocol surface consumed by state providers. Both the
/// native-backed client and deterministic browser fake implement this contract.
abstract interface class MoonlightRepository {
  Future<HostRefreshResult> refreshHost(SavedHost host, HostStatus status);
  Future<List<MoonlightApp>> getAppList(SavedHost host, HostStatus status);
  Future<Uint8List> getBoxArt(SavedHost host, HostStatus status, int appId);
  Future<PairingResult> pair(SavedHost host, HostStatus status, String pin);
  Future<SavedHost> updateExternalAddress(SavedHost host);
  Future<void> wake(SavedHost host);
  Future<LaunchResult> launch(
    SavedHost host,
    HostStatus status,
    HostLaunchRequest request,
  );
  Future<LaunchResult> resume(
    SavedHost host,
    HostStatus status,
    HostLaunchRequest request,
  );
  Future<void> cancel(SavedHost host, HostStatus status);
}

abstract interface class Clock {
  DateTime now();
}

final class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}

typedef UuidFactory = String Function();

/// Generation tokens make late async responses harmless without requiring the
/// underlying transport to implement cancellation.
final class OperationGeneration {
  int _generation = 0;

  int begin() => ++_generation;
  void cancel() => ++_generation;
  bool isCurrent(int generation) => generation == _generation;
}
