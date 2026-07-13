import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonlight_tizen_flutter/data/fakes/fake_moonlight_repository.dart';
import 'package:moonlight_tizen_flutter/domain/domain.dart';
import 'package:moonlight_tizen_flutter/state/state.dart';

void main() {
  test('fake override bundle hydrates persistent settings and hosts', () async {
    final bundle = await createFakeOverrideBundle(
      const FakeStateSeed(
        settings: AppSettings(
          resolution: StreamResolution.hd1080,
          bitrateMbps: 20,
        ),
        hosts: [
          SavedHost(id: 'host-1', hostname: 'Fake PC', address: '192.0.2.1'),
        ],
      ),
    );
    final container = ProviderContainer(overrides: bundle.overrides);
    addTearDown(container.dispose);

    await container.read(bootstrapProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(settingsProvider).resolution,
      StreamResolution.hd1080,
    );
    expect(container.read(savedHostsProvider).single.hostname, 'Fake PC');
  });

  test('apps family uses the injectable repository', () async {
    final bundle = await createFakeOverrideBundle(
      const FakeStateSeed(
        hosts: [
          SavedHost(id: 'host-1', hostname: 'Fake PC', address: '192.0.2.1'),
        ],
        appsByHost: {
          'host-1': [MoonlightApp(id: 1, title: 'Desktop')],
        },
      ),
    );
    final container = ProviderContainer(overrides: bundle.overrides);
    addTearDown(container.dispose);
    await container.read(bootstrapProvider.future);
    await Future<void>.delayed(Duration.zero);
    container
        .read(hostStatusesProvider.notifier)
        .set('host-1', const HostStatus(online: true, paired: true));

    final apps = await container.read(appsProvider('host-1').future);
    expect(apps.single.title, 'Desktop');
  });

  test('background host polling does not reload the games list', () async {
    const host = SavedHost(
      id: 'host-1',
      hostname: 'Fake PC',
      address: '192.0.2.1',
    );
    final repository = FakeMoonlightRepository(
      appsByHost: const {
        'host-1': [MoonlightApp(id: 1, title: 'Desktop')],
      },
    );
    final bundle = await createFakeOverrideBundle(
      const FakeStateSeed(
        hosts: [host],
        appsByHost: {
          'host-1': [MoonlightApp(id: 1, title: 'Desktop')],
        },
      ),
      repository: repository,
    );
    final container = ProviderContainer(overrides: bundle.overrides);
    addTearDown(container.dispose);
    await container.read(bootstrapProvider.future);
    await Future<void>.delayed(Duration.zero);
    final subscription = container.listen(
      appsProvider(host.id),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    expect(await container.read(appsProvider(host.id).future), isEmpty);
    expect(repository.getAppListCallCount, 0);

    container
        .read(hostStatusesProvider.notifier)
        .set(host.id, const HostStatus(online: true, paired: true));
    await Future<void>.delayed(Duration.zero);
    expect(
      (await container.read(appsProvider(host.id).future)).single.title,
      'Desktop',
    );
    expect(repository.getAppListCallCount, 1);

    for (var poll = 0; poll < 12; poll += 1) {
      await container.read(appCoordinatorProvider).pollHost(host.id);
      await Future<void>.delayed(Duration.zero);
    }

    expect(repository.getAppListCallCount, 1);
  });

  test(
    'saved hosts keep pairing status unknown until first observation',
    () async {
      final bundle = await createFakeOverrideBundle(
        const FakeStateSeed(
          hosts: [
            SavedHost(id: 'host-1', hostname: 'Fake PC', address: '192.0.2.1'),
          ],
        ),
      );
      final container = ProviderContainer(overrides: bundle.overrides);
      addTearDown(container.dispose);
      await container.read(bootstrapProvider.future);
      await Future<void>.delayed(Duration.zero);

      var entry = container.read(hostsProvider).single;
      expect(entry.statusKnown, isFalse);
      expect(entry.status.paired, isFalse);

      container
          .read(hostStatusesProvider.notifier)
          .set('host-1', const HostStatus(online: true, paired: false));

      entry = container.read(hostsProvider).single;
      expect(entry.statusKnown, isTrue);
      expect(entry.status.online, isTrue);
      expect(entry.status.paired, isFalse);
    },
  );

  test('a rejected pairing attempt can be retried', () async {
    final bundle = await createFakeOverrideBundle(
      const FakeStateSeed(
        hosts: [
          SavedHost(id: 'host-1', hostname: 'Fake PC', address: '192.0.2.1'),
        ],
        pairingFails: true,
      ),
    );
    final container = ProviderContainer(overrides: bundle.overrides);
    addTearDown(container.dispose);
    await container.read(bootstrapProvider.future);
    await Future<void>.delayed(Duration.zero);

    final pairing = container.read(pairingProvider.notifier);
    expect((await pairing.pair('host-1', '1234')).paired, isFalse);
    expect(container.read(pairingProvider).phase, PairingPhase.failed);

    expect((await pairing.pair('host-1', '5678')).paired, isFalse);
    expect(container.read(pairingProvider).phase, PairingPhase.failed);
  });

  test(
    'subnet discovery adds responders using their stable server UID',
    () async {
      final bundle = await createFakeOverrideBundle(const FakeStateSeed());
      final container = ProviderContainer(overrides: bundle.overrides);
      addTearDown(container.dispose);
      await container.read(bootstrapProvider.future);
      await Future<void>.delayed(Duration.zero);

      final summary = await container
          .read(appCoordinatorProvider)
          .discoverHosts(const ['192.168.1.42', 'not-an-ip']);

      expect(summary.responderCount, 1);
      expect(summary.addedHostCount, 1);
      final host = container.read(savedHostsProvider).single;
      expect(host.id, 'fake-discovered:192.168.1.42');
      expect(host.serverUid, host.id);
      expect(host.address, '192.168.1.42');
      expect(container.read(hostStatusesProvider)[host.id]?.online, isTrue);
    },
  );

  test(
    'subnet discovery preserves an online hostname but repairs it when offline',
    () async {
      const address = '192.168.1.42';
      const host = SavedHost(
        id: 'known-host',
        serverUid: 'fake-discovered:$address',
        hostname: 'Gaming PC',
        address: 'gaming-pc.local',
        pinnedCertificate: 'certificate',
      );
      final bundle = await createFakeOverrideBundle(
        const FakeStateSeed(hosts: [host]),
      );
      final container = ProviderContainer(overrides: bundle.overrides);
      addTearDown(container.dispose);
      await container.read(bootstrapProvider.future);
      await Future<void>.delayed(Duration.zero);
      container
          .read(hostStatusesProvider.notifier)
          .set(host.id, const HostStatus(online: true, paired: true));

      final preserved = await container
          .read(appCoordinatorProvider)
          .discoverHosts(const [address]);
      expect(preserved.updatedHostCount, 0);
      expect(container.read(savedHostsProvider).single.address, host.address);

      container
          .read(hostStatusesProvider.notifier)
          .set(host.id, const HostStatus());
      final repaired = await container
          .read(appCoordinatorProvider)
          .discoverHosts(const [address]);
      expect(repaired.updatedHostCount, 1);
      final updated = container.read(savedHostsProvider).single;
      expect(updated.id, host.id);
      expect(updated.address, address);
      expect(updated.pinnedCertificate, host.pinnedCertificate);
    },
  );
}
