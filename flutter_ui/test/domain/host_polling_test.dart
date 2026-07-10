import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonlight_tizen_flutter/data/data.dart';
import 'package:moonlight_tizen_flutter/domain/domain.dart';

void main() {
  const host = SavedHost(id: 'host', hostname: 'PC', address: '192.168.1.5');

  test('marks host offline only after two consecutive failures', () async {
    final poller = HostPoller(_failingClient());
    final first = await poller.poll(
      host,
      const HostStatus(online: true),
      streamActive: false,
    );
    expect(first.status.online, isTrue);
    expect(first.status.consecutivePollFailures, 1);

    final second = await poller.poll(host, first.status, streamActive: false);
    expect(second.status.online, isFalse);
    expect(second.status.consecutivePollFailures, 2);
  });

  test('skips polling during an active stream', () async {
    final poller = HostPoller(_failingClient());
    final result = await poller.poll(
      host,
      const HostStatus(online: true),
      streamActive: true,
    );
    expect(result.skippedForStream, isTrue);
    expect(result.status.online, isTrue);
  });

  test(
    'failed host polling emits structured diagnostics without addresses',
    () async {
      final logger = _RecordingLogger();
      final poller = HostPoller(_failingClient(logger));

      await poller.poll(host, const HostStatus(), streamActive: false);

      expect(
        logger.events.map((entry) => entry.event),
        containsAll([
          'nvhttp.host_refresh.started',
          'nvhttp.host_refresh.candidate_failed',
          'nvhttp.host_refresh.failed',
        ]),
      );
      final serialized = logger.events.toString();
      expect(serialized, isNot(contains(host.address)));
    },
  );
}

NvHttpClient _failingClient([DiagnosticLogger? logger]) => NvHttpClient(
  transport: _Transport(),
  pairingGateway: _Pairing(),
  discoveryGateway: _Discovery(),
  requests: NvHttpRequestBuilder(
    clientUid: 'client',
    uuidFactory: () => 'uuid',
  ),
  logger: logger ?? const NoopDiagnosticLogger(),
);

final class _LogEntry {
  const _LogEntry(this.level, this.event, this.details);
  final String level;
  final String event;
  final Map<String, Object?> details;

  @override
  String toString() => '$level $event $details';
}

final class _RecordingLogger implements DiagnosticLogger {
  final List<_LogEntry> events = [];

  @override
  void log(
    String level,
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {
    events.add(_LogEntry(level, event, details));
  }
}

final class _Transport implements MoonlightHttpTransport {
  @override
  Future<Uint8List> openBinary(Uri uri, {String? pinnedCertificate}) =>
      throw const TransportException('offline');

  @override
  Future<String> openText(Uri uri, {String? pinnedCertificate}) =>
      throw const TransportException('offline');
}

final class _Pairing implements PairingGateway {
  @override
  Future<String> pair({
    required int serverMajorVersion,
    required String address,
    required int httpPort,
    required String pin,
    required String uniqueId,
  }) async => '';
}

final class _Discovery implements NetworkDiscoveryGateway {
  @override
  Future<String?> stun() async => null;

  @override
  Future<void> wakeOnLan(String macAddress) async {}
}
