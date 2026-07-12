import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonlight_tizen_flutter/data/native/moonlight_native.dart';
import 'package:moonlight_tizen_flutter/data/native/production_native.dart';
import 'package:moonlight_tizen_flutter/data/nvhttp_client.dart';
import 'package:moonlight_tizen_flutter/domain/domain.dart';

void main() {
  group('createNativeProductionBundle', () {
    test(
      'reuses a saved identity and initializes a shared repository',
      () async {
        final runtime = _FakeNativeRuntime();
        const identity = ClientIdentity(
          clientUid: '0123456789abcdef',
          certificatePem: 'certificate',
          privateKeyPem: 'private-key',
        );

        final bundle = await createNativeProductionBundle(
          identity: identity,
          runtime: runtime,
          uuidFactory: () => 'request-uuid',
        );

        expect(runtime.initializeCalls, 1);
        expect(runtime.makeCertificateCalls, 0);
        expect(runtime.initializedIdentity, same(identity));
        expect(bundle.identity, same(identity));
        expect(bundle.generatedIdentity, isFalse);
        expect(bundle.repository, isA<NvHttpClient>());
        expect(
          (bundle.repository as NvHttpClient).requests.clientUid,
          identity.clientUid,
        );
        expect(bundle.overrides, hasLength(5));

        bundle.dispose();
        expect(runtime.disposed, isTrue);
      },
    );

    test(
      'generates missing credentials with the requested client UID',
      () async {
        final runtime = _FakeNativeRuntime();

        final bundle = await createNativeProductionBundle(
          clientUid: 'fedcba9876543210',
          runtime: runtime,
        );

        expect(runtime.makeCertificateCalls, 1);
        expect(bundle.generatedIdentity, isTrue);
        expect(bundle.identity.clientUid, 'fedcba9876543210');
        expect(bundle.identity.hasCertificate, isTrue);
        expect(runtime.initializedIdentity, bundle.identity);
      },
    );
  });

  test('the non-web conditional adapter is safe and unavailable', () {
    final runtime = createMoonlightNativeRuntime();
    expect(runtime.isAvailable, isFalse);
    expect(runtime.connectedGamepadMask(), 0);
    expect(runtime.unlockAudio(), isFalse);
  });
}

final class _FakeNativeRuntime implements MoonlightNativeRuntime {
  int initializeCalls = 0;
  int makeCertificateCalls = 0;
  ClientIdentity? initializedIdentity;
  bool disposed = false;

  @override
  bool get isAvailable => true;

  @override
  Stream<StreamEvent> get events => const Stream<StreamEvent>.empty();

  @override
  Stream<NativeInputEvent> get inputEvents =>
      const Stream<NativeInputEvent>.empty();

  @override
  Future<NativeRuntimeInfo> initialize() async {
    initializeCalls += 1;
    return NativeRuntimeInfo(
      ready: true,
      bridgeVersion: 1,
      capabilities: PlatformCapabilities.tizen10(),
    );
  }

  @override
  Future<ClientIdentity> makeCertificate({required String clientUid}) async {
    makeCertificateCalls += 1;
    return ClientIdentity(
      clientUid: clientUid,
      certificatePem: 'generated-certificate',
      privateKeyPem: 'generated-private-key',
    );
  }

  @override
  Future<void> httpInit(ClientIdentity identity) async {
    initializedIdentity = identity;
  }

  @override
  Future<String> openText(Uri uri, {String? pinnedCertificate}) async =>
      '<root status_code="200"/>';

  @override
  Future<Uint8List> openBinary(Uri uri, {String? pinnedCertificate}) async =>
      Uint8List(0);

  @override
  Future<String> pair({
    required int serverMajorVersion,
    required String address,
    required int httpPort,
    required String pin,
    required String uniqueId,
  }) async => 'pin';

  @override
  Future<String?> stun() async => null;

  @override
  Future<void> wakeOnLan(String macAddress) async {}

  @override
  Future<List<String>> scanLocalSubnet({
    Duration timeout = const Duration(milliseconds: 1800),
  }) async => const <String>[];

  @override
  bool unlockAudio() => true;

  @override
  Future<StreamEvent> startStream(StreamRequest request) async =>
      const StreamEvent(kind: StreamEventKind.lifecycle, name: 'streaming');

  @override
  Future<void> stopStream() async {}

  @override
  Future<void> toggleStats() async {}

  @override
  Future<Map<String, Object?>> probeVideoCodecSupport(
    Map<String, Object?> request,
  ) async => const <String, Object?>{};

  @override
  NativeInputMode setInputMode(NativeInputMode mode) => mode;

  @override
  int connectedGamepadMask() => 0;

  @override
  List<NativeInputDevice> inputDevices() => const <NativeInputDevice>[];

  @override
  bool testRumble(int browserIndex) => false;

  @override
  bool sendEscape() => true;

  @override
  bool restartApp() => true;

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
  String diagnosticQrSvg(String value) => '<svg></svg>';

  @override
  String getIpAddress() => '192.168.1.2';

  @override
  Future<Map<String, Object?>> startLogExportServer({
    required String payload,
    required String filename,
    required String token,
    int requestedPort = 0,
  }) async => const {'port': 1234, 'path': '/log'};

  @override
  Future<void> stopLogExportServer() async {}

  @override
  void dispose() {
    disposed = true;
  }
}
