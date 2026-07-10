import 'package:flutter_test/flutter_test.dart';
import 'package:moonlight_tizen_flutter/data/data.dart';
import 'package:moonlight_tizen_flutter/domain/domain.dart';

void main() {
  late NvHttpRequestBuilder builder;
  const host = SavedHost(
    id: 'host',
    hostname: 'PC',
    address: '192.168.1.5',
    httpPort: 47989,
    httpsPort: 47984,
  );

  setUp(() {
    builder = NvHttpRequestBuilder(
      clientUid: 'CLIENT-UID',
      uuidFactory: () => 'REQUEST-UUID',
    );
  });

  test('builds server info URL with stable identity fields', () {
    final uri = builder.serverInfo(
      host,
      host.address,
      secure: false,
      isNvidiaServerSoftware: false,
    );
    expect(uri.toString(), contains('http://192.168.1.5:47989/serverinfo?'));
    expect(uri.queryParameters['uniqueid'], 'CLIENT-UID');
    expect(uri.queryParameters['uuid'], 'REQUEST-UUID');
  });

  test('uses the compatibility UID for Nvidia servers', () {
    final uri = builder.appList(
      host,
      const HostStatus(isNvidiaServerSoftware: true),
    );
    expect(
      uri.queryParameters['uniqueid'],
      NvHttpRequestBuilder.nvidiaClientUid,
    );
  });

  test('builds all launch parameters without positional coupling', () {
    final uri = builder.launch(
      host,
      const HostStatus(),
      const HostLaunchRequest(
        appId: 42,
        mode: '1920x1080x60',
        optimizeGameSettings: true,
        remoteInput: RemoteInputCredentials(key: 'abcd', keyId: -12),
        hdr: true,
        playAudioOnHost: false,
        gamepadMask: 3,
      ),
    );
    expect(uri.path, '/launch');
    expect(uri.queryParameters['appid'], '42');
    expect(uri.queryParameters['mode'], '1920x1080x60');
    expect(uri.queryParameters['sops'], '1');
    expect(uri.queryParameters['rikeyid'], '-12');
    expect(uri.queryParameters['hdrMode'], '1');
    expect(uri.queryParameters['remoteControllersBitmap'], '3');
    expect(uri.queryParameters['gcmap'], '3');
  });
}
