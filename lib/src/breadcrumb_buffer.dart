import 'dart:math' as math;

import 'types.dart';

/// A fixed-capacity circular buffer for [Breadcrumb] entries.
///
/// When the buffer is full, the oldest breadcrumb is overwritten. Breadcrumbs
/// are returned in oldest-first order via [getAll].
class BreadcrumbBuffer {
  /// Creates a breadcrumb buffer with the given [capacity].
  ///
  /// The capacity is clamped to a minimum of 1.
  BreadcrumbBuffer({int capacity = 50}) : capacity = math.max(1, capacity) {
    _buffer = List<Breadcrumb?>.filled(this.capacity, null);
  }

  /// The maximum number of breadcrumbs this buffer can hold.
  final int capacity;

  late List<Breadcrumb?> _buffer;
  int _head = 0;
  int _count = 0;

  /// Number of breadcrumbs currently in the buffer.
  int get size => _count;

  /// Adds a breadcrumb to the buffer.
  ///
  /// If [timestamp] is not set on the breadcrumb, it is auto-populated with
  /// the current UTC time in ISO-8601 format. The [type] field is truncated
  /// to 50 characters and [message] to 500 characters.
  void add(Breadcrumb breadcrumb) {
    final timestamp = breadcrumb.timestamp.isEmpty
        ? DateTime.now().toUtc().toIso8601String()
        : breadcrumb.timestamp;

    final truncatedType = breadcrumb.type.length > 50
        ? breadcrumb.type.substring(0, 50)
        : breadcrumb.type;

    final truncatedMessage = breadcrumb.message.length > 500
        ? breadcrumb.message.substring(0, 500)
        : breadcrumb.message;

    final entry = Breadcrumb(
      timestamp: timestamp,
      type: truncatedType,
      message: truncatedMessage,
      data: breadcrumb.data,
    );

    _buffer[_head] = entry;
    _head = (_head + 1) % capacity;
    if (_count < capacity) {
      _count++;
    }
  }

  /// Returns all breadcrumbs in oldest-first order.
  ///
  /// Returns an empty list if the buffer is empty.
  List<Breadcrumb> getAll() {
    if (_count == 0) return [];

    final result = <Breadcrumb>[];
    // If the buffer is not full, items are at indices 0.._count-1.
    // If full, the oldest item is at _head (since _head points to the next
    // write position, which is also the oldest entry in a full buffer).
    final start = _count < capacity ? 0 : _head;
    for (var i = 0; i < _count; i++) {
      final index = (start + i) % capacity;
      result.add(_buffer[index]!);
    }
    return result;
  }

  /// Clears all breadcrumbs from the buffer.
  void clear() {
    _buffer.fillRange(0, capacity, null);
    _head = 0;
    _count = 0;
  }
}
