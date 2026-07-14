import 'app_settings.dart';
import 'build_variant.dart';
import 'host_models.dart';
import 'json_utils.dart';
import 'platform_capabilities.dart';

final class RemoteInputCredentials {
  const RemoteInputCredentials({required this.key, required this.keyId});

  final String key;
  final int keyId;

  factory RemoteInputCredentials.fromJson(Map<String, Object?> json) =>
      RemoteInputCredentials(
        key: jsonString(json['key']),
        keyId: jsonInt(json['keyId']),
      );

  Map<String, Object?> toJson() => {'key': key, 'keyId': keyId};
}

final class HostLaunchRequest {
  const HostLaunchRequest({
    this.appId,
    required this.mode,
    required this.optimizeGameSettings,
    required this.remoteInput,
    required this.hdr,
    required this.playAudioOnHost,
    this.surroundAudioInfo = 0x030002,
    required this.gamepadMask,
  });

  final int? appId;
  final String mode;
  final bool optimizeGameSettings;
  final RemoteInputCredentials remoteInput;
  final bool hdr;
  final bool playAudioOnHost;
  final int surroundAudioInfo;
  final int gamepadMask;
}

final class LaunchResult {
  const LaunchResult({
    required this.statusCode,
    this.statusMessage = '',
    this.sessionUrl = '',
  });

  final int statusCode;
  final String statusMessage;
  final String sessionUrl;
  bool get isSuccess => statusCode == 200 && sessionUrl.isNotEmpty;
}

/// Named replacement for the native runtime's historical positional
/// arguments. [toJson] is passed unchanged to `MoonlightNative.startStream`.
final class StreamRequest {
  static const int currentSchemaVersion = 3;

  const StreamRequest({
    this.schemaVersion = currentSchemaVersion,
    required this.appId,
    required this.appTitle,
    required this.hostAddress,
    required this.hostHttpPort,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.bitrateKbps,
    required this.remoteInput,
    required this.appVersion,
    required this.gfeVersion,
    required this.sessionUrl,
    required this.serverCodecModeSupport,
    required this.framePacing,
    required this.optimizeGameSettings,
    required this.rumbleFeedback,
    required this.mouseEmulation,
    required this.flipAbButtons,
    required this.flipXyButtons,
    this.inputConfiguration = const <String, Object?>{},
    required this.audioBackend,
    required this.audioConfiguration,
    required this.audioPacketDurationMs,
    required this.audioJitterBufferMs,
    required this.playAudioOnHost,
    required this.videoCodec,
    required this.hdr,
    required this.fullColorRange,
    required this.gameMode,
    required this.disableConnectionWarnings,
    required this.showPerformanceStats,
    this.disabledCodecMimeTypes = const <String>[],
  });

  final int schemaVersion;
  final int appId;
  final String appTitle;
  final String hostAddress;
  final int hostHttpPort;
  final int width;
  final int height;
  final int frameRate;
  final int bitrateKbps;
  final RemoteInputCredentials remoteInput;
  final String appVersion;
  final String gfeVersion;
  final String sessionUrl;
  final int serverCodecModeSupport;
  final bool framePacing;
  final bool optimizeGameSettings;
  final bool rumbleFeedback;
  final bool mouseEmulation;
  final bool flipAbButtons;
  final bool flipXyButtons;
  final Map<String, Object?> inputConfiguration;
  final AudioBackend audioBackend;
  final AudioConfiguration audioConfiguration;
  final int audioPacketDurationMs;
  final int audioJitterBufferMs;
  final bool playAudioOnHost;
  final VideoCodec videoCodec;
  final bool hdr;
  final bool fullColorRange;
  final bool gameMode;
  final bool disableConnectionWarnings;
  final bool showPerformanceStats;
  final List<String> disabledCodecMimeTypes;

