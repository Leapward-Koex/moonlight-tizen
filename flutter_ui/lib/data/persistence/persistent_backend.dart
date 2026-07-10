import 'persistent_backend_stub.dart'
    if (dart.library.js_interop) 'persistent_backend_web.dart'
    as implementation;

abstract interface class PersistentBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

Future<PersistentBackend> openPersistentBackend() =>
    implementation.openPersistentBackend();
