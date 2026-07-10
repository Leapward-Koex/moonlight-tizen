// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(persistentStateStore)
final persistentStateStoreProvider = PersistentStateStoreProvider._();

final class PersistentStateStoreProvider
    extends
        $FunctionalProvider<
          AsyncValue<PersistentStateStore>,
          PersistentStateStore,
          FutureOr<PersistentStateStore>
        >
    with
        $FutureModifier<PersistentStateStore>,
        $FutureProvider<PersistentStateStore> {
  PersistentStateStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'persistentStateStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$persistentStateStoreHash();

  @$internal
  @override
  $FutureProviderElement<PersistentStateStore> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PersistentStateStore> create(Ref ref) {
    return persistentStateStore(ref);
  }
}

String _$persistentStateStoreHash() =>
    r'33218f7f1549d3ec2d5af29677a79ecfc205bf25';

@ProviderFor(platformCapabilities)
final platformCapabilitiesProvider = PlatformCapabilitiesProvider._();

final class PlatformCapabilitiesProvider
    extends
        $FunctionalProvider<
          PlatformCapabilities,
          PlatformCapabilities,
          PlatformCapabilities
        >
    with $Provider<PlatformCapabilities> {
  PlatformCapabilitiesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'platformCapabilitiesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$platformCapabilitiesHash();

  @$internal
  @override
  $ProviderElement<PlatformCapabilities> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PlatformCapabilities create(Ref ref) {
    return platformCapabilities(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlatformCapabilities value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlatformCapabilities>(value),
    );
  }
}

String _$platformCapabilitiesHash() =>
    r'b192b3d51e4631088b4c40d77e34ffeff62e9218';

@ProviderFor(moonlightRepository)
final moonlightRepositoryProvider = MoonlightRepositoryProvider._();

final class MoonlightRepositoryProvider
    extends
        $FunctionalProvider<
          MoonlightRepository,
          MoonlightRepository,
          MoonlightRepository
        >
    with $Provider<MoonlightRepository> {
  MoonlightRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'moonlightRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$moonlightRepositoryHash();

  @$internal
  @override
  $ProviderElement<MoonlightRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MoonlightRepository create(Ref ref) {
    return moonlightRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MoonlightRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MoonlightRepository>(value),
    );
  }
}

String _$moonlightRepositoryHash() =>
    r'0b31f95acfb1f67bfd7869c764a1cda02e985ce7';

@ProviderFor(diagnosticLogger)
final diagnosticLoggerProvider = DiagnosticLoggerProvider._();

final class DiagnosticLoggerProvider
    extends
        $FunctionalProvider<
          DiagnosticLogger,
          DiagnosticLogger,
          DiagnosticLogger
        >
    with $Provider<DiagnosticLogger> {
  DiagnosticLoggerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'diagnosticLoggerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$diagnosticLoggerHash();

  @$internal
  @override
  $ProviderElement<DiagnosticLogger> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DiagnosticLogger create(Ref ref) {
    return diagnosticLogger(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DiagnosticLogger value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DiagnosticLogger>(value),
    );
  }
}

String _$diagnosticLoggerHash() => r'8c75318af1a90703faeb915693184557e8a9b39c';

@ProviderFor(Settings)
final settingsProvider = SettingsProvider._();

final class SettingsProvider extends $NotifierProvider<Settings, AppSettings> {
  SettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsHash();

  @$internal
  @override
  Settings create() => Settings();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppSettings>(value),
    );
  }
}

String _$settingsHash() => r'e4da1bc077de98ec3e83f481df637ba86d9dd9ef';

abstract class _$Settings extends $Notifier<AppSettings> {
  AppSettings build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AppSettings, AppSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AppSettings, AppSettings>,
              AppSettings,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(ClientIdentityState)
final clientIdentityStateProvider = ClientIdentityStateProvider._();

final class ClientIdentityStateProvider
    extends $NotifierProvider<ClientIdentityState, ClientIdentity?> {
  ClientIdentityStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clientIdentityStateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clientIdentityStateHash();

  @$internal
  @override
  ClientIdentityState create() => ClientIdentityState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClientIdentity? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClientIdentity?>(value),
    );
  }
}

String _$clientIdentityStateHash() =>
    r'8dd5345e1e9c3b8b2104f6ae6b3f91ca31f962e9';

