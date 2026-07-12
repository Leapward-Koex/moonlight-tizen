import '../../domain/contracts.dart';
import 'persistent_box_art_cache_stub.dart'
    if (dart.library.js_interop) 'persistent_box_art_cache_web.dart'
    as implementation;

export 'in_memory_box_art_cache.dart';

Future<BoxArtCache> openPersistentBoxArtCache() =>
    implementation.openPersistentBoxArtCache();
