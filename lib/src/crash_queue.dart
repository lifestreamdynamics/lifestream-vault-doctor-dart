import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'storage_backend.dart';
import 'types.dart';

/// Persistent offline queue for crash reports.
///
/// Reports are serialized to JSON and stored via a [StorageBackend].
/// When the device comes back online, call [flush] to upload queued reports.
class CrashQueue {
  CrashQueue(this._storage, {String storageKey = 'doctor:queue'})
      : _storageKey = storageKey;

  /// Maximum number of reports held in the queue. When exceeded, the oldest
  /// entry is dropped.
  static const int maxQueueSize = 50;

  /// Maximum number of upload attempts before a report is dead-lettered.
  static const int maxAttempts = 5;

  static const _uuid = Uuid();

  final StorageBackend _storage;
  final String _storageKey;

  /// Adds a new report to the queue. If the queue is at capacity, the oldest
  /// entry is dropped first.
  Future<void> enqueue(String content, String path) async {
    final queue = await _load();
    final entry = QueuedReport(
      id: _uuid.v4(),
      content: content,
      path: path,
      attempts: 0,
      queuedAt: DateTime.now().toUtc().toIso8601String(),
    );
    if (queue.length >= maxQueueSize) {
      queue.removeAt(0); // drop oldest
    }
    queue.add(entry);
    await _save(queue);
  }

  /// Returns the oldest queued report without removing it, or `null` if the
  /// queue is empty.
  Future<QueuedReport?> dequeue() async {
    final queue = await _load();
    return queue.isEmpty ? null : queue[0];
  }

  /// Removes the report with the given [id] from the queue.
  Future<void> remove(String id) async {
    final queue = await _load();
    final updated = queue.where((entry) => entry.id != id).toList();
    await _save(updated);
  }

  /// Increments the attempt count and sets [lastAttemptAt] for the report
  /// with the given [id].
  Future<void> markAttempted(String id) async {
    final queue = await _load();
    final updated = queue.map((entry) {
      if (entry.id == id) {
        return entry.markAttempted(DateTime.now().toUtc().toIso8601String());
      }
      return entry;
    }).toList();
    await _save(updated);
  }

  /// Returns the number of reports currently in the queue.
  Future<int> size() async {
    final queue = await _load();
    return queue.length;
  }

  /// Attempts to upload every queued report via [handler].
  ///
  /// - On success the report is removed from the queue.
  /// - On failure the attempt count is incremented. If the report has
  ///   reached [maxAttempts], it is dead-lettered (removed permanently).
  Future<FlushResult> flush(Future<void> Function(QueuedReport) handler) async {
    final queue = await _load();
    var sent = 0;
    var failed = 0;
    var deadLettered = 0;

    for (final entry in queue) {
      try {
        await handler(entry);
        await remove(entry.id);
        sent++;
      } catch (_) {
        await markAttempted(entry.id);
        final updated = await _load();
        final current = updated.cast<QueuedReport?>().firstWhere(
              (e) => e!.id == entry.id,
              orElse: () => null,
            );
        if (current != null && current.attempts >= maxAttempts) {
          await remove(entry.id);
          deadLettered++;
        } else {
          failed++;
        }
      }
    }

    return FlushResult(sent: sent, failed: failed, deadLettered: deadLettered);
  }

  /// Removes all reports from the queue.
  Future<void> clear() async {
    await _save([]);
  }

  /// Loads the queue from storage. Returns an empty list if the storage key
  /// is missing, the JSON is invalid, or the parsed value is not a list.
  Future<List<QueuedReport>> _load() async {
    final raw = await _storage.getItem(_storageKey);
    if (raw == null) return [];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is List) {
        return parsed
            .cast<Map<String, Object?>>()
            .map(QueuedReport.fromJson)
            .toList();
      }
      return [];
    } on FormatException {
      return [];
    } on TypeError {
      // Malformed entry — treat as empty queue rather than crashing.
      return [];
    }
  }

  /// Persists the queue to storage as JSON.
  Future<void> _save(List<QueuedReport> queue) async {
    await _storage.setItem(
      _storageKey,
      jsonEncode(queue.map((e) => e.toJson()).toList()),
    );
  }
}
