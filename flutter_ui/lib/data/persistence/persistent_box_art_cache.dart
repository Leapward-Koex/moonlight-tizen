import 'dart:convert';
import 'dart:typed_data';

import '../../domain/contracts.dart';
import '../../domain/host_models.dart';
import 'persistent_backend.dart';

/// Small IndexedDB-backed box-art cache using the same isolated database as
/// Riverpod state. A per-host manifest makes host removal deterministic.
final class PersistentBoxArtCache implements BoxArtCache {
  const PersistentBoxArtCache(this.backend);

  final PersistentBackend backend;

  String _key(SavedHost host, int appId) => 'boxart.${host.id}.$appId';
  String _manifestKey(SavedHost host) => 'boxart.${host.id}.manifest';

  @override
  Future<Uint8List?> read(SavedHost host, int appId) async {
    final source = await backend.read(_key(host, appId));
    if (source == null || source.isEmpty) return null;
    try {
      return base64Decode(source);
    } catch (_) {
      await backend.delete(_key(host, appId));
      return null;
    }
  }

  @override
  Future<void> write(SavedHost host, int appId, Uint8List bytes) async {
    await backend.write(_key(host, appId), base64Encode(bytes));
    final manifest = (await _manifest(host))..add(appId);
    await backend.write(
      _manifestKey(host),
      jsonEncode(manifest.toList()..sort()),
    );
  }

  @override
  Future<void> clear(SavedHost host) async {
    final manifest = await _manifest(host);
    await Future.wait(
      manifest.map((appId) => backend.delete(_key(host, appId))),
    );
    await backend.delete(_manifestKey(host));
  }

  Future<Set<int>> _manifest(SavedHost host) async {
    final source = await backend.read(_manifestKey(host));
    if (source == null) return <int>{};
    try {
      return (jsonDecode(source) as List)
          .whereType<num>()
          .map((value) => value.toInt())
          .toSet();
    } catch (_) {
      return <int>{};
    }
  }
}
