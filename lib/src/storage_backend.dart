/// Storage backend interface for platform-agnostic persistence.
///
/// Implement this interface to provide custom storage (e.g., Hive,
/// SharedPreferences, file-based) for the offline queue and consent state.
abstract class StorageBackend {
  /// Retrieves the value for [key], or `null` if not found.
  Future<String?> getItem(String key);

  /// Stores [value] under [key].
  Future<void> setItem(String key, String value);

  /// Removes the entry for [key].
  Future<void> removeItem(String key);
}