  factory StreamRequest.fromSettings({
    required MoonlightApp app,
    required SavedHost host,
    required HostStatus hostStatus,
    required AppSettings settings,
    required RemoteInputCredentials remoteInput,
    required String sessionUrl,
    required Iterable<String> disabledCodecMimeTypes,
  }) => StreamRequest(
    appId: app.id,
    appTitle: app.title,
    hostAddress: host.address,
    hostHttpPort: host.httpPort,
    width: settings.resolution.width,
    height: settings.resolution.height,
    frameRate: settings.frameRate,
    bitrateKbps: settings.bitrateKbps,
    remoteInput: remoteInput,
    appVersion: hostStatus.appVersion,
    gfeVersion: hostStatus.gfeVersion,
    sessionUrl: sessionUrl,
    serverCodecModeSupport: hostStatus.serverCodecModeSupport,
    framePacing: settings.framePacing,
    optimizeGameSettings: settings.optimizeGameSettings,
    rumbleFeedback: settings.rumbleFeedback,
    mouseEmulation: settings.mouseEmulation,
    flipAbButtons: settings.flipAbButtons,
    flipXyButtons: settings.flipXyButtons,
    inputConfiguration: settings.toInputConfigurationJson(),
    audioBackend: settings.audioBackend,
    audioConfiguration: settings.audioConfiguration,
    audioPacketDurationMs: settings.audioBackend == AudioBackend.nativeEmss
        ? 20
        : settings.audioPacketDurationMs,
    audioJitterBufferMs: settings.audioJitterBufferMs,
    playAudioOnHost: settings.playAudioOnHost,
    videoCodec: settings.videoCodec,
    hdr: settings.hdr,
    fullColorRange: settings.fullColorRange,
    gameMode: kForceGameMode || settings.gameMode,
    disableConnectionWarnings: settings.disableConnectionWarnings,
    showPerformanceStats: settings.showPerformanceStats,
    disabledCodecMimeTypes: List.unmodifiable(disabledCodecMimeTypes),
  );

  factory StreamRequest.fromJson(Map<String, Object?> json) => StreamRequest(
    schemaVersion: jsonInt(json['schemaVersion'], currentSchemaVersion),
    appId: jsonInt(json['appId']),
    appTitle: jsonString(json['appTitle']),
    hostAddress: jsonString(json['hostAddress'] ?? json['host']),
    hostHttpPort: jsonInt(json['hostHttpPort'] ?? json['httpPort']),
    width: jsonInt(json['width']),
    height: jsonInt(json['height']),
    frameRate: jsonInt(json['frameRate'] ?? json['fps']),
    bitrateKbps: jsonInt(json['bitrateKbps']),
    remoteInput: RemoteInputCredentials.fromJson(
      jsonMap(json['remoteInput']).isNotEmpty
          ? jsonMap(json['remoteInput'])
          : {'key': json['remoteInputKey'], 'keyId': json['remoteInputKeyId']},
    ),
    appVersion: jsonString(json['appVersion']),
    gfeVersion: jsonString(json['gfeVersion']),
    sessionUrl: jsonString(json['sessionUrl']),
    serverCodecModeSupport: jsonInt(json['serverCodecModeSupport']),
    framePacing: jsonBool(json['framePacing']),
    optimizeGameSettings: jsonBool(json['optimizeGameSettings']),
    rumbleFeedback: jsonBool(json['rumbleFeedback']),
    mouseEmulation: jsonBool(json['mouseEmulation']),
    flipAbButtons: jsonBool(json['flipAbButtons']),
    flipXyButtons: jsonBool(json['flipXyButtons']),
    inputConfiguration: Map.unmodifiable(jsonMap(json['inputConfiguration'])),
    audioBackend: AudioBackend.fromWireName(
      jsonString(json['audioBackend'], AudioBackend.webAudio.wireName),
    ),
    audioConfiguration: AudioConfiguration.fromWireName(
      jsonString(json['audioConfiguration'], 'Stereo'),
    ),
    audioPacketDurationMs: jsonInt(json['audioPacketDurationMs']),
    audioJitterBufferMs: jsonInt(json['audioJitterBufferMs'], 100),
    playAudioOnHost: jsonBool(json['playAudioOnHost']),
    videoCodec:
        VideoCodec.fromWireName(jsonString(json['videoCodec'], 'H264')) ??
        VideoCodec.h264,
    hdr: jsonBool(json['hdr']),
    fullColorRange: jsonBool(json['fullColorRange']),
    gameMode: jsonBool(json['gameMode']),
    disableConnectionWarnings: jsonBool(json['disableConnectionWarnings']),
    showPerformanceStats: jsonBool(json['showPerformanceStats']),
    disabledCodecMimeTypes: jsonList(json['disabledCodecMimeTypes'])
        .map(jsonString)
        .where((value) => value.isNotEmpty)
        .toList(growable: false),
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'appId': appId,
    'appTitle': appTitle,
    'hostAddress': hostAddress,
    'hostHttpPort': hostHttpPort,
    'width': width,
    'height': height,
    'frameRate': frameRate,
    'bitrateKbps': bitrateKbps,
    'remoteInputKey': remoteInput.key,
    'remoteInputKeyId': remoteInput.keyId,
    'appVersion': appVersion,
    'gfeVersion': gfeVersion,
    'sessionUrl': sessionUrl,
    'serverCodecModeSupport': serverCodecModeSupport,
    'framePacing': framePacing,
    'optimizeGameSettings': optimizeGameSettings,
    'rumbleFeedback': rumbleFeedback,
    'mouseEmulation': mouseEmulation,
    'flipAbButtons': flipAbButtons,
    'flipXyButtons': flipXyButtons,
    'inputConfiguration': inputConfiguration,
    'audioBackend': audioBackend.wireName,
    'audioConfiguration': audioConfiguration.wireName,
    'audioPacketDurationMs': audioPacketDurationMs,
    'audioJitterBufferMs': audioJitterBufferMs,
    'playAudioOnHost': playAudioOnHost,
    'videoCodec': videoCodec.wireName,
    'hdr': hdr,
    'fullColorRange': fullColorRange,
    'gameMode': gameMode,
    'disableConnectionWarnings': disableConnectionWarnings,
    'showPerformanceStats': showPerformanceStats,
    'disabledCodecMimeTypes': disabledCodecMimeTypes,
  };
}

