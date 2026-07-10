import 'dart:convert';

import 'package:flutter_riverpod/experimental/persist.dart';

import 'persistent_backend.dart';
import 'persistent_backend_stub.dart' show MemoryBackend;

/// Riverpod offline-persistence adapter. Riverpod's experimental API is
/// intentionally isolated to this file so an upstream API change has one
/// migration point.
abstract base class PersistentStateStore extends Storage<String, String> {
  PersistentStateStore(this.backend);

  final PersistentBackend backend;

  @override
  Future<PersistedData<String>?> read(String key) async {
    final source = await backend.read(key);
    if (source == null) return null;
    try {
      final json = jsonDecode(source) as Map<String, Object?>;
      final expireAt = DateTime.tryParse(json['expireAt']?.toString() ?? '');
      if (expireAt != null && expireAt.isBefore(DateTime.now())) {
        await backend.delete(key);
        return null;
      }
      return PersistedData<String>(
        json['data']?.toString() ?? '',
        destroyKey: json['destroyKey']?.toString(),
        expireAt: expireAt,
      );
    } catch (_) {
      await backend.delete(key);
      return null;
    }
  }

  @override
  Future<void> write(String key, String value, StorageOptions options) async {
    final duration = options.cacheTime.duration;
    final expireAt = duration == null ? null : DateTime.now().add(duration);
    await backend.write(
      key,
      jsonEncode({
        'data': value,
        'destroyKey': options.destroyKey,
        'expireAt': expireAt?.toIso8601String(),
      }),
    );
  }

  @override
  Future<void> delete(String key) => backend.delete(key);

  @override
  void deleteOutOfDate() {
    // All Moonlight user data uses unsafe_forever and versioned keys. Stale
    // schemas are removed by destroyKey/key migration when a provider reads.
  }
}

final class IndexedDbPersistentStateStore extends PersistentStateStore {
  IndexedDbPersistentStateStore._(super.backend);

  static Future<IndexedDbPersistentStateStore> open() async =>
      IndexedDbPersistentStateStore._(await openPersistentBackend());
}

final class InMemoryPersistentStateStore extends PersistentStateStore {
  InMemoryPersistentStateStore([Map<String, String>? seed])
    : super(MemoryBackend(seed));
}