abstract class _$ClientIdentityState extends $Notifier<ClientIdentity?> {
  ClientIdentity? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ClientIdentity?, ClientIdentity?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ClientIdentity?, ClientIdentity?>,
              ClientIdentity?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(SavedHosts)
final savedHostsProvider = SavedHostsProvider._();

final class SavedHostsProvider
    extends $NotifierProvider<SavedHosts, List<SavedHost>> {
  SavedHostsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'savedHostsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$savedHostsHash();

  @$internal
  @override
  SavedHosts create() => SavedHosts();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<SavedHost> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<SavedHost>>(value),
    );
  }
}

String _$savedHostsHash() => r'c18f2ef3dab9e0a394ac8abe703302ba0151018a';

abstract class _$SavedHosts extends $Notifier<List<SavedHost>> {
  List<SavedHost> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<SavedHost>, List<SavedHost>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<SavedHost>, List<SavedHost>>,
              List<SavedHost>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(CodecCapabilities)
final codecCapabilitiesProvider = CodecCapabilitiesProvider._();

final class CodecCapabilitiesProvider
    extends $NotifierProvider<CodecCapabilities, CodecCapabilityCache> {
  CodecCapabilitiesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'codecCapabilitiesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$codecCapabilitiesHash();

  @$internal
  @override
  CodecCapabilities create() => CodecCapabilities();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CodecCapabilityCache value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CodecCapabilityCache>(value),
    );
  }
}

String _$codecCapabilitiesHash() => r'65a279544725b4d2e3323bb9877e02b07334b8e9';

abstract class _$CodecCapabilities extends $Notifier<CodecCapabilityCache> {
  CodecCapabilityCache build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<CodecCapabilityCache, CodecCapabilityCache>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CodecCapabilityCache, CodecCapabilityCache>,
              CodecCapabilityCache,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(UpdateCheckTimestamp)
final updateCheckTimestampProvider = UpdateCheckTimestampProvider._();

final class UpdateCheckTimestampProvider
    extends $NotifierProvider<UpdateCheckTimestamp, DateTime?> {
  UpdateCheckTimestampProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'updateCheckTimestampProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$updateCheckTimestampHash();

  @$internal
  @override
  UpdateCheckTimestamp create() => UpdateCheckTimestamp();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime?>(value),
    );
  }
}

String _$updateCheckTimestampHash() =>
    r'4a8a99caa8c2b651e492142cdad9e4f9843b22a7';

abstract class _$UpdateCheckTimestamp extends $Notifier<DateTime?> {
  DateTime? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DateTime?, DateTime?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DateTime?, DateTime?>,
              DateTime?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(HostStatuses)
final hostStatusesProvider = HostStatusesProvider._();

final class HostStatusesProvider
    extends $NotifierProvider<HostStatuses, Map<String, HostStatus>> {
  HostStatusesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hostStatusesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hostStatusesHash();

  @$internal
  @override
  HostStatuses create() => HostStatuses();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, HostStatus> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, HostStatus>>(value),
    );
  }
}

String _$hostStatusesHash() => r'cc0748b3b2ee85c5712754c330a2e79dd4676e94';

