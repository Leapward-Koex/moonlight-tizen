import 'persistent_backend.dart';

Future<PersistentBackend> openPersistentBackend() async => MemoryBackend();

final class MemoryBackend implements PersistentBackend {
  MemoryBackend([Map<String, String>? seed])
    : _values = seed ?? <String, String>{};

  final Map<String, String> _values;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