enum StreamSessionPhase {
  idle,
  preparing,
  launching,
  connecting,
  streaming,
  stopping,
  stopped,
  failed,
}

final class StreamSessionState {
  const StreamSessionState({
    this.phase = StreamSessionPhase.idle,
    this.attemptId,
    this.request,
    this.message = '',
    this.error,
    this.startedAt,
  });

  final StreamSessionPhase phase;
  final String? attemptId;
  final StreamRequest? request;
  final String message;
  final MoonlightRuntimeError? error;
  final DateTime? startedAt;

  bool get isActive => switch (phase) {
    StreamSessionPhase.preparing ||
    StreamSessionPhase.launching ||
    StreamSessionPhase.connecting ||
    StreamSessionPhase.streaming ||
    StreamSessionPhase.stopping => true,
    _ => false,
  };

  StreamSessionState copyWith({
    StreamSessionPhase? phase,
    String? attemptId,
    StreamRequest? request,
    String? message,
    MoonlightRuntimeError? error,
    DateTime? startedAt,
  }) => StreamSessionState(
    phase: phase ?? this.phase,
    attemptId: attemptId ?? this.attemptId,
    request: request ?? this.request,
    message: message ?? this.message,
    error: error ?? this.error,
    startedAt: startedAt ?? this.startedAt,
  );
}

enum StreamEventKind {
  readiness,
  lifecycle,
  progress,
  warning,
  statistics,
  codecProfile,
  audioPolicy,
  rumble,
  mouseEmulation,
}

final class StreamEvent {
  const StreamEvent({
    required this.kind,
    this.attemptId,
    this.name = '',
    this.message = '',
    this.data = const <String, Object?>{},
  });

  final StreamEventKind kind;
  final String? attemptId;
  final String name;
  final String message;
  final Map<String, Object?> data;

  factory StreamEvent.fromJson(Map<String, Object?> json) => StreamEvent(
    kind: StreamEventKind.values.firstWhere(
      (kind) => kind.name == jsonString(json['kind'] ?? json['type']),
      orElse: () => StreamEventKind.lifecycle,
    ),
    attemptId: json['attemptId']?.toString(),
    name: jsonString(json['name'] ?? json['event']),
    message: jsonString(json['message']),
    data: jsonMap(json['data'] ?? json['details']),
  );
}

final class MoonlightRuntimeError {
  const MoonlightRuntimeError({
    required this.code,
    required this.message,
    this.details = const <String, Object?>{},
  });

  final String code;
  final String message;
  final Map<String, Object?> details;

  factory MoonlightRuntimeError.fromJson(Map<String, Object?> json) =>
      MoonlightRuntimeError(
        code: jsonString(json['code'], 'unknown'),
        message: jsonString(json['message'], 'Unknown error'),
        details: jsonMap(json['details']),
      );

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'details': details,
  };
}
