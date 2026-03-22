import 'package:lifestream_doctor/src/session.dart';
import 'package:test/test.dart';

void main() {
  group('Session', () {
    test('generates a valid UUID v4 id', () {
      final session = Session();
      final uuidV4Pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(session.id, matches(uuidV4Pattern));
    });

    test('duration starts at 0 when clock is constant', () {
      const fixedTime = 1000000;
      final session = Session(clock: () => fixedTime);
      expect(session.getDurationMs(), equals(0));
    });

    test('duration increases as clock advances', () {
      var now = 1000;
      final session = Session(clock: () => now);

      expect(session.getDurationMs(), equals(0));

      now = 1500;
      expect(session.getDurationMs(), equals(500));

      now = 3000;
      expect(session.getDurationMs(), equals(2000));
    });

    test('duration reflects exact clock difference', () {
      var now = 0;
      final session = Session(clock: () => now);

      now = 12345;
      expect(session.getDurationMs(), equals(12345));
    });

    test('each session has a unique id', () {
      final ids = <String>{};
      for (var i = 0; i < 20; i++) {
        ids.add(Session().id);
      }
      expect(ids.length, equals(20));
    });

    test('uses default clock when none provided', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final session = Session();
      final after = DateTime.now().millisecondsSinceEpoch;

      // Duration should be very small (non-negative).
      final duration = session.getDurationMs();
      expect(duration, greaterThanOrEqualTo(0));
      // Should be less than the time between before and after + some margin.
      expect(duration, lessThan(after - before + 100));
    });

    test('clock is called at construction time for start', () {
      var callCount = 0;
      var now = 5000;
      final session = Session(clock: () {
        callCount++;
        return now;
      });
      // Clock called once during construction (for _startTime).
      // The factory calls effectiveClock() once.
      final constructionCalls = callCount;
      expect(constructionCalls, equals(1));

      // getDurationMs calls clock again.
      now = 6000;
      session.getDurationMs();
      expect(callCount, equals(constructionCalls + 1));
    });
  });
}
