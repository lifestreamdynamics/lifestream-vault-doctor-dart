import 'package:uuid/uuid.dart';

/// Tracks a unique session ID and elapsed duration.
///
/// Each session is assigned a UUID v4 at construction time. The injectable
/// [clock] parameter allows deterministic testing of duration calculations.
class Session {
  /// Creates a new session with a unique ID.
  ///
  /// [clock] is injectable for testing — it must return milliseconds since
  /// epoch. When omitted, defaults to [DateTime.now().millisecondsSinceEpoch].
  factory Session({int Function()? clock}) {
    final effectiveClock =
        clock ?? (() => DateTime.now().millisecondsSinceEpoch);
    return Session._(
      clock: effectiveClock,
      startTime: effectiveClock(),
      id: const Uuid().v4(),
    );
  }

  Session._({
    required int Function() clock,
    required int startTime,
    required this.id,
  })  : _clock = clock,
        _startTime = startTime;

  /// Unique session identifier (UUID v4).
  final String id;

  final int _startTime;
  final int Function() _clock;

  /// Returns the session duration in milliseconds.
  int getDurationMs() => _clock() - _startTime;
}
