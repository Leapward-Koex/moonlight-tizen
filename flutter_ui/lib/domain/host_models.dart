import 'json_utils.dart';

final class ClientIdentity {
  static const int currentSchemaVersion = 1;

  const ClientIdentity({
    this.schemaVersion = currentSchemaVersion,
    required this.clientUid,
    required this.certificatePem,
    required this.privateKeyPem,
    this.createdAt,
  });

  final int schemaVersion;
  final String clientUid;
  final String certificatePem;
  final String privateKeyPem;
  final DateTime? createdAt;

  bool get hasCertificate =>
      certificatePem.isNotEmpty && privateKeyPem.isNotEmpty;

  factory ClientIdentity.fromJson(Map<String, Object?> json) => ClientIdentity(
    schemaVersion: jsonInt(json['schemaVersion'], currentSchemaVersion),
    clientUid: jsonString(json['clientUid'] ?? json['uniqueId']),
    certificatePem: jsonString(json['certificatePem'] ?? json['certificate']),
    privateKeyPem: jsonString(json['privateKeyPem'] ?? json['privateKey']),
    createdAt: jsonDateTime(json['createdAt']),
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'clientUid': clientUid,
    'certificatePem': certificatePem,
    'privateKeyPem': privateKeyPem,
    'createdAt': createdAt?.toIso8601String(),
  };
}

/// Stable, persisted host data. Reachability, pairing state, running games and
/// server versions deliberately live in [HostStatus] and are never persisted.
final class SavedHost {
  static const int currentSchemaVersion = 1;
  static const int defaultHttpPort = 47989;
  static const int defaultHttpsPort = 47984;

  const SavedHost({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    this.serverUid = '',
    required this.hostname,
    required this.address,
    this.userEnteredAddress = '',
    this.localAddress = '',
    this.externalAddress = '',
    this.macAddress = '',
    this.httpPort = defaultHttpPort,
    this.httpsPort = defaultHttpsPort,
    this.externalPort = defaultHttpPort,
    this.pinnedCertificate = '',
  });

  final int schemaVersion;
  final String id;
  final String serverUid;
  final String hostname;
  final String address;
  final String userEnteredAddress;
  final String localAddress;
  final String externalAddress;
  final String macAddress;
  final int httpPort;
  final int httpsPort;
  final int externalPort;
  final String pinnedCertificate;

  bool get hasPinnedCertificate => pinnedCertificate.isNotEmpty;

