import 'dart:async';

import '../../domain/contracts.dart';
import '../../domain/host_models.dart';
import '../../domain/json_utils.dart';
import '../../domain/platform_capabilities.dart';
import '../../domain/stream_models.dart';

enum NativeInputMode { ui, stream, disabled }

final class NativeRuntimeInfo {
  const NativeRuntimeInfo({
    required this.ready,
    required this.bridgeVersion,
    required this.capabilities,
    this.raw = const <String, Object?>{},
  });

  final bool ready;
  final int bridgeVersion;
  final PlatformCapabilities capabilities;
  final Map<String, Object?> raw;

  factory NativeRuntimeInfo.fromJson(Map<String, Object?> json) {
    final platform = jsonMap(json['platform']);
    final isTizen = jsonBool(platform['isTizen']);
    final platformVersion = jsonString(platform['platformVersion']);
    final maximumWidth = jsonInt(platform['maximumWidth'], 1920);
    final maximumHeight = jsonInt(platform['maximumHeight'], 1080);
    return NativeRuntimeInfo(
      ready: jsonBool(json['ready'], true),
      bridgeVersion: jsonInt(json['bridgeVersion'], 1),
      capabilities: PlatformCapabilities(
        platform: isTizen ? 'tizen' : 'browser',
        platformVersion: platformVersion,
        maxWidth: maximumWidth,
        maxHeight: maximumHeight,
        supportsHdr: jsonBool(platform['isHdrCapable']),
        supportsGameMode: isTizen,
        supportsRumble: isTizen,
        supportsPointerLock: true,
        supportsRestart: isTizen,
        supportsNativeAudio:
            isTizen &&
            jsonBool(
              platform['supportsNativeAudio'],
              jsonBool(platform['supportsNativeStreaming']),
            ),
        supportedCodecs: isTizen
            ? const {VideoCodec.h264, VideoCodec.hevc, VideoCodec.av1}
            : const {VideoCodec.h264},
      ),
      raw: Map.unmodifiable(json),
    );
  }
}

final class NativeInputEvent {
  const NativeInputEvent({
    required this.type,
    this.action = '',
    this.phase = '',
    this.source = '',
    this.gamepadIndex,
    this.connectedMask,
    this.data = const <String, Object?>{},
  });

  final String type;
  final String action;
  final String phase;
  final String source;
  final int? gamepadIndex;
  final int? connectedMask;
  final Map<String, Object?> data;

  factory NativeInputEvent.fromJson(Map<String, Object?> json) =>
      NativeInputEvent(
        type: jsonString(json['type']),
        action: jsonString(json['action']),
        phase: jsonString(json['phase']),
        source: jsonString(json['source']),
        gamepadIndex: json['gamepadIndex'] == null
            ? null
            : jsonInt(json['gamepadIndex']),
        connectedMask: json['connectedMask'] == null
            ? null
            : jsonInt(json['connectedMask']),
        data: Map.unmodifiable(json),
      );
}

final class NativeInputDevice {
  const NativeInputDevice({
    required this.slot,
    required this.browserIndex,
    required this.fingerprint,
    required this.id,
    required this.mapping,
    required this.buttonCount,
    required this.axisCount,
    required this.supportsRumble,
    this.pressedButtons = const <int>[],
    this.axes = const <double>[],
  });

  final int slot;
  final int browserIndex;
  final String fingerprint;
  final String id;
  final String mapping;
  final int buttonCount;
  final int axisCount;
  final bool supportsRumble;
  final List<int> pressedButtons;
  final List<double> axes;

  factory NativeInputDevice.fromJson(Map<String, Object?> json) =>
      NativeInputDevice(
        slot: jsonInt(json['slot']),
        browserIndex: jsonInt(json['browserIndex']),
        fingerprint: jsonString(json['fingerprint']),
        id: jsonString(json['id'], 'Controller'),
        mapping: jsonString(json['mapping'], 'unknown'),
        buttonCount: jsonInt(json['buttonCount']),
        axisCount: jsonInt(json['axisCount']),
        supportsRumble: jsonBool(json['supportsRumble']),
        pressedButtons: jsonList(
          json['pressedButtons'],
        ).map(jsonInt).toList(growable: false),
        axes: jsonList(json['axes']).map(jsonDouble).toList(growable: false),
      );
}

/// Typed Dart boundary around `window.MoonlightNative`.
///
/// The runtime also implements the three protocol gateways so one instance is
/// shared by [NvHttpClient] and stream lifecycle orchestration.
abstract interface class MoonlightNativeRuntime
    implements
        MoonlightHttpTransport,
        PairingGateway,
        NetworkDiscoveryGateway,
        SubnetDiscoveryGateway {
  bool get isAvailable;

  Stream<StreamEvent> get events;
  Stream<NativeInputEvent> get inputEvents;

  Future<NativeRuntimeInfo> initialize();

  Future<ClientIdentity> makeCertificate({required String clientUid});

  Future<void> httpInit(ClientIdentity identity);

  /// Starts Web Audio synchronously. Invoke directly inside Launch/Resume's
  /// user gesture before awaiting host protocol work.
  bool unlockAudio();

  Future<StreamEvent> startStream(StreamRequest request);
  Future<void> stopStream();
  void recoverStreamSurface();
  Future<void> toggleStats();

  Future<Map<String, Object?>> probeVideoCodecSupport(
    Map<String, Object?> request,
  );

  NativeInputMode setInputMode(NativeInputMode mode);
  int connectedGamepadMask();
  List<NativeInputDevice> inputDevices();
  bool testRumble(int browserIndex);
  bool sendEscape();
  bool restartApp();
  String setDiagnosticLogLevel(String level);
  void logDiagnostic(
    String level,
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]);
  Map<String, Object?> diagnosticLogStatus();
  Future<String> diagnosticLogs();
  Future<Map<String, Object?>> clearDiagnosticLogs();
  String diagnosticQrSvg(String value);
  String getIpAddress();
  Future<Map<String, Object?>> startLogExportServer({
    required String payload,
    required String filename,
    required String token,
    int requestedPort = 0,
  });
  Future<void> stopLogExportServer();

  void dispose();
}
