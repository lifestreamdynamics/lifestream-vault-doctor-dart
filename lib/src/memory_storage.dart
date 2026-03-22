import 'storage_backend.dart';

/// In-memory [StorageBackend] implementation.
///
/// Data is lost when the process exits. Use this as a default when no
/// persistent storage is available, or for testing.
class MemoryStorage implements StorageBackend {
  final Map<String, String> _store = {};

  @override
  Future<String?> getItem(String key) async => _store[key];

  @override
  Future<void> setItem(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> removeItem(String key) async {
    _store.remove(key);
  }
}
