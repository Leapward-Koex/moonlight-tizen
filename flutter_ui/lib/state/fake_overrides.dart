import 'dart:convert';

import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:flutter_riverpod/misc.dart';

import '../data/fakes/fake_moonlight_repository.dart';
import '../data/persistence/persistent_state_store.dart';
import '../domain/domain.dart';
import 'app_state.dart';

final class FakeStateSeed {
  const FakeStateSeed({
    this.settings,
    this.hosts = const <SavedHost>[],
    this.appsByHost = const <String, List<MoonlightApp>>{},
    this.capabilities,
    this.offlineHostIds = const <String>{},
    this.pairingFails = false,
    this.launchFails = false,
  });

  final AppSettings? settings;
  final List<SavedHost> hosts;
  final Map<String, List<MoonlightApp>> appsByHost;
  final PlatformCapabilities? capabilities;
  final Set<String> offlineHostIds;
  final bool pairingFails;
  final bool launchFails;
}

final class FakeOverrideBundle {
  const FakeOverrideBundle({required this.overrides, required this.storage});
  final List<Override> overrides;
  final InMemoryPersistentStateStore storage;
}

Future<FakeOverrideBundle> createFakeOverrideBundle(FakeStateSeed seed) async {
  final storage = InMemoryPersistentStateStore();
  if (seed.settings != null) {
    await storage.write(
      'appSettings.v1',
      jsonEncode(seed.settings!.toJson()),
      _fakeStorageOptions('app-settings-v1'),
    );
  }
  await storage.write(
    'savedHosts.v1',
    jsonEncode(seed.hosts.map((host) => host.toJson()).toList()),
    _fakeStorageOptions('saved-hosts-v1'),
  );
  final repository = FakeMoonlightRepository(
    appsByHost: seed.appsByHost,
    offlineHostIds: seed.offlineHostIds,
    pairingFails: seed.pairingFails,
    launchFails: seed.launchFails,
  );
  return FakeOverrideBundle(
    storage: storage,
    overrides: [
      persistentStateStoreProvider.overrideWith((ref) async => storage),
      platformCapabilitiesProvider.overrideWithValue(
        seed.capabilities ?? const PlatformCapabilities(),
      ),
      moonlightRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

StorageOptions _fakeStorageOptions(String destroyKey) => StorageOptions(
  cacheTime: StorageCacheTime.unsafe_forever,
  destroyKey: destroyKey,
);
