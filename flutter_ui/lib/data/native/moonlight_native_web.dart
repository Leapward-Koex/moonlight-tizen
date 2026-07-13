import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import '../../domain/errors.dart';
import '../../domain/host_models.dart';
import '../../domain/json_utils.dart';
import '../../domain/stream_models.dart';
import 'native_runtime.dart';

@JS('MoonlightNative')
external JSObject? get _moonlightNativeObject;

extension type _MoonlightNativeFacade(JSObject _) implements JSObject {
  external JSBoolean isAvailable();
  external JSPromise<JSAny?> initialize();
  external JSPromise<JSAny?> makeCertificate();
  external JSPromise<JSAny?> httpInit(
    JSString certificate,
    JSString privateKey,
    JSString uniqueId,
  );
  external JSPromise<JSString> openText(JSString url, JSString? pin);
  external JSPromise<JSUint8Array> openBinary(JSString url, JSString? pin);
  external JSPromise<JSString> pair(
    JSString serverMajorVersion,
    JSString address,
    JSNumber httpPort,
    JSString pin,
    JSString uniqueId,
  );
  external JSPromise<JSString> stun();
  external JSPromise<JSAny?> wakeOnLan(JSString macAddress);
  external JSPromise<JSString> scanLocalSubnet(JSNumber timeoutMs);
  external JSPromise<JSAny?> startStream(JSAny request);
  external JSPromise<JSAny?> stopStream();
  external JSPromise<JSAny?> startSyntheticAudioTest(JSBoolean gameMode);
  external JSPromise<JSAny?> playSyntheticAudioClick(JSString inputLabel);
  external JSPromise<JSAny?> stopSyntheticAudioTest();
  external void recoverStreamSurface();
  external JSPromise<JSAny?> toggleStats();
  external JSPromise<JSAny?> probeVideoCodecSupport(JSAny request);
  external JSBoolean unlockAudio();
  external JSString setInputMode(JSString mode);
  external JSNumber connectedGamepadMask();
  external JSAny? inputDevices();
  external JSBoolean testRumble(JSNumber browserIndex);
  external JSBoolean sendEscape();
  external JSBoolean restartApp();
  external JSBoolean exitApp();
  external JSString setDiagnosticLogLevel(JSString level);
  external JSBoolean logDiagnostic(
    JSString level,
    JSString eventName,
    JSAny details,
  );
  external JSAny? getDiagnosticLogStatus();
  external JSPromise<JSString> getDiagnosticLogs();
  external JSPromise<JSAny?> clearDiagnosticLogs();
  external JSString getDiagnosticQrSvg(JSString value);
  external JSString getIpAddress();
  external JSPromise<JSAny?> startLogExportServer(
    JSString payload,
    JSString filename,
    JSString token,
    JSNumber requestedPort,
  );
  external JSPromise<JSAny?> stopLogExportServer();
  external JSAny? getPlatformInfo();
  external void setEventSink(JSFunction? callback);
  external void registerInputSink(JSFunction? callback);
}

MoonlightNativeRuntime createMoonlightNativeRuntime() =>
    WebMoonlightNativeRuntime();

final class WebMoonlightNativeRuntime implements MoonlightNativeRuntime {
  WebMoonlightNativeRuntime() {
    final object = _moonlightNativeObject;
    if (object == null) return;
    _facade = _MoonlightNativeFacade(object);
    _eventCallback = ((JSAny? value) {
      final json = _stringKeyedMap(value?.dartify());
      if (json.isNotEmpty && !_events.isClosed) {
        final event = _streamEvent(json);
        _events.add(event);
        if (event.kind != StreamEventKind.statistics &&
            event.kind != StreamEventKind.progress) {
          logDiagnostic(
            event.kind == StreamEventKind.warning ? 'warning' : 'info',
            'native.event.${event.kind.name}',
            {
              'name': event.name,
              'attemptId': event.attemptId,
              'message': event.message,
              'data': event.data,
            },
          );
        }
      }
    }).toJS;
    _inputCallback = ((JSAny? value) {
      final json = _stringKeyedMap(value?.dartify());
      if (json.isNotEmpty && !_inputEvents.isClosed) {
        final event = NativeInputEvent.fromJson(json);
        _inputEvents.add(event);
        if (event.type != 'action' ||
            event.action == 'stop' ||
            event.action == 'toggleStats') {
          logDiagnostic('debug', 'native.input.${event.type}', {
            'action': event.action,
            'phase': event.phase,
            'source': event.source,
            'gamepadIndex': event.gamepadIndex,
            'connectedMask': event.connectedMask,
            'controlIndex': event.data['controlIndex'],
          });
        }
      }
    }).toJS;
    _facade!.setEventSink(_eventCallback);
    _facade!.registerInputSink(_inputCallback);
  }

