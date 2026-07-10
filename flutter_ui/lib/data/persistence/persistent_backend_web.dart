import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

import 'persistent_backend.dart';

const _databaseName = 'MoonlightFlutterState';
const _objectStoreName = 'riverpod';

Future<PersistentBackend> openPersistentBackend() async {
  final completer = Completer<IDBDatabase>();
  final request = window.indexedDB.open(_databaseName, 1);
  request.onupgradeneeded = ((Event _) {
    final database = request.result as IDBDatabase;
    if (!database.objectStoreNames.contains(_objectStoreName)) {
      database.createObjectStore(_objectStoreName);
    }
  }).toJS;
  request.onsuccess = ((Event _) {
    completer.complete(request.result as IDBDatabase);
  }).toJS;
  request.onerror = ((Event _) {
    completer.completeError(
      StateError('Unable to open $_databaseName: ${request.error?.message}'),
    );
  }).toJS;
  return IndexedDbBackend(await completer.future);
}

final class IndexedDbBackend implements PersistentBackend {
  IndexedDbBackend(this._database);

  final IDBDatabase _database;

  @override
  Future<String?> read(String key) {
    final transaction = _database.transaction(
      _objectStoreName.toJS,
      'readonly',
    );
    final request = transaction.objectStore(_objectStoreName).get(key.toJS);
    return _completeRequest(request, (result) => result?.dartify()?.toString());
  }

  @override
  Future<void> write(String key, String value) {
    final transaction = _database.transaction(
      _objectStoreName.toJS,
      'readwrite',
    );
    final request = transaction
        .objectStore(_objectStoreName)
        .put(value.toJS, key.toJS);
    return _completeRequest<void>(request, (_) {});
  }

  @override
  Future<void> delete(String key) {
    final transaction = _database.transaction(
      _objectStoreName.toJS,
      'readwrite',
    );
    final request = transaction.objectStore(_objectStoreName).delete(key.toJS);
    return _completeRequest<void>(request, (_) {});
  }

  Future<T> _completeRequest<T>(
    IDBRequest request,
    T Function(JSAny? value) convert,
  ) {
    final completer = Completer<T>();
    request.onsuccess = ((Event _) {
      completer.complete(convert(request.result));
    }).toJS;
    request.onerror = ((Event _) {
      completer.completeError(
        StateError('IndexedDB request failed: ${request.error?.message}'),
      );
    }).toJS;
    return completer.future;
  }
}
