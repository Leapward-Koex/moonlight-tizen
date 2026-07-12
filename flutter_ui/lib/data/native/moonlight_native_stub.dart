import 'dart:async';
import 'dart:typed_data';

import '../../domain/host_models.dart';
import '../../domain/stream_models.dart';
import 'native_runtime.dart';

MoonlightNativeRuntime createMoonlightNativeRuntime() =>
    const UnsupportedMoonlightNativeRuntime();

final class UnsupportedMoonlightNativeRuntime
    implements MoonlightNativeRuntime {
  const UnsupportedMoonlightNativeRuntime();

  Never _unsupported() => throw UnsupportedError(
    'MoonlightNative is available only in the production web application.',
  );

  @override
  bool get isAvailable => false;

  @override
  Stream<StreamEvent> get events => const Stream<StreamEvent>.empty();

  @override
  Stream<NativeInputEvent> get inputEvents =>
      const Stream<NativeInputEvent>.empty();

  @override
  Future<NativeRuntimeInfo> initialize() async => _unsupported();

  @override
  Future<ClientIdentity> makeCertificate({required String clientUid}) async =>
      _unsupported();

  @override
  Future<void> httpInit(ClientIdentity identity) async => _unsupported();

  @override
  Future<String> openText(Uri uri, {String? pinnedCertificate}) async =>
      _unsupported();

  @override
  Future<Uint8List> openBinary(Uri uri, {String? pinnedCertificate}) async =>
      _unsupported();

  @override
  Future<String> pair({
    required int serverMajorVersion,
    required String address,
    required int httpPort,
    required String pin,
    required String uniqueId,
  }) async => _unsupported();

  @override
  Future<String?> stun() async => _unsupported();

  @override
  Future<void> wakeOnLan(String macAddress) async => _unsupported();

  @override
  Future<List<String>> scanLocalSubnet({
    Duration timeout = const Duration(milliseconds: 1800),
  }) async => const <String>[];

  @override
  bool unlockAudio() => false;

  @override
  Future<StreamEvent> startStream(StreamRequest request) async =>
      _unsupported();

  @override
  Future<void> stopStream() async => _unsupported();

  @override
  Future<void> toggleStats() async => _unsupported();

  @override
  Future<Map<String, Object?>> probeVideoCodecSupport(
    Map<String, Object?> request,
  ) async => _unsupported();

  @override
  NativeInputMode setInputMode(NativeInputMode mode) => mode;

  @override
  int connectedGamepadMask() => 0;

  @override
  List<NativeInputDevice> inputDevices() => const <NativeInputDevice>[];

  @override
  bool testRumble(int browserIndex) => false;

  @override
  bool sendEscape() => false;

  @override
  bool restartApp() => false;

  @override
  String setDiagnosticLogLevel(String level) => level;

  @override
  void logDiagnostic(
    String level,
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {}

  @override
  Map<String, Object?> diagnosticLogStatus() => const {
    'level': 'off',
    'entryCount': 0,
    'bytes': 0,
  };

  @override
  Future<String> diagnosticLogs() async => '';

  @override
  Future<Map<String, Object?>> clearDiagnosticLogs() async =>
      diagnosticLogStatus();

  @override
  String diagnosticQrSvg(String value) => '';

  @override
  String getIpAddress() => '';

  @override
  Future<Map<String, Object?>> startLogExportServer({
    required String payload,
    required String filename,
    required String token,
    int requestedPort = 0,
  }) async => _unsupported();

  @override
  Future<void> stopLogExportServer() async => _unsupported();

  @override
  void dispose() {}
}
