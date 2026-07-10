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
}
