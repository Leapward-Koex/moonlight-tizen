import 'dart:typed_data';

import '../domain/contracts.dart';
import '../domain/diagnostics.dart';
import '../domain/errors.dart';
import '../domain/host_models.dart';
import '../domain/stream_models.dart';
import 'nvhttp_request_builder.dart';
import 'nvhttp_xml_parser.dart';

final class NvHttpClient implements MoonlightRepository {
  NvHttpClient({
    required this.transport,
    required this.pairingGateway,
    required this.discoveryGateway,
    required this.requests,
    this.parser = const NvHttpXmlParser(),
    this.clock = const SystemClock(),
    this.boxArtCache,
    this.logger = const NoopDiagnosticLogger(),
    PairingCoordinator? pairingCoordinator,
  }) : pairingCoordinator = pairingCoordinator ?? PairingCoordinator();

  final MoonlightHttpTransport transport;
  final PairingGateway pairingGateway;
  final NetworkDiscoveryGateway discoveryGateway;
  final NvHttpRequestBuilder requests;
  final NvHttpXmlParser parser;
  final Clock clock;
  final BoxArtCache? boxArtCache;
  final DiagnosticLogger logger;
  final PairingCoordinator pairingCoordinator;

  Future<ServerInfo> fetchServerInfoAt(
    SavedHost host,
    HostStatus previousStatus,
    String address,
  ) async {
    if (!host.hasPinnedCertificate) {
      return _fetchServerInfo(host, previousStatus, address, secure: false);
    }

    try {
      return await _fetchServerInfo(
        host,
        previousStatus,
        address,
        secure: true,
      );
    } on TransportException catch (error) {
      if (!error.isCertificateMismatch) rethrow;
      return _fetchServerInfo(host, previousStatus, address, secure: false);
    } on ProtocolException {
      // The legacy client falls back to HTTP when a syntactically valid HTTPS
      // response is rejected. Never hide a host identity mismatch.
      try {
        return await _fetchServerInfo(
          host,
          previousStatus,
          address,
          secure: false,
        );
      } on UnexpectedHostException {
        rethrow;
      }
    }
  }

  @override
  Future<HostRefreshResult> refreshHost(
    SavedHost host,
    HostStatus previousStatus,
  ) async {
    final stopwatch = Stopwatch()..start();
    Object? lastError;
    final candidates = _addressCandidates(host);
    logger.log('debug', 'nvhttp.host_refresh.started', {
      'candidateCount': candidates.length,
      'hasPinnedCertificate': host.hasPinnedCertificate,
      'previouslyOnline': previousStatus.online,
      'consecutiveFailures': previousStatus.consecutivePollFailures,
    });
    for (var index = 0; index < candidates.length; index++) {
      final address = candidates[index];
      try {
        final info = await fetchServerInfoAt(host, previousStatus, address);
        final updatedHost = host.copyWith(
          serverUid: info.serverUid,
          hostname: info.hostname,
          address: address,
          localAddress: info.localAddress.isEmpty
              ? host.localAddress
              : info.localAddress,
          externalAddress: info.externalAddress.isEmpty
              ? host.externalAddress
              : info.externalAddress,
          macAddress: info.macAddress.isEmpty
              ? host.macAddress
              : info.macAddress,
          httpsPort: info.httpsPort > 0 ? info.httpsPort : host.httpsPort,
          externalPort: info.externalPort > 0
              ? info.externalPort
              : host.externalPort,
        );
        final result = HostRefreshResult(
          host: updatedHost,
          status: info.toStatus(previous: previousStatus, now: clock.now()),
          serverInfo: info,
        );
        logger.log('info', 'nvhttp.host_refresh.succeeded', {
          'candidateIndex': index,
          'durationMs': stopwatch.elapsedMilliseconds,
          'paired': result.status.paired,
          'serverMajorVersion': result.status.serverMajorVersion,
          'appCount': result.status.numberOfApps,
          'currentGameId': result.status.currentGameId,
        });
        return result;
      } catch (error, stackTrace) {
        lastError = error;
        logger
            .error('nvhttp.host_refresh.candidate_failed', error, stackTrace, {
              'candidateIndex': index,
              'secureAttempted': host.hasPinnedCertificate,
              'durationMs': stopwatch.elapsedMilliseconds,
            });
      }
    }
    logger.log('error', 'nvhttp.host_refresh.failed', {
      'candidateCount': candidates.length,
      'durationMs': stopwatch.elapsedMilliseconds,
      'lastErrorType': lastError.runtimeType.toString(),
    });
    throw MoonlightException(
      'Unable to contact ${host.hostname}.',
      cause: lastError,
    );
  }

