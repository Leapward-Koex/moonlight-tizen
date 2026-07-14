import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/moonlight_app.dart';
import 'domain/domain.dart';
import 'state/state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final fake = await createFakeOverrideBundle(
    const FakeStateSeed(
      hosts: [
        SavedHost(
          id: 'browser-demo-pc',
          serverUid: 'browser-demo-pc',
          hostname: 'Browser Demo PC',
          address: '192.0.2.42',
          pinnedCertificate: 'simulated-certificate',
        ),
      ],
      appsByHost: {
        'browser-demo-pc': [
          MoonlightApp(id: 1, title: 'Desktop'),
          MoonlightApp(id: 2, title: 'Steam Big Picture'),
          MoonlightApp(id: 3, title: 'Simulated Adventure'),
        ],
      },
    ),
  );
  runApp(
    ProviderScope(
      overrides: fake.overrides,
      child: const MoonlightFlutterApp(),
    ),
  );
}
