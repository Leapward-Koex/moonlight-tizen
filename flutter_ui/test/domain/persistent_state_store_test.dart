import 'dart:typed_data';

import 'package:flutter_riverpod/experimental/persist.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonlight_tizen_flutter/data/data.dart';
import 'package:moonlight_tizen_flutter/domain/domain.dart';

void main() {
  test('in-memory store preserves Riverpod metadata and value', () async {
    final store = InMemoryPersistentStateStore();
    const options = StorageOptions(
      cacheTime: StorageCacheTime.unsafe_forever,
      destroyKey: 'schema-v1',
    );

    await store.write('settings.v1', '{"value":1}', options);
    final restored = await store.read('settings.v1');

    expect(restored?.data, '{"value":1}');
    expect(restored?.destroyKey, 'schema-v1');
    expect(restored?.expireAt, isNull);
  });

  test('delete removes persisted state', () async {
    final store = InMemoryPersistentStateStore();
    await store.write('hosts.v1', '[]', const StorageOptions());
    await store.delete('hosts.v1');
    expect(await store.read('hosts.v1'), isNull);
  });

  test('box art cache round-trips bytes and clears a host', () async {
    final cache = InMemoryBoxArtCache();
    const host = SavedHost(id: 'pc', hostname: 'PC', address: '10.0.0.2');
    final bytes = Uint8List.fromList([0, 1, 2, 254, 255]);

    await cache.write(host, 7, bytes);
    expect(await cache.read(host, 7), bytes);

    await cache.clear(host);
    expect(await cache.read(host, 7), isNull);
  });
}
