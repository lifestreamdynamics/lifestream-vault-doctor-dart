import 'dart:math' as math;

/// Deduplicates errors by fingerprint within a sliding time window.
///
/// Each unique error fingerprint is tracked with its last-seen timestamp.
/// Repeated occurrences within [windowMs] are suppressed to avoid flooding
/// crash reports with duplicate entries.
class RateLimiter {
  /// Creates a rate limiter with the given [windowMs].
  ///
  /// The window is clamped to a minimum of 1000 ms. An optional [clock]
  /// function can be injected for deterministic testing — it must return
  /// milliseconds since epoch.
  RateLimiter({int windowMs = 60000, int Function()? clock})
      : windowMs = math.max(1000, windowMs),
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Time window in milliseconds for deduplication.
  final int windowMs;

  static const int _maxFingerprints = 10000;

  final Map<String, int> _seen = {};
  final int Function() _clock;

  /// Generates a fingerprint string from an error name and message.
  static String fingerprint(String errorName, String message) =>
      '$errorName::$message';

  /// Returns `true` if this fingerprint should be allowed (not rate-limited).
  ///
  /// A fingerprint is allowed if it has not been seen within the current
  /// window, or if the window has expired since the last occurrence.
  ///
  /// If the internal map has reached [_maxFingerprints] capacity and the
  /// fingerprint is unknown, it is allowed without being tracked to prevent
  /// unbounded memory growth.
  bool shouldAllow(String fingerprint) {
    final now = _clock();
    _prune(now);

    final lastSeen = _seen[fingerprint];
    if (lastSeen != null) {
      if (now - lastSeen < windowMs) {
        return false;
      }
      // Window expired — allow and update timestamp.
      _seen[fingerprint] = now;
      return true;
    }

    // Unknown fingerprint — check capacity.
    if (_seen.length >= _maxFingerprints) {
      // At capacity: allow without tracking.
      return true;
    }

    _seen[fingerprint] = now;
    return true;
  }

  /// Removes all expired entries from the seen map.
  void _prune(int now) {
    _seen.removeWhere((_, timestamp) => now - timestamp >= windowMs);
  }

  /// Clears all tracked fingerprints.
  void clear() {
    _seen.clear();
  }
}