  @override
  Future<List<MoonlightApp>> getAppList(
    SavedHost host,
    HostStatus status,
  ) async {
    final stopwatch = Stopwatch()..start();
    logger.log('debug', 'nvhttp.app_list.started');
    final response = await transport.openText(
      requests.appList(host, status),
      pinnedCertificate: _pin(host),
    );
    final apps = parser.parseAppList(response);
    logger.log('info', 'nvhttp.app_list.succeeded', {
      'appCount': apps.length,
      'durationMs': stopwatch.elapsedMilliseconds,
    });
    return apps;
  }

  @override
  Future<Uint8List> getBoxArt(
    SavedHost host,
    HostStatus status,
    int appId,
  ) async {
    final cached = await boxArtCache?.read(host, appId);
    if (cached != null) {
      logger.log('debug', 'nvhttp.box_art.cache_hit', {
        'appId': appId,
        'bytes': cached.length,
      });
      return cached;
    }
    final stopwatch = Stopwatch()..start();
    final bytes = await transport.openBinary(
      requests.appAsset(host, status, appId),
      pinnedCertificate: _pin(host),
    );
    await boxArtCache?.write(host, appId, bytes);
    logger.log('debug', 'nvhttp.box_art.downloaded', {
      'appId': appId,
      'bytes': bytes.length,
      'durationMs': stopwatch.elapsedMilliseconds,
    });
    return bytes;
  }

  @override
  Future<LaunchResult> launch(
    SavedHost host,
    HostStatus status,
    HostLaunchRequest request,
  ) async {
    if (request.appId == null) {
      throw const ProtocolException('Launch request is missing an app ID.');
    }
    final stopwatch = Stopwatch()..start();
    logger.log('info', 'nvhttp.launch.started', {
      'appId': request.appId,
      'mode': request.mode,
      'hdr': request.hdr,
      'gamepadMask': request.gamepadMask,
    });
    final response = await transport.openText(
      requests.launch(host, status, request),
      pinnedCertificate: _pin(host),
    );
    final result = parser.parseLaunchResult(response);
    logger.log(result.isSuccess ? 'info' : 'error', 'nvhttp.launch.completed', {
      'appId': request.appId,
      'statusCode': result.statusCode,
      'durationMs': stopwatch.elapsedMilliseconds,
      'hasSessionUrl': result.sessionUrl.isNotEmpty,
    });
    return result;
  }

  @override
  Future<LaunchResult> resume(
    SavedHost host,
    HostStatus status,
    HostLaunchRequest request,
  ) async {
    final stopwatch = Stopwatch()..start();
    logger.log('info', 'nvhttp.resume.started', {
      'mode': request.mode,
      'hdr': request.hdr,
      'gamepadMask': request.gamepadMask,
    });
    final response = await transport.openText(
      requests.resume(host, status, request),
      pinnedCertificate: _pin(host),
    );
    final result = parser.parseLaunchResult(response);
    logger.log(result.isSuccess ? 'info' : 'error', 'nvhttp.resume.completed', {
      'statusCode': result.statusCode,
      'durationMs': stopwatch.elapsedMilliseconds,
      'hasSessionUrl': result.sessionUrl.isNotEmpty,
    });
    return result;
  }

  @override
  Future<void> cancel(SavedHost host, HostStatus status) async {
    final stopwatch = Stopwatch()..start();
    logger.log('info', 'nvhttp.cancel.started', {
      'currentGameId': status.currentGameId,
    });
    final response = await transport.openText(
      requests.cancel(host, status),
      pinnedCertificate: _pin(host),
    );
    parser.requireSuccess(response, 'cancel');
    logger.log('info', 'nvhttp.cancel.succeeded', {
      'durationMs': stopwatch.elapsedMilliseconds,
    });
  }

