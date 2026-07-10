import '../domain/host_models.dart';
import '../domain/stream_models.dart';

final class NvHttpRequestBuilder {
  NvHttpRequestBuilder({required this.clientUid, required this.uuidFactory});

  static const nvidiaClientUid = '0123456789ABCDEF';

  final String clientUid;
  final String Function() uuidFactory;

  String effectiveUid(bool isNvidiaServerSoftware) =>
      isNvidiaServerSoftware ? nvidiaClientUid : clientUid;

  Uri serverInfo(
    SavedHost host,
    String address, {
    required bool secure,
    required bool isNvidiaServerSoftware,
  }) => _uri(
    secure ? 'https' : 'http',
    address,
    secure ? host.httpsPort : host.httpPort,
    '/serverinfo',
    _identity(isNvidiaServerSoftware),
  );

  Uri appList(SavedHost host, HostStatus status) =>
      _secure(host, '/applist', _identity(status.isNvidiaServerSoftware));

  Uri appAsset(SavedHost host, HostStatus status, int appId) =>
      _secure(host, '/appasset', {
        ..._identity(status.isNvidiaServerSoftware),
        'appid': '$appId',
        'AssetType': '2',
        'AssetIdx': '0',
      });

  Uri launch(SavedHost host, HostStatus status, HostLaunchRequest request) =>
      _secure(host, '/launch', {
        ..._identity(status.isNvidiaServerSoftware),
        'appid': '${request.appId}',
        ..._launchParameters(request),
      });

  Uri resume(SavedHost host, HostStatus status, HostLaunchRequest request) =>
      _secure(host, '/resume', {
        ..._identity(status.isNvidiaServerSoftware),
        ..._launchParameters(request),
      });

  Uri cancel(SavedHost host, HostStatus status) =>
      _secure(host, '/cancel', _identity(status.isNvidiaServerSoftware));

  Uri pairChallenge(SavedHost host, HostStatus status) =>
      _secure(host, '/pair', {
        'uniqueid': effectiveUid(status.isNvidiaServerSoftware),
        'devicename': 'roth',
        'updateState': '1',
        'phrase': 'pairchallenge',
      });

  Map<String, String> _identity(bool nvidia) => {
    'uniqueid': effectiveUid(nvidia),
    'uuid': uuidFactory(),
  };

  Map<String, String> _launchParameters(HostLaunchRequest request) => {
    'mode': request.mode,
    'additionalStates': '1',
    'sops': request.optimizeGameSettings ? '1' : '0',
    'rikey': request.remoteInput.key,
    'rikeyid': '${request.remoteInput.keyId}',
    'hdrMode': request.hdr ? '1' : '0',
    'localAudioPlayMode': request.playAudioOnHost ? '1' : '0',
    'surroundAudioInfo': '${request.surroundAudioInfo}',
    'remoteControllersBitmap': '${request.gamepadMask}',
    'gcmap': '${request.gamepadMask}',
  };

  Uri _secure(SavedHost host, String path, Map<String, String> query) =>
      _uri('https', host.address, host.httpsPort, path, query);

  Uri _uri(
    String scheme,
    String address,
    int port,
    String path,
    Map<String, String> query,
  ) {
    var host = address.trim();
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    return Uri(
      scheme: scheme,
      host: host,
      port: port,
      path: path,
      queryParameters: query,
    );
  }
}
