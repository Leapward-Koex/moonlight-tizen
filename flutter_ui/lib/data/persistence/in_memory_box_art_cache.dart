import 'dart:typed_data';

import '../../domain/contracts.dart';
import '../../domain/host_models.dart';

final class InMemoryBoxArtCache implements BoxArtCache {
  final Map<String, Uint8List> _entries = <String, Uint8List>{};

  String _key(SavedHost host, int appId) => '${host.id}:$appId';

  @override
  Future<Uint8List?> read(SavedHost host, int appId) async =>
      _entries[_key(host, appId)];

  @override
  Future<void> write(SavedHost host, int appId, Uint8List bytes) async {
    _entries[_key(host, appId)] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> clear(SavedHost host) async {
    _entries.removeWhere((key, _) => key.startsWith('${host.id}:'));
  }
}
