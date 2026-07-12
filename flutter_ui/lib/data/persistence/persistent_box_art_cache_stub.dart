import '../../domain/contracts.dart';
import 'in_memory_box_art_cache.dart';

Future<BoxArtCache> openPersistentBoxArtCache() async => InMemoryBoxArtCache();