  _MoonlightNativeFacade? _facade;
  JSFunction? _eventCallback;
  JSFunction? _inputCallback;
  final StreamController<StreamEvent> _events =
      StreamController<StreamEvent>.broadcast(sync: true);
  final StreamController<NativeInputEvent> _inputEvents =
      StreamController<NativeInputEvent>.broadcast(sync: true);

  _MoonlightNativeFacade get _native =>
      _facade ??
      (throw StateError(
        'window.MoonlightNative is missing. Ensure native/moonlight_native.js '
        'loads before flutter_bootstrap.js.',
      ));

  @override
  bool get isAvailable {
    try {
      return _facade?.isAvailable().toDart ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<StreamEvent> get events => _events.stream;

  @override
  Stream<NativeInputEvent> get inputEvents => _inputEvents.stream;

  @override
  Future<NativeRuntimeInfo> initialize() async {
    logDiagnostic('info', 'native.runtime.initialize_started');
    try {
      var json = _stringKeyedMap(
        (await _native.initialize().toDart)?.dartify(),
      );
      if (jsonMap(json['platform']).isEmpty) {
        json = {
          ...json,
          'platform': _stringKeyedMap(_native.getPlatformInfo()?.dartify()),
        };
      }
      final info = NativeRuntimeInfo.fromJson(json);
      logDiagnostic('info', 'native.runtime.initialize_succeeded', {
        'bridgeVersion': info.bridgeVersion,
        'platform': info.capabilities.platform,
        'platformVersion': info.capabilities.platformVersion,
        'maxWidth': info.capabilities.maxWidth,
        'maxHeight': info.capabilities.maxHeight,
        'supportsHdr': info.capabilities.supportsHdr,
        'supportsGameMode': info.capabilities.supportsGameMode,
      });
      return info;
    } catch (error) {
      logDiagnostic('error', 'native.runtime.initialize_failed', {
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
      });
      throw MoonlightException(
        'Unable to initialize the Moonlight native runtime.',
        cause: error,
      );
    }
  }

  @override
  Future<ClientIdentity> makeCertificate({required String clientUid}) async {
    logDiagnostic('info', 'native.identity.generate_started');
    try {
      final json = _stringKeyedMap(
        (await _native.makeCertificate().toDart)?.dartify(),
      );
      final certificate = jsonString(json['cert']);
      final privateKey = jsonString(json['privateKey']);
      if (certificate.isEmpty || privateKey.isEmpty) {
        throw const ProtocolException(
          'Native certificate generation returned incomplete credentials.',
        );
      }
      final identity = ClientIdentity(
        clientUid: clientUid,
        certificatePem: certificate,
        privateKeyPem: privateKey,
        createdAt: DateTime.now(),
      );
      logDiagnostic('info', 'native.identity.generate_succeeded');
      return identity;
    } catch (error) {
      if (error is MoonlightException) rethrow;
      throw MoonlightException(
        'Unable to generate the Moonlight client certificate.',
        cause: error,
      );
    }
  }

  @override
  Future<void> httpInit(ClientIdentity identity) async {
    if (!identity.hasCertificate || identity.clientUid.isEmpty) {
      throw const ProtocolException(
        'HTTP initialization requires a certificate, private key, and client UID.',
      );
    }
    logDiagnostic('info', 'native.http.initialize_started', {
      'hasCertificate': identity.hasCertificate,
      'hasClientUid': identity.clientUid.isNotEmpty,
    });
    try {
      await _native
          .httpInit(
            identity.certificatePem.toJS,
            identity.privateKeyPem.toJS,
            identity.clientUid.toJS,
          )
          .toDart;
      logDiagnostic('info', 'native.http.initialize_succeeded');
    } catch (error) {
      logDiagnostic('error', 'native.http.initialize_failed', {
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
      });
      throw MoonlightException(
        'Unable to initialize the native HTTP client.',
        cause: error,
      );
    }
  }

  @override
  Future<String> openText(Uri uri, {String? pinnedCertificate}) async {
    final stopwatch = Stopwatch()..start();
    logDiagnostic('debug', 'native.http.text_started', {
      'scheme': uri.scheme,
      'port': uri.port,
      'path': uri.path,
      'hasPinnedCertificate': pinnedCertificate?.isNotEmpty == true,
    });
    try {
      final value = await _native
          .openText(uri.toString().toJS, pinnedCertificate?.toJS)
          .toDart;
      final response = value.toDart;
      logDiagnostic('debug', 'native.http.text_succeeded', {
        'scheme': uri.scheme,
        'path': uri.path,
        'durationMs': stopwatch.elapsedMilliseconds,
        'responseChars': response.length,
      });
      return response;
    } catch (error) {
      logDiagnostic('error', 'native.http.text_failed', {
        'scheme': uri.scheme,
        'port': uri.port,
        'path': uri.path,
        'durationMs': stopwatch.elapsedMilliseconds,
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
      });
      throw _transportException(uri, error);
    }
  }

  @override
  Future<List<String>> scanLocalSubnet({
    Duration timeout = const Duration(milliseconds: 1800),
  }) async {
    final stopwatch = Stopwatch()..start();
    logDiagnostic('info', 'native.subnet_scan.started', {
      'timeoutMs': timeout.inMilliseconds,
    });
    try {
      final source =
          (await _native.scanLocalSubnet(timeout.inMilliseconds.toJS).toDart)
              .toDart;
      final decoded = jsonDecode(source);
      final addresses = decoded is List
          ? decoded
                .whereType<String>()
                .where(_isIpv4Address)
                .toSet()
                .toList(growable: false)
          : const <String>[];
      logDiagnostic('info', 'native.subnet_scan.completed', {
        'durationMs': stopwatch.elapsedMilliseconds,
        'responderCount': addresses.length,
      });
      return addresses;
    } catch (error) {
      logDiagnostic('warning', 'native.subnet_scan.failed', {
        'durationMs': stopwatch.elapsedMilliseconds,
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
      });
      return const <String>[];
    }
  }

  @override
  Future<Uint8List> openBinary(Uri uri, {String? pinnedCertificate}) async {
    final stopwatch = Stopwatch()..start();
    try {
      final value = await _native
          .openBinary(uri.toString().toJS, pinnedCertificate?.toJS)
          .toDart;
      final response = Uint8List.fromList(value.toDart);
      logDiagnostic('debug', 'native.http.binary_succeeded', {
        'path': uri.path,
        'durationMs': stopwatch.elapsedMilliseconds,
        'responseBytes': response.length,
      });
      return response;
    } catch (error) {
      logDiagnostic('error', 'native.http.binary_failed', {
        'path': uri.path,
        'durationMs': stopwatch.elapsedMilliseconds,
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
      });
      throw _transportException(uri, error);
    }
  }

  @override
  Future<String> pair({
    required int serverMajorVersion,
    required String address,
    required int httpPort,
    required String pin,
    required String uniqueId,
  }) async {
    final stopwatch = Stopwatch()..start();
    logDiagnostic('info', 'native.pair.started', {
      'serverMajorVersion': serverMajorVersion,
      'httpPort': httpPort,
    });
    try {
      final value = await _native
          .pair(
            '$serverMajorVersion'.toJS,
            address.toJS,
            httpPort.toJS,
            pin.toJS,
            uniqueId.toJS,
          )
          .toDart;
      final certificate = value.toDart;
      logDiagnostic('info', 'native.pair.succeeded', {
        'durationMs': stopwatch.elapsedMilliseconds,
        'credentialReturned': certificate.isNotEmpty,
      });
      return certificate;
    } catch (error) {
      logDiagnostic('error', 'native.pair.failed', {
        'durationMs': stopwatch.elapsedMilliseconds,
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
      });
      throw MoonlightException('Pairing failed.', cause: error);
    }
  }

  @override
  Future<String?> stun() async {
    try {
      final value = (await _native.stun().toDart).toDart.trim();
      return value.isEmpty ? null : value;
    } catch (error) {
      throw MoonlightException(
        'Unable to discover the external address.',
        cause: error,
      );
    }
  }

  @override
  Future<void> wakeOnLan(String macAddress) async {
    try {
      await _native.wakeOnLan(macAddress.toJS).toDart;
    } catch (error) {
      throw MoonlightException(
        'Unable to send the Wake-on-LAN packet.',
        cause: error,
      );
    }
  }

  @override
  bool unlockAudio() {
    try {
      return _native.unlockAudio().toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<StreamEvent> startStream(StreamRequest request) async {
    logDiagnostic('info', 'native.stream.start_requested', {
      'appId': request.appId,
      'width': request.width,
      'height': request.height,
      'frameRate': request.frameRate,
      'bitrateKbps': request.bitrateKbps,
      'videoCodec': request.videoCodec.wireName,
      'hdr': request.hdr,
      'gameMode': request.gameMode,
      'gamepadMask': connectedGamepadMask(),
    });
    try {
      final value = request.toJson().jsify();
      if (value == null) throw StateError('Unable to serialize StreamRequest.');
      final result = await _native.startStream(value).toDart;
      final event = _streamEvent(_stringKeyedMap(result?.dartify()));
      logDiagnostic('info', 'native.stream.start_completed', {
        'event': event.name,
        'attemptId': event.attemptId,
      });
      return event;
    } catch (error) {
      logDiagnostic('error', 'native.stream.start_failed', {
        'appId': request.appId,
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
      });
      throw MoonlightException('Unable to start the stream.', cause: error);
    }
  }

  @override
  Future<void> stopStream() async {
    logDiagnostic('info', 'native.stream.stop_requested');
    try {
      await _native.stopStream().toDart;
      logDiagnostic('info', 'native.stream.stop_accepted');
    } catch (error) {
      logDiagnostic('error', 'native.stream.stop_failed', {
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
      });
      throw MoonlightException('Unable to stop the stream.', cause: error);
    }
  }

  @override
  Future<void> startSyntheticAudioTest({required bool gameMode}) async {
    logDiagnostic('info', 'native.synthetic_audio.start_requested', {
      'requestedGameMode': gameMode,
      'audioPts': 0,
      'bypasses': const ['sunshine', 'network', 'opus', 'moonlight-queues'],
    });
    try {
      await _native.startSyntheticAudioTest(gameMode.toJS).toDart;
      logDiagnostic('info', 'native.synthetic_audio.start_accepted', {
        'requestedGameMode': gameMode,
      });
    } catch (error) {
      logDiagnostic('error', 'native.synthetic_audio.start_failed', {
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
      });
      throw MoonlightException(
        'Unable to initialize the synthetic PCM audio test.',
        cause: error,
      );
    }
  }

  @override
  Future<int> playSyntheticAudioClick(String inputLabel) async {
    try {
      final result = await _native
          .playSyntheticAudioClick(inputLabel.toJS)
          .toDart;
      final value = result?.dartify();
      final clickNumber = value is num ? value.toInt() : int.tryParse('$value');
      return clickNumber ?? 0;
    } catch (error) {
      throw MoonlightException(
        'Unable to play the synthetic PCM click.',
        cause: error,
      );
    }
  }

  @override
  Future<void> stopSyntheticAudioTest() async {
    try {
      await _native.stopSyntheticAudioTest().toDart;
      logDiagnostic('info', 'native.synthetic_audio.stopped');
    } catch (error) {
      logDiagnostic('warning', 'native.synthetic_audio.stop_failed', {
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
      });
    }
  }

  @override
  void recoverStreamSurface() => _facade?.recoverStreamSurface();

  @override
  Future<void> toggleStats() async {
    try {
      await _native.toggleStats().toDart;
    } catch (error) {
      throw MoonlightException(
        'Unable to toggle stream statistics.',
        cause: error,
      );
    }
  }

  @override
  Future<Map<String, Object?>> probeVideoCodecSupport(
    Map<String, Object?> request,
  ) async {
    logDiagnostic('info', 'native.codec_probe.started', {
      'width': request['width'],
      'height': request['height'],
      'frameRate': request['frameRate'] ?? request['fps'],
      'hdrMode': request['hdrMode'],
      'preferredCodec': request['preferredCodec'],
    });
    try {
      final value = request.jsify();
      if (value == null) throw StateError('Unable to serialize codec probe.');
      final result = await _native.probeVideoCodecSupport(value).toDart;
      final response = _stringKeyedMap(result?.dartify());
      logDiagnostic('info', 'native.codec_probe.completed', {
        'candidateCount': response['candidates'] is List
            ? (response['candidates']! as List).length
            : 0,
        'selectedMimeType': response['selectedMimeType'],
      });
      return response;
    } catch (error) {
      throw MoonlightException(
        'Unable to probe video codec support.',
        cause: error,
      );
    }
  }

  @override
  NativeInputMode setInputMode(NativeInputMode mode) {
    final result = _native.setInputMode(mode.name.toJS).toDart;
    return NativeInputMode.values.firstWhere(
      (value) => value.name == result,
      orElse: () => mode,
    );
  }

  @override
  int connectedGamepadMask() {
    try {
      return _native.connectedGamepadMask().toDartInt;
    } catch (_) {
      return 0;
    }
  }

  @override
  List<NativeInputDevice> inputDevices() {
    try {
      final values = _facade?.inputDevices().dartify();
      if (values is! List) return const <NativeInputDevice>[];
      return values
          .map(_stringKeyedMap)
          .where((value) => value.isNotEmpty)
          .map(NativeInputDevice.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <NativeInputDevice>[];
    }
  }

  @override
  bool testRumble(int browserIndex) {
    try {
      return _native.testRumble(browserIndex.toJS).toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  bool sendEscape() {
    try {
      return _native.sendEscape().toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  bool restartApp() {
    try {
      return _native.restartApp().toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  bool exitApp() {
    try {
      return _native.exitApp().toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  String setDiagnosticLogLevel(String level) =>
      _native.setDiagnosticLogLevel(level.toJS).toDart;

  @override
  void logDiagnostic(
    String level,
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {
    _native.logDiagnostic(level.toJS, event.toJS, details.jsify()!);
  }

  @override
  Map<String, Object?> diagnosticLogStatus() =>
      _stringKeyedMap(_native.getDiagnosticLogStatus()?.dartify());

  @override
  Future<String> diagnosticLogs() async =>
      (await _native.getDiagnosticLogs().toDart).toDart;

  @override
  Future<Map<String, Object?>> clearDiagnosticLogs() async =>
      _stringKeyedMap((await _native.clearDiagnosticLogs().toDart)?.dartify());

  @override
  String diagnosticQrSvg(String value) =>
      _native.getDiagnosticQrSvg(value.toJS).toDart;

  @override
  String getIpAddress() => _native.getIpAddress().toDart;

  @override
  Future<Map<String, Object?>> startLogExportServer({
    required String payload,
    required String filename,
    required String token,
    int requestedPort = 0,
  }) async => _stringKeyedMap(
    (await _native
            .startLogExportServer(
              payload.toJS,
              filename.toJS,
              token.toJS,
              requestedPort.toJS,
            )
            .toDart)
        ?.dartify(),
  );

  @override
  Future<void> stopLogExportServer() async {
    await _native.stopLogExportServer().toDart;
  }

  @override
  void dispose() {
    try {
      _facade?.setEventSink(null);
      _facade?.registerInputSink(null);
    } catch (_) {
      // The page may already be tearing down.
    }
    _eventCallback = null;
    _inputCallback = null;
    unawaited(_events.close());
    unawaited(_inputEvents.close());
  }
}

bool _isIpv4Address(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return false;
  return parts.every((part) {
    final octet = int.tryParse(part);
    return octet != null && octet >= 0 && octet <= 255;
  });
}

TransportException _transportException(Uri uri, Object error) {
  final message = error.toString();
  final numeric = RegExp(r'-?\d+').firstMatch(message);
  return TransportException(
    'Native request failed for ${uri.host}.',
    code: numeric == null ? null : int.tryParse(numeric.group(0)!),
    cause: error,
  );
}

Map<String, Object?> _stringKeyedMap(Object? value) {
  if (value is! Map) return const <String, Object?>{};
  return value.map(
    (key, item) => MapEntry(key.toString(), _normalizeDartified(item)),
  );
}

Object? _normalizeDartified(Object? value) {
  if (value is Map) return _stringKeyedMap(value);
  if (value is List) {
    return value.map(_normalizeDartified).toList(growable: false);
  }
  return value;
}

StreamEvent _streamEvent(Map<String, Object?> json) {
  final type = jsonString(json['type']);
  final nativeName = jsonString(json['name'] ?? json['state']);
  final kind = switch (type) {
    'runtime' => StreamEventKind.readiness,
    'progress' || 'transient' => StreamEventKind.progress,
    'warning' || 'dialog' => StreamEventKind.warning,
    'statistics' => StreamEventKind.statistics,
    'codec-profile' => StreamEventKind.codecProfile,
    'rumble' => StreamEventKind.rumble,
    'mouse-emulation' => StreamEventKind.mouseEmulation,
    _ => StreamEventKind.lifecycle,
  };
  final name = switch (nativeName) {
    'streamStarting' => 'connecting',
    'streamStarted' || 'connectionEstablished' || 'displayVideo' => 'streaming',
    'streamStartFailed' => 'failed',
    'streamStopping' => 'stopping',
    'streamTerminated' => 'terminated',
    _ => nativeName.isEmpty ? type : nativeName,
  };
  return StreamEvent(
    kind: kind,
    attemptId: json['attemptId']?.toString(),
    name: name,
    message: jsonString(json['message'] ?? json['reason']),
    data: Map.unmodifiable(json),
  );
}
