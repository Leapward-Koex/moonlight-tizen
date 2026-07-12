import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
