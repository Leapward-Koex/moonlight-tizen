import 'package:xml/xml.dart';

import '../domain/errors.dart';
import '../domain/host_models.dart';
import '../domain/stream_models.dart';

final class NvHttpXmlParser {
  const NvHttpXmlParser();

  ServerInfo parseServerInfo(
    String source, {
    String expectedServerUid = '',
    int fallbackHttpsPort = SavedHost.defaultHttpsPort,
    int fallbackExternalPort = SavedHost.defaultHttpPort,
  }) {
    final root = _parseRoot(source);
    _requireSuccess(root, 'server info');

    final serverUid = _text(root, 'uniqueid');
    if (serverUid.isEmpty) {
      throw const ProtocolException('Server info is missing uniqueid.');
    }
    if (expectedServerUid.isNotEmpty && serverUid != expectedServerUid) {
      throw UnexpectedHostException(
        expected: expectedServerUid,
        actual: serverUid,
      );
    }

    final appVersion = _text(root, 'appversion');
    final state = _text(root, 'state');
    final currentGame = state.endsWith('_SERVER_BUSY')
        ? _integer(root, 'currentgame')
        : 0;
    final modes = <DisplayMode>{};
    for (final element in _elements(root, 'DisplayMode')) {
      final mode = DisplayMode(
        width: _integer(element, 'Width'),
        height: _integer(element, 'Height'),
        refreshRate: _integer(element, 'RefreshRate'),
      );
      if (mode.width > 0 && mode.height > 0 && mode.refreshRate > 0) {
        modes.add(mode);
      }
    }

    return ServerInfo(
      serverUid: serverUid,
      hostname: _text(root, 'hostname').isEmpty
          ? 'UNKNOWN'
          : _text(root, 'hostname'),
      localAddress: _text(root, 'LocalIP'),
      externalAddress: _text(root, 'ExternalIP'),
      macAddress: _text(root, 'mac'),
      httpsPort: _integer(root, 'HttpsPort', fallbackHttpsPort),
      externalPort: _integer(root, 'ExternalPort', fallbackExternalPort),
      paired: _text(root, 'PairStatus') == '1',
      appVersion: appVersion,
      gfeVersion: _text(root, 'GfeVersion'),
      serverMajorVersion: int.tryParse(appVersion.split('.').first) ?? 0,
      serverCodecModeSupport: _integer(root, 'ServerCodecModeSupport'),
      serverState: state,
      isNvidiaServerSoftware: state.contains('MJOLNIR'),
      gpuType: _text(root, 'gputype'),
      numberOfApps: _integer(root, 'numofapps'),
      currentGameId: currentGame,
      displayModes: List.unmodifiable(modes),
    );
  }

  List<MoonlightApp> parseAppList(String source) {
    final root = _parseRoot(source);
    _requireSuccess(root, 'app list');
    final apps = <MoonlightApp>[];
    for (final element in _elements(root, 'App')) {
      final id = _integer(element, 'ID', -1);
      final title = _text(element, 'AppTitle');
      if (id >= 0 && title.isNotEmpty) {
        apps.add(MoonlightApp(id: id, title: title));
      }
    }
    return List.unmodifiable(apps);
  }

  LaunchResult parseLaunchResult(String source) {
    final root = _parseRoot(source);
    final code = int.tryParse(root.getAttribute('status_code') ?? '') ?? -1;
    var message = root.getAttribute('status_message') ?? '';
    var normalizedCode = code;
    if (code == 4294967295 && message == 'Invalid') {
      normalizedCode = 418;
      message =
          'Audio capture device is missing. Please reinstall the audio drivers.';
    }
    return LaunchResult(
      statusCode: normalizedCode,
      statusMessage: message,
      sessionUrl: _text(root, 'sessionUrl0'),
    );
  }

  bool parsePairResult(String source) {
    final root = _parseRoot(source);
    _requireSuccess(root, 'pair challenge');
    return _text(root, 'paired') == '1';
  }

  void requireSuccess(String source, String operation) {
    _requireSuccess(_parseRoot(source), operation);
  }

  XmlElement _parseRoot(String source) {
    try {
      final document = XmlDocument.parse(source);
      final root = document.rootElement;
      if (root.name.local != 'root') {
        final nested = _elements(root, 'root');
        if (nested.isNotEmpty) return nested.first;
      }
      return root;
    } catch (error) {
      throw ProtocolException('Malformed XML response.', cause: error);
    }
  }

  void _requireSuccess(XmlElement root, String operation) {
    final code = int.tryParse(root.getAttribute('status_code') ?? '') ?? -1;
    if (code != 200) {
      final message = root.getAttribute('status_message') ?? '';
      throw ProtocolException(
        'Host rejected $operation with status $code${message.isEmpty ? '' : ': $message'}.',
        statusCode: code,
        statusMessage: message,
      );
    }
  }

  String _text(XmlElement parent, String localName) {
    final elements = _elements(parent, localName);
    return elements.isEmpty ? '' : elements.first.innerText.trim();
  }

  int _integer(XmlElement parent, String localName, [int fallback = 0]) =>
      int.tryParse(_text(parent, localName)) ?? fallback;

  List<XmlElement> _elements(XmlElement parent, String localName) => parent
      .descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == localName)
      .toList(growable: false);
}
