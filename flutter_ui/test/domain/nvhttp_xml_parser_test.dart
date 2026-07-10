import 'package:flutter_test/flutter_test.dart';
import 'package:moonlight_tizen_flutter/data/data.dart';
import 'package:moonlight_tizen_flutter/domain/domain.dart';

const _serverInfo = '''
<root status_code="200" status_message="OK">
  <hostname>Gaming-PC</hostname>
  <uniqueid>SERVER-123</uniqueid>
  <LocalIP>192.168.1.20</LocalIP>
  <ExternalIP>203.0.113.4</ExternalIP>
  <mac>AA:BB:CC:DD:EE:FF</mac>
  <HttpsPort>47984</HttpsPort>
  <ExternalPort>47989</ExternalPort>
  <PairStatus>1</PairStatus>
  <appversion>7.1.431.0</appversion>
  <GfeVersion>3.27.0</GfeVersion>
  <ServerCodecModeSupport>513</ServerCodecModeSupport>
  <gputype>RTX 4080</gputype>
  <numofapps>2</numofapps>
  <state>SUNSHINE_SERVER_BUSY</state>
  <currentgame>42</currentgame>
  <DisplayMode><Width>1920</Width><Height>1080</Height><RefreshRate>60</RefreshRate></DisplayMode>
  <DisplayMode><Width>1920</Width><Height>1080</Height><RefreshRate>120</RefreshRate></DisplayMode>
</root>
''';

void main() {
  const parser = NvHttpXmlParser();

  test('parses server info and display modes', () {
    final result = parser.parseServerInfo(
      _serverInfo,
      expectedServerUid: 'SERVER-123',
    );

    expect(result.hostname, 'Gaming-PC');
    expect(result.paired, isTrue);
    expect(result.serverMajorVersion, 7);
    expect(result.currentGameId, 42);
    expect(result.serverCodecModeSupport, 513);
    expect(result.displayModes, hasLength(2));
  });

  test('rejects a changed server identity', () {
    expect(
      () => parser.parseServerInfo(
        _serverInfo,
        expectedServerUid: 'DIFFERENT-SERVER',
      ),
      throwsA(isA<UnexpectedHostException>()),
    );
  });

  test('forces current game to zero when the host is not busy', () {
    final result = parser.parseServerInfo(
      _serverInfo.replaceFirst('SUNSHINE_SERVER_BUSY', 'SUNSHINE_SERVER_FREE'),
    );
    expect(result.currentGameId, 0);
  });

  test('parses app list and skips incomplete entries', () {
    final apps = parser.parseAppList('''
      <root status_code="200">
        <App><ID>1</ID><AppTitle>Desktop</AppTitle></App>
        <App><ID>2</ID><AppTitle>Steam</AppTitle></App>
        <App><ID>bad</ID><AppTitle>Broken</AppTitle></App>
      </root>
    ''');
    expect(apps.map((app) => app.title), ['Desktop', 'Steam']);
  });

  test('normalizes the legacy audio capture launch error', () {
    final result = parser.parseLaunchResult(
      '<root status_code="4294967295" status_message="Invalid"/>',
    );
    expect(result.statusCode, 418);
    expect(result.statusMessage, contains('Audio capture device'));
  });

  test('rejects malformed XML and non-200 responses', () {
    expect(
      () => parser.parseAppList('<root>'),
      throwsA(isA<ProtocolException>()),
    );
    expect(
      () => parser.parseAppList('<root status_code="503"/>'),
      throwsA(
        isA<ProtocolException>().having(
          (error) => error.statusCode,
          'statusCode',
          503,
        ),
      ),
    );
  });
}
