import 'package:lifestream_doctor/src/rate_limiter.dart';
import 'package:test/test.dart';

void main() {
  group('RateLimiter', () {
    test('allows first occurrence of a fingerprint', () {
      final now = 10000;
      final limiter = RateLimiter(clock: () => now);

      expect(limiter.shouldAllow('TypeError::oops'), isTrue);
    });

    test('blocks same fingerprint within window', () {
      var now = 10000;
      final limiter = RateLimiter(windowMs: 5000, clock: () => now);

      expect(limiter.shouldAllow('TypeError::oops'), isTrue);

      now = 12000; // 2s later — within 5s window.
      expect(limiter.shouldAllow('TypeError::oops'), isFalse);
    });

    test('allows same fingerprint after window expires', () {
      var now = 10000;
      final limiter = RateLimiter(windowMs: 5000, clock: () => now);

      expect(limiter.shouldAllow('TypeError::oops'), isTrue);

      now = 15000; // Exactly at window boundary — expired.
      expect(limiter.shouldAllow('TypeError::oops'), isTrue);
    });

    test('allows same fingerprint well after window expires', () {
      var now = 10000;
      final limiter = RateLimiter(windowMs: 5000, clock: () => now);

      expect(limiter.shouldAllow('TypeError::oops'), isTrue);

      now = 20000; // 10s later — well past 5s window.
      expect(limiter.shouldAllow('TypeError::oops'), isTrue);
    });

    test('allows different fingerprints independently', () {
      var now = 10000;
      final limiter = RateLimiter(windowMs: 5000, clock: () => now);

      expect(limiter.shouldAllow('TypeError::oops'), isTrue);
      expect(limiter.shouldAllow('RangeError::bad'), isTrue);

      now = 12000;
      // Both should be blocked within their windows.
      expect(limiter.shouldAllow('TypeError::oops'), isFalse);
      expect(limiter.shouldAllow('RangeError::bad'), isFalse);

      // A new fingerprint should still be allowed.
      expect(limiter.shouldAllow('StateError::nope'), isTrue);
    });

    test('clear resets all tracked fingerprints', () {
      var now = 10000;
      final limiter = RateLimiter(windowMs: 60000, clock: () => now);

      limiter.shouldAllow('TypeError::oops');
      now = 11000;
      expect(limiter.shouldAllow('TypeError::oops'), isFalse);

      limiter.clear();
      expect(limiter.shouldAllow('TypeError::oops'), isTrue);
    });

    test('fingerprint static method returns correct format', () {
      expect(
        RateLimiter.fingerprint('TypeError', 'null is not an object'),
        equals('TypeError::null is not an object'),
      );
      expect(
        RateLimiter.fingerprint('RangeError', 'index out of range'),
        equals('RangeError::index out of range'),
      );
    });

    test('fingerprint handles empty strings', () {
      expect(RateLimiter.fingerprint('', ''), equals('::'));
      expect(RateLimiter.fingerprint('Error', ''), equals('Error::'));
    });

    test('minimum window is clamped to 1000ms', () {
      final limiter = RateLimiter(windowMs: 100);
      expect(limiter.windowMs, equals(1000));

      final limiter2 = RateLimiter(windowMs: 0);
      expect(limiter2.windowMs, equals(1000));

      final limiter3 = RateLimiter(windowMs: -500);
      expect(limiter3.windowMs, equals(1000));
    });

    test('window at exactly 1000ms is not clamped', () {
      final limiter = RateLimiter(windowMs: 1000);
      expect(limiter.windowMs, equals(1000));
    });

    test('max fingerprint cap: allows without tracking at capacity', () {
      final now = 10000;
      final limiter = RateLimiter(windowMs: 60000, clock: () => now);

      // Fill to exactly _maxFingerprints (10000).
      for (var i = 0; i < 10000; i++) {
        expect(limiter.shouldAllow('error-$i::msg'), isTrue);
      }

      // The 10001st unique fingerprint should be allowed (not blocked).
      expect(limiter.shouldAllow('overflow::msg'), isTrue);

      // But it should NOT have been tracked — so allowing it again should
      // still return true (it's still "new" each time).
      expect(limiter.shouldAllow('overflow::msg'), isTrue);
    });

    test('prune removes expired entries', () {
      var now = 10000;
      final limiter = RateLimiter(windowMs: 5000, clock: () => now);

      limiter.shouldAllow('old::entry');
      now = 11000;
      limiter.shouldAllow('newer::entry');

      // Advance past old entry's window but not newer's.
      now = 15000;
      // shouldAllow triggers prune internally.
      // 'old::entry' was seen at 10000, window is 5000, now is 15000
      // -> 15000 - 10000 = 5000 >= 5000, so it's expired and pruned.
      expect(limiter.shouldAllow('old::entry'), isTrue);

      // 'newer::entry' was seen at 11000, 15000 - 11000 = 4000 < 5000,
      // so it should still be blocked.
      expect(limiter.shouldAllow('newer::entry'), isFalse);
    });

    test('default window is 60000ms', () {
      final limiter = RateLimiter();
      expect(limiter.windowMs, equals(60000));
    });
  });
}