  factory SavedHost.fromJson(Map<String, Object?> json) {
    final httpPort = jsonInt(json['httpPort'], defaultHttpPort);
    final httpsPort = jsonInt(json['httpsPort'], httpPort - 5);
    return SavedHost(
      schemaVersion: jsonInt(json['schemaVersion'], currentSchemaVersion),
      id: jsonString(json['id'] ?? json['serverUid'] ?? json['serverUID']),
      serverUid: jsonString(json['serverUid'] ?? json['serverUID']),
      hostname: jsonString(json['hostname'], 'UNKNOWN'),
      address: jsonString(json['address']),
      userEnteredAddress: jsonString(json['userEnteredAddress']),
      localAddress: jsonString(json['localAddress']),
      externalAddress: jsonString(
        json['externalAddress'] ?? json['externalIP'],
      ),
      macAddress: jsonString(json['macAddress']),
      httpPort: httpPort > 0 ? httpPort : defaultHttpPort,
      httpsPort: httpsPort > 0 ? httpsPort : defaultHttpsPort,
      externalPort: jsonInt(json['externalPort'], httpPort),
      pinnedCertificate: jsonString(
        json['pinnedCertificate'] ?? json['ppkstr'],
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'id': id,
    'serverUid': serverUid,
    'hostname': hostname,
    'address': address,
    'userEnteredAddress': userEnteredAddress,
    'localAddress': localAddress,
    'externalAddress': externalAddress,
    'macAddress': macAddress,
    'httpPort': httpPort,
    'httpsPort': httpsPort,
    'externalPort': externalPort,
    'pinnedCertificate': pinnedCertificate,
  };

  SavedHost copyWith({
    String? id,
    String? serverUid,
    String? hostname,
    String? address,
    String? userEnteredAddress,
    String? localAddress,
    String? externalAddress,
    String? macAddress,
    int? httpPort,
    int? httpsPort,
    int? externalPort,
    String? pinnedCertificate,
  }) => SavedHost(
    id: id ?? this.id,
    serverUid: serverUid ?? this.serverUid,
    hostname: hostname ?? this.hostname,
    address: address ?? this.address,
    userEnteredAddress: userEnteredAddress ?? this.userEnteredAddress,
    localAddress: localAddress ?? this.localAddress,
    externalAddress: externalAddress ?? this.externalAddress,
    macAddress: macAddress ?? this.macAddress,
    httpPort: httpPort ?? this.httpPort,
    httpsPort: httpsPort ?? this.httpsPort,
    externalPort: externalPort ?? this.externalPort,
    pinnedCertificate: pinnedCertificate ?? this.pinnedCertificate,
  );
}

final class DisplayMode {
  const DisplayMode({
    required this.width,
    required this.height,
    required this.refreshRate,
  });

  final int width;
  final int height;
  final int refreshRate;

  String get key => '$height:$width';

  factory DisplayMode.fromJson(Map<String, Object?> json) => DisplayMode(
    width: jsonInt(json['width']),
    height: jsonInt(json['height']),
    refreshRate: jsonInt(json['refreshRate']),
  );

  Map<String, Object?> toJson() => {
    'width': width,
    'height': height,
    'refreshRate': refreshRate,
  };

  @override
  bool operator ==(Object other) =>
      other is DisplayMode &&
      width == other.width &&
      height == other.height &&
      refreshRate == other.refreshRate;

  @override
  int get hashCode => Object.hash(width, height, refreshRate);
}

/// The latest non-persisted observation for a saved host.
final class HostStatus {
  const HostStatus({
    this.online = false,
    this.paired = false,
    this.currentGameId = 0,
    this.appVersion = '',
    this.gfeVersion = '',
    this.serverMajorVersion = 0,
    this.serverState = '',
    this.isNvidiaServerSoftware = false,
    this.gpuType = '',
    this.serverCodecModeSupport = 0,
    this.numberOfApps = 0,
    this.displayModes = const <DisplayMode>[],
    this.consecutivePollFailures = 0,
    this.successfulPollCount = 0,
    this.lastSeenAt,
  });

  final bool online;
  final bool paired;
  final int currentGameId;
  final String appVersion;
  final String gfeVersion;
  final int serverMajorVersion;
  final String serverState;
  final bool isNvidiaServerSoftware;
  final String gpuType;
  final int serverCodecModeSupport;
  final int numberOfApps;
  final List<DisplayMode> displayModes;
  final int consecutivePollFailures;
  final int successfulPollCount;
  final DateTime? lastSeenAt;

  bool supportsMode(int width, int height, int fps) => displayModes.any(
    (mode) =>
        mode.width == width && mode.height == height && mode.refreshRate == fps,
  );

  HostStatus afterFailure() {
    final failures = consecutivePollFailures + 1;
    return copyWith(
      consecutivePollFailures: failures,
      online: failures >= 2 ? false : online,
    );
  }

  HostStatus copyWith({
    bool? online,
    bool? paired,
    int? currentGameId,
    String? appVersion,
    String? gfeVersion,
    int? serverMajorVersion,
    String? serverState,
    bool? isNvidiaServerSoftware,
    String? gpuType,
    int? serverCodecModeSupport,
    int? numberOfApps,
    List<DisplayMode>? displayModes,
    int? consecutivePollFailures,
    int? successfulPollCount,
    DateTime? lastSeenAt,
  }) => HostStatus(
    online: online ?? this.online,
    paired: paired ?? this.paired,
    currentGameId: currentGameId ?? this.currentGameId,
    appVersion: appVersion ?? this.appVersion,
    gfeVersion: gfeVersion ?? this.gfeVersion,
    serverMajorVersion: serverMajorVersion ?? this.serverMajorVersion,
    serverState: serverState ?? this.serverState,
    isNvidiaServerSoftware:
        isNvidiaServerSoftware ?? this.isNvidiaServerSoftware,
    gpuType: gpuType ?? this.gpuType,
    serverCodecModeSupport:
        serverCodecModeSupport ?? this.serverCodecModeSupport,
    numberOfApps: numberOfApps ?? this.numberOfApps,
    displayModes: List.unmodifiable(displayModes ?? this.displayModes),
    consecutivePollFailures:
        consecutivePollFailures ?? this.consecutivePollFailures,
    successfulPollCount: successfulPollCount ?? this.successfulPollCount,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
  );

  Map<String, Object?> toJson() => {
    'online': online,
    'paired': paired,
    'currentGameId': currentGameId,
    'appVersion': appVersion,
    'gfeVersion': gfeVersion,
    'serverMajorVersion': serverMajorVersion,
    'serverState': serverState,
    'isNvidiaServerSoftware': isNvidiaServerSoftware,
    'gpuType': gpuType,
    'serverCodecModeSupport': serverCodecModeSupport,
    'numberOfApps': numberOfApps,
    'displayModes': displayModes.map((mode) => mode.toJson()).toList(),
    'consecutivePollFailures': consecutivePollFailures,
    'successfulPollCount': successfulPollCount,
    'lastSeenAt': lastSeenAt?.toIso8601String(),
  };
}

final class MoonlightApp {
  static const int currentSchemaVersion = 1;

  const MoonlightApp({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    required this.title,
  });

  final int schemaVersion;
  final int id;
  final String title;
  String get boxArtCacheKey => 'boxart-$id';

  factory MoonlightApp.fromJson(Map<String, Object?> json) => MoonlightApp(
    schemaVersion: jsonInt(json['schemaVersion'], currentSchemaVersion),
    id: jsonInt(json['id'] ?? json['ID']),
    title: jsonString(json['title'] ?? json['AppTitle']),
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'id': id,
    'title': title,
  };
}

/// Parsed protocol result before it is split into persisted and transient data.
final class ServerInfo {
  const ServerInfo({
    required this.serverUid,
    required this.hostname,
    this.localAddress = '',
    this.externalAddress = '',
    this.macAddress = '',
    this.httpsPort = SavedHost.defaultHttpsPort,
    this.externalPort = SavedHost.defaultHttpPort,
    this.paired = false,
    this.appVersion = '',
    this.gfeVersion = '',
    this.serverMajorVersion = 0,
    this.serverCodecModeSupport = 0,
    this.serverState = '',
    this.isNvidiaServerSoftware = false,
    this.gpuType = '',
    this.numberOfApps = 0,
    this.currentGameId = 0,
    this.displayModes = const <DisplayMode>[],
  });

  final String serverUid;
  final String hostname;
  final String localAddress;
  final String externalAddress;
  final String macAddress;
  final int httpsPort;
  final int externalPort;
  final bool paired;
  final String appVersion;
  final String gfeVersion;
  final int serverMajorVersion;
  final int serverCodecModeSupport;
  final String serverState;
  final bool isNvidiaServerSoftware;
  final String gpuType;
  final int numberOfApps;
  final int currentGameId;
  final List<DisplayMode> displayModes;

  HostStatus toStatus({required HostStatus previous, required DateTime now}) =>
      HostStatus(
        online: true,
        paired: paired,
        currentGameId: currentGameId,
        appVersion: appVersion,
        gfeVersion: gfeVersion,
        serverMajorVersion: serverMajorVersion,
        serverState: serverState,
        isNvidiaServerSoftware: isNvidiaServerSoftware,
        gpuType: gpuType,
        serverCodecModeSupport: serverCodecModeSupport,
        numberOfApps: numberOfApps,
        displayModes: List.unmodifiable(displayModes),
        successfulPollCount: previous.successfulPollCount + 1,
        consecutivePollFailures: 0,
        lastSeenAt: now,
      );
}

final class HostRefreshResult {
  const HostRefreshResult({
    required this.host,
    required this.status,
    required this.serverInfo,
  });

  final SavedHost host;
  final HostStatus status;
  final ServerInfo serverInfo;
}

final class PairingResult {
  const PairingResult({
    required this.host,
    required this.status,
    required this.paired,
  });

  final SavedHost host;
  final HostStatus status;
  final bool paired;
}
