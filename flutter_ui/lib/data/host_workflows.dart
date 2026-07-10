import 'dart:async';

import '../domain/contracts.dart';
import '../domain/errors.dart';
import '../domain/host_models.dart';
import '../domain/stream_models.dart';

typedef Delay = Future<void> Function(Duration duration);

final class HostPollResult {
  const HostPollResult({
    required this.host,
    required this.status,
    this.refresh,
    this.error,
    this.shouldRefreshApps = false,
    this.skippedForStream = false,
  });

  final SavedHost host;
  final HostStatus status;
  final HostRefreshResult? refresh;
  final Object? error;
  final bool shouldRefreshApps;
  final bool skippedForStream;
}

/// One-shot host polling with request coalescing and legacy failure semantics.
/// The UI/state layer schedules this every [pollInterval].
final class HostPoller {
  HostPoller(this.client);

  static const pollInterval = Duration(seconds: 5);
  static const appRefreshEverySuccessfulPolls = 10;

  final MoonlightRepository client;
  final Map<String, Future<HostPollResult>> _inFlight = {};

  Future<HostPollResult> poll(
    SavedHost host,
    HostStatus status, {
    required bool streamActive,
  }) {
    if (streamActive) {
      return Future.value(
        HostPollResult(host: host, status: status, skippedForStream: true),
      );
    }
    final existing = _inFlight[host.id];
    if (existing != null) return existing;
    final request = _poll(host, status);
    _inFlight[host.id] = request;
    request.whenComplete(() => _inFlight.remove(host.id));
    return request;
  }

  Future<HostPollResult> _poll(SavedHost host, HostStatus status) async {
    try {
      final refresh = await client.refreshHost(host, status);
      return HostPollResult(
        host: refresh.host,
        status: refresh.status,
        refresh: refresh,
        shouldRefreshApps:
            refresh.status.paired &&
            refresh.status.successfulPollCount %
                    appRefreshEverySuccessfulPolls ==
                0,
      );
    } catch (error) {
      return HostPollResult(
        host: host,
        status: status.afterFailure(),
        error: error,
      );
    }
  }
}

final class AppSwitchWorkflow {
  AppSwitchWorkflow(
    this.client, {
    this.maxRefreshAttempts = 6,
    this.refreshDelay = const Duration(milliseconds: 500),
    Delay? delay,
  }) : delay = delay ?? Future<void>.delayed;

  final MoonlightRepository client;
  final int maxRefreshAttempts;
  final Duration refreshDelay;
  final Delay delay;
  final OperationGeneration _generation = OperationGeneration();

  void cancelPending() => _generation.cancel();

  /// Quits the currently running host app and waits until server-info confirms
  /// it has stopped. Call only after the user has confirmed the switch.
  Future<HostRefreshResult> quitAndWait(
    SavedHost host,
    HostStatus status,
  ) async {
    final generation = _generation.begin();
    await client.cancel(host, status);
    var currentHost = host;
    var currentStatus = status;
    for (var attempt = 0; attempt < maxRefreshAttempts; attempt++) {
      if (!_generation.isCurrent(generation)) {
        throw const StaleOperationException();
      }
      await delay(refreshDelay);
      final refresh = await client.refreshHost(currentHost, currentStatus);
      currentHost = refresh.host;
      currentStatus = refresh.status;
      if (currentStatus.currentGameId == 0) return refresh;
    }
    throw const ProtocolException(
      'The host did not stop the running app before the switch timed out.',
    );
  }

  Future<LaunchResult> launchOrResume(
    SavedHost host,
    HostStatus status,
    HostLaunchRequest request,
  ) async {
    final appId = request.appId;
    final result = appId != null && status.currentGameId == appId
        ? await client.resume(host, status, request)
        : await client.launch(host, status, request);
    if (result.statusCode != 200) {
      throw ProtocolException(
        'Host rejected the stream request with status ${result.statusCode}: ${result.statusMessage}.',
        statusCode: result.statusCode,
        statusMessage: result.statusMessage,
      );
    }
    if (result.sessionUrl.isEmpty) {
      throw const ProtocolException(
        'Host accepted the stream request but returned no session URL.',
      );
    }
    return result;
  }
}