abstract class _$HostStatuses extends $Notifier<Map<String, HostStatus>> {
  Map<String, HostStatus> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<Map<String, HostStatus>, Map<String, HostStatus>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, HostStatus>, Map<String, HostStatus>>,
              Map<String, HostStatus>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(hosts)
final hostsProvider = HostsProvider._();

final class HostsProvider
    extends
        $FunctionalProvider<List<HostEntry>, List<HostEntry>, List<HostEntry>>
    with $Provider<List<HostEntry>> {
  HostsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hostsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hostsHash();

  @$internal
  @override
  $ProviderElement<List<HostEntry>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<HostEntry> create(Ref ref) {
    return hosts(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<HostEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<HostEntry>>(value),
    );
  }
}

String _$hostsHash() => r'8b136eb2c2fd564dfc84ba0039151fdf6d50ca84';

@ProviderFor(Apps)
final appsProvider = AppsFamily._();

final class AppsProvider
    extends $AsyncNotifierProvider<Apps, List<MoonlightApp>> {
  AppsProvider._({
    required AppsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'appsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$appsHash();

  @override
  String toString() {
    return r'appsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  Apps create() => Apps();

  @override
  bool operator ==(Object other) {
    return other is AppsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$appsHash() => r'53ac591e9b0b7ef9f814a15c5e5abc3070acdab7';

final class AppsFamily extends $Family
    with
        $ClassFamilyOverride<
          Apps,
          AsyncValue<List<MoonlightApp>>,
          List<MoonlightApp>,
          FutureOr<List<MoonlightApp>>,
          String
        > {
  AppsFamily._()
    : super(
        retry: null,
        name: r'appsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AppsProvider call(String hostId) =>
      AppsProvider._(argument: hostId, from: this);

  @override
  String toString() => r'appsProvider';
}

abstract class _$Apps extends $AsyncNotifier<List<MoonlightApp>> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<List<MoonlightApp>> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<MoonlightApp>>, List<MoonlightApp>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<MoonlightApp>>, List<MoonlightApp>>,
              AsyncValue<List<MoonlightApp>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(boxArt)
final boxArtProvider = BoxArtFamily._();

final class BoxArtProvider
    extends
        $FunctionalProvider<
          AsyncValue<Uint8List?>,
          Uint8List?,
          FutureOr<Uint8List?>
        >
    with $FutureModifier<Uint8List?>, $FutureProvider<Uint8List?> {
  BoxArtProvider._({
    required BoxArtFamily super.from,
    required (String, int) super.argument,
  }) : super(
         retry: null,
         name: r'boxArtProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$boxArtHash();

  @override
  String toString() {
    return r'boxArtProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<Uint8List?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Uint8List?> create(Ref ref) {
    final argument = this.argument as (String, int);
    return boxArt(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is BoxArtProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$boxArtHash() => r'd6b27c73d6bb03941c2380552c83f6f9ee47ed9f';

final class BoxArtFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Uint8List?>, (String, int)> {
  BoxArtFamily._()
    : super(
        retry: null,
        name: r'boxArtProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  BoxArtProvider call(String hostId, int appId) =>
      BoxArtProvider._(argument: (hostId, appId), from: this);

  @override
  String toString() => r'boxArtProvider';
}

@ProviderFor(Pairing)
final pairingProvider = PairingProvider._();

final class PairingProvider extends $NotifierProvider<Pairing, PairingState> {
  PairingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pairingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pairingHash();

  @$internal
  @override
  Pairing create() => Pairing();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PairingState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PairingState>(value),
    );
  }
}

String _$pairingHash() => r'73af1b5a80fbff7292c3dd4f04fbd60a4c9f0f65';

abstract class _$Pairing extends $Notifier<PairingState> {
  PairingState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PairingState, PairingState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PairingState, PairingState>,
              PairingState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(StreamSession)
final streamSessionProvider = StreamSessionProvider._();

final class StreamSessionProvider
    extends $NotifierProvider<StreamSession, StreamSessionState> {
  StreamSessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'streamSessionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$streamSessionHash();

  @$internal
  @override
  StreamSession create() => StreamSession();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StreamSessionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StreamSessionState>(value),
    );
  }
}

String _$streamSessionHash() => r'4e12df6077a63714de99bd688de51652136c4819';

abstract class _$StreamSession extends $Notifier<StreamSessionState> {
  StreamSessionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<StreamSessionState, StreamSessionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<StreamSessionState, StreamSessionState>,
              StreamSessionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(bootstrap)
final bootstrapProvider = BootstrapProvider._();

final class BootstrapProvider
    extends
        $FunctionalProvider<
          AsyncValue<BootstrapState>,
          BootstrapState,
          FutureOr<BootstrapState>
        >
    with $FutureModifier<BootstrapState>, $FutureProvider<BootstrapState> {
  BootstrapProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bootstrapProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bootstrapHash();

  @$internal
  @override
  $FutureProviderElement<BootstrapState> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<BootstrapState> create(Ref ref) {
    return bootstrap(ref);
  }
}

String _$bootstrapHash() => r'0b7900adbe38558d590ffbb1e0c5ed972afe7a06';

@ProviderFor(appCoordinator)
final appCoordinatorProvider = AppCoordinatorProvider._();

final class AppCoordinatorProvider
    extends $FunctionalProvider<AppCoordinator, AppCoordinator, AppCoordinator>
    with $Provider<AppCoordinator> {
  AppCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appCoordinatorHash();

  @$internal
  @override
  $ProviderElement<AppCoordinator> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppCoordinator create(Ref ref) {
    return appCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppCoordinator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppCoordinator>(value),
    );
  }
}

String _$appCoordinatorHash() => r'3126900e5401c91b7eb504086abbc0f00e8e81be';
