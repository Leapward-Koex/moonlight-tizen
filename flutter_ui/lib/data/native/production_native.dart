import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../domain/contracts.dart';
import '../../domain/diagnostics.dart';
import '../../domain/host_models.dart';
import '../../domain/platform_capabilities.dart';
import '../../state/app_state.dart';
import '../nvhttp_client.dart';
import '../nvhttp_request_builder.dart';
import 'moonlight_native.dart';

/// Production-only runtime provider. Application entrypoints override this
/// together with [moonlightRepositoryProvider] using [NativeProductionBundle].
final moonlightNativeRuntimeProvider = Provider<MoonlightNativeRuntime>(
  (ref) => throw UnsupportedError(
    'moonlightNativeRuntimeProvider must be overridden in the production app.',
  ),
  name: 'moonlightNativeRuntimeProvider',
);

final class NativeDiagnosticLogger implements DiagnosticLogger {
  const NativeDiagnosticLogger(this.runtime);

  final MoonlightNativeRuntime runtime;

  @override
  void log(
    String level,
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) => runtime.logDiagnostic(level, event, details);
}

final class NativeProductionBundle {
  const NativeProductionBundle({
    required this.runtime,
    required this.repository,
    required this.identity,
    required this.runtimeInfo,
    required this.overrides,
    required this.generatedIdentity,
  });

  final MoonlightNativeRuntime runtime;
  final MoonlightRepository repository;
  final ClientIdentity identity;
  final NativeRuntimeInfo runtimeInfo;
  final List<Override> overrides;

  /// True when the caller must persist [identity] through
  /// `clientIdentityStateProvider.notifier.setIdentity()` after mounting its
  /// ProviderScope.
  final bool generatedIdentity;

  PlatformCapabilities get capabilities => runtimeInfo.capabilities;

  void dispose() => runtime.dispose();
}

/// Initializes the native runtime and returns everything needed by the
/// production ProviderScope without coupling setup to `main.dart`.
Future<NativeProductionBundle> createNativeProductionBundle({
  ClientIdentity? identity,
  String? clientUid,
  MoonlightNativeRuntime? runtime,
  BoxArtCache? boxArtCache,
  Clock clock = const SystemClock(),
  UuidFactory? uuidFactory,
}) async {
  final native = runtime ?? createMoonlightNativeRuntime();
  try {
    final runtimeInfo = await native.initialize();
    final hasSavedIdentity = identity?.hasCertificate == true;
    var effectiveIdentity = identity;
    if (!hasSavedIdentity) {
      final effectiveUid = identity?.clientUid.isNotEmpty == true
          ? identity!.clientUid
          : (clientUid?.trim().isNotEmpty == true
                ? clientUid!.trim()
                : _randomHex(16));
      effectiveIdentity = await native.makeCertificate(clientUid: effectiveUid);
    } else if (effectiveIdentity!.clientUid.isEmpty) {
      effectiveIdentity = ClientIdentity(
        clientUid: clientUid?.trim().isNotEmpty == true
            ? clientUid!.trim()
            : _randomHex(16),
        certificatePem: effectiveIdentity.certificatePem,
        privateKeyPem: effectiveIdentity.privateKeyPem,
        createdAt: effectiveIdentity.createdAt,
      );
    }

    await native.httpInit(effectiveIdentity);
    final requests = NvHttpRequestBuilder(
      clientUid: effectiveIdentity.clientUid,
      uuidFactory: uuidFactory ?? _uuidV4,
    );
    final logger = NativeDiagnosticLogger(native);
    final repository = NvHttpClient(
      transport: native,
      pairingGateway: native,
      discoveryGateway: native,
      requests: requests,
      clock: clock,
      boxArtCache: boxArtCache,
      logger: logger,
    );
    return NativeProductionBundle(
      runtime: native,
      repository: repository,
      identity: effectiveIdentity,
      runtimeInfo: runtimeInfo,
      generatedIdentity: !hasSavedIdentity,
      overrides: [
        moonlightNativeRuntimeProvider.overrideWithValue(native),
        moonlightRepositoryProvider.overrideWithValue(repository),
        platformCapabilitiesProvider.overrideWithValue(
          runtimeInfo.capabilities,
        ),
        diagnosticLoggerProvider.overrideWithValue(logger),
      ],
    );
  } catch (_) {
    native.dispose();
    rethrow;
  }
}

final Random _secureRandom = Random.secure();

String _randomHex(int length) {
  const digits = '0123456789abcdef';
  return List<String>.generate(
    length,
    (_) => digits[_secureRandom.nextInt(digits.length)],
    growable: false,
  ).join();
}

String _uuidV4() {
  final bytes = List<int>.generate(
    16,
    (_) => _secureRandom.nextInt(256),
    growable: false,
  );
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int value) => value.toRadixString(16).padLeft(2, '0');
  final value = bytes.map(hex).join();
  return '${value.substring(0, 8)}-'
      '${value.substring(8, 12)}-'
      '${value.substring(12, 16)}-'
      '${value.substring(16, 20)}-'
      '${value.substring(20)}';
}
