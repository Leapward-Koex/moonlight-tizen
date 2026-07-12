import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import '../../domain/contracts.dart';
import '../../domain/host_models.dart';

const _boxArtRoot = 'wgt-private/cache/boxart';

@JS('MoonlightTizenPlatform')
external JSObject? get _tizenPlatformObject;

extension type _TizenPlatformFacade(JSObject _) implements JSObject {
  external JSBoolean hasPrivateFileStorage();
  external JSPromise<JSUint8Array?> readPrivateFile(JSString path);
  external JSPromise<JSAny?> writePrivateFile(
    JSString path,
    JSUint8Array bytes,
  );
  external JSPromise<JSAny?> deletePrivateDirectory(JSString path);
}

Future<BoxArtCache> openPersistentBoxArtCache() async {
  final object = _tizenPlatformObject;
  if (object == null) {
    throw StateError('window.MoonlightTizenPlatform is unavailable.');
  }
  final platform = _TizenPlatformFacade(object);
  if (!platform.hasPrivateFileStorage().toDart) {
    throw StateError('Tizen private-file storage is unavailable.');
  }
  return _TizenPrivateBoxArtCache(platform);
}

final class _TizenPrivateBoxArtCache implements BoxArtCache {
  _TizenPrivateBoxArtCache(this._platform);

  final _TizenPlatformFacade _platform;

  String _hostDirectory(SavedHost host) {
    final encoded = base64Url.encode(utf8.encode(host.id)).replaceAll('=', '');
    return '$_boxArtRoot/$encoded';
  }

  String _path(SavedHost host, int appId) =>
      '${_hostDirectory(host)}/$appId.img';

  @override
  Future<Uint8List?> read(SavedHost host, int appId) async {
    final result = await _platform
        .readPrivateFile(_path(host, appId).toJS)
        .toDart;
    return result?.toDart;
  }

  @override
  Future<void> write(SavedHost host, int appId, Uint8List bytes) async {
    await _platform
        .writePrivateFile(_path(host, appId).toJS, bytes.toJS)
        .toDart;
  }

  @override
  Future<void> clear(SavedHost host) async {
    await _platform.deletePrivateDirectory(_hostDirectory(host).toJS).toDart;
  }
}
