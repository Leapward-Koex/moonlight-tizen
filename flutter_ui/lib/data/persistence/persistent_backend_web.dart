import 'dart:convert';
import 'dart:js_interop';

import 'persistent_backend.dart';

const _stateRoot = 'wgt-private/state';

@JS('MoonlightTizenPlatform')
external JSObject? get _tizenPlatformObject;

extension type _TizenPlatformFacade(JSObject _) implements JSObject {
  external JSBoolean hasPrivateStateStorage();
  external JSPromise<JSString?> readPrivateTextFile(JSString path);
  external JSPromise<JSAny?> writePrivateTextFile(
    JSString path,
    JSString value,
  );
  external JSPromise<JSAny?> deletePrivateFile(JSString path);
}

Future<PersistentBackend> openPersistentBackend() async {
  final object = _tizenPlatformObject;
  if (object == null) {
    throw StateError('window.MoonlightTizenPlatform is unavailable.');
  }
  final platform = _TizenPlatformFacade(object);
  if (!platform.hasPrivateStateStorage().toDart) {
    throw StateError('Tizen private state storage is unavailable.');
  }
  return _TizenPrivateFileBackend(platform);
}

final class _TizenPrivateFileBackend implements PersistentBackend {
  _TizenPrivateFileBackend(this._platform);

  final _TizenPlatformFacade _platform;

  JSString _path(String key) {
    final encoded = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    return '$_stateRoot/$encoded.json'.toJS;
  }

  @override
  Future<String?> read(String key) async {
    final result = await _platform.readPrivateTextFile(_path(key)).toDart;
    return result?.toDart;
  }

  @override
  Future<void> write(String key, String value) async {
    await _platform.writePrivateTextFile(_path(key), value.toJS).toDart;
  }

  @override
  Future<void> delete(String key) async {
    await _platform.deletePrivateFile(_path(key)).toDart;
  }
}