  @override
  Future<PairingResult> pair(
    SavedHost host,
    HostStatus status,
    String pin,
  ) => pairingCoordinator.run(() async {
    final stopwatch = Stopwatch()..start();
    logger.log('info', 'nvhttp.pairing.started', {
      'previouslyPaired': status.paired,
      'hasPinnedCertificate': host.hasPinnedCertificate,
    });
    var refresh = await refreshHost(host, status);
    if (refresh.status.paired && refresh.host.hasPinnedCertificate) {
      final result = PairingResult(
        host: refresh.host,
        status: refresh.status,
        paired: true,
      );
      logger.log('info', 'nvhttp.pairing.already_paired', {
        'durationMs': stopwatch.elapsedMilliseconds,
      });
      return result;
    }

    final certificate = await pairingGateway.pair(
      serverMajorVersion: refresh.status.serverMajorVersion,
      address: refresh.host.address,
      httpPort: refresh.host.httpPort,
      pin: pin,
      uniqueId: requests.effectiveUid(refresh.status.isNvidiaServerSoftware),
    );
    final pairedHost = refresh.host.copyWith(pinnedCertificate: certificate);
    final response = await transport.openText(
      requests.pairChallenge(pairedHost, refresh.status),
      pinnedCertificate: certificate,
    );
    final paired = parser.parsePairResult(response);
    final result = PairingResult(
      host: pairedHost,
      status: refresh.status.copyWith(paired: paired),
      paired: paired,
    );
    logger.log(paired ? 'info' : 'warning', 'nvhttp.pairing.completed', {
      'paired': paired,
      'durationMs': stopwatch.elapsedMilliseconds,
    });
    return result;
  });

  @override
  Future<SavedHost> updateExternalAddress(SavedHost host) async {
    logger.log('debug', 'nvhttp.stun.started');
    final address = await discoveryGateway.stun();
    final updated = address == null || address.isEmpty
        ? host
        : host.copyWith(externalAddress: address);
    logger.log('debug', 'nvhttp.stun.completed', {
      'addressDiscovered': address != null && address.isNotEmpty,
    });
    return updated;
  }

  @override
  Future<void> wake(SavedHost host) async {
    logger.log('info', 'nvhttp.wake_on_lan.started', {
      'hasMacAddress': host.macAddress.isNotEmpty,
    });
    await discoveryGateway.wakeOnLan(host.macAddress);
    logger.log('info', 'nvhttp.wake_on_lan.completed');
  }

  Future<ServerInfo> _fetchServerInfo(
    SavedHost host,
    HostStatus previousStatus,
    String address, {
    required bool secure,
  }) async {
    final response = await transport.openText(
      requests.serverInfo(
        host,
        address,
        secure: secure,
        isNvidiaServerSoftware: previousStatus.isNvidiaServerSoftware,
      ),
      pinnedCertificate: secure ? _pin(host) : null,
    );
    return parser.parseServerInfo(
      response,
      expectedServerUid: host.serverUid,
      fallbackHttpsPort: host.httpsPort,
      fallbackExternalPort: host.externalPort,
    );
  }

  List<String> _addressCandidates(SavedHost host) {
    final values = <String>[
      host.address,
      if (host.hostname.isNotEmpty && host.hostname != 'UNKNOWN')
        host.hostname.endsWith('.local')
            ? host.hostname
            : '${host.hostname}.local',
      host.localAddress,
      host.externalAddress,
      host.userEnteredAddress,
    ];
    final seen = <String>{};
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && seen.add(value))
        .toList(growable: false);
  }

  String? _pin(SavedHost host) =>
      host.pinnedCertificate.isEmpty ? null : host.pinnedCertificate;
}

final class PairingCoordinator {
  bool _active = false;

  Future<T> run<T>(Future<T> Function() action) async {
    if (_active) throw const PairingBusyException();
    _active = true;
    try {
      return await action();
    } finally {
      _active = false;
    }
  }
}
