import 'package:lifestream_doctor/src/breadcrumb_buffer.dart';
import 'package:lifestream_doctor/src/types.dart';
import 'package:test/test.dart';

void main() {
  group('BreadcrumbBuffer', () {
    late BreadcrumbBuffer buffer;

    setUp(() {
      buffer = BreadcrumbBuffer(capacity: 5);
    });

    Breadcrumb makeBreadcrumb({
      String timestamp = '2025-01-01T00:00:00.000Z',
      String type = 'test',
      String message = 'test message',
      Map<String, Object?>? data,
    }) {
      return Breadcrumb(
        timestamp: timestamp,
        type: type,
        message: message,
        data: data,
      );
    }

    test('adds and retrieves a single breadcrumb', () {
      buffer.add(makeBreadcrumb(message: 'hello'));
      final all = buffer.getAll();
      expect(all, hasLength(1));
      expect(all.first.message, equals('hello'));
    });

    test('returns breadcrumbs in oldest-first order', () {
      buffer.add(makeBreadcrumb(message: 'first'));
      buffer.add(makeBreadcrumb(message: 'second'));
      buffer.add(makeBreadcrumb(message: 'third'));

      final all = buffer.getAll();
      expect(all.map((b) => b.message).toList(),
          equals(['first', 'second', 'third']));
    });

    test('evicts oldest breadcrumbs when over capacity', () {
      for (var i = 0; i < 7; i++) {
        buffer.add(makeBreadcrumb(message: 'msg-$i'));
      }

      final all = buffer.getAll();
      expect(all, hasLength(5));
      // Oldest two (msg-0, msg-1) should be evicted.
      expect(all.map((b) => b.message).toList(),
          equals(['msg-2', 'msg-3', 'msg-4', 'msg-5', 'msg-6']));
    });

    test('auto-sets timestamp when not provided', () {
      final before = DateTime.now().toUtc();
      buffer.add(const Breadcrumb(
        timestamp: '',
        type: 'test',
        message: 'auto-ts',
      ));
      final after = DateTime.now().toUtc();

      final all = buffer.getAll();
      expect(all, hasLength(1));

      final ts = DateTime.parse(all.first.timestamp);
      expect(ts.isUtc, isTrue);
      // Timestamp should be between before and after.
      expect(
        ts.millisecondsSinceEpoch,
        greaterThanOrEqualTo(before.millisecondsSinceEpoch),
      );
      expect(
        ts.millisecondsSinceEpoch,
        lessThanOrEqualTo(after.millisecondsSinceEpoch),
      );
    });

    test('preserves explicit timestamp', () {
      const explicit = '2024-06-15T12:30:00.000Z';
      buffer.add(makeBreadcrumb(timestamp: explicit));

      final all = buffer.getAll();
      expect(all.first.timestamp, equals(explicit));
    });

    test('truncates type at 50 characters', () {
      final longType = 'a' * 100;
      buffer.add(makeBreadcrumb(type: longType));

      final all = buffer.getAll();
      expect(all.first.type.length, equals(50));
      expect(all.first.type, equals('a' * 50));
    });

    test('preserves type under 50 characters', () {
      const shortType = 'navigation';
      buffer.add(makeBreadcrumb(type: shortType));

      final all = buffer.getAll();
      expect(all.first.type, equals(shortType));
    });

    test('truncates message at 500 characters', () {
      final longMessage = 'b' * 1000;
      buffer.add(makeBreadcrumb(message: longMessage));

      final all = buffer.getAll();
      expect(all.first.message.length, equals(500));
      expect(all.first.message, equals('b' * 500));
    });

    test('preserves message under 500 characters', () {
      const shortMessage = 'clicked button';
      buffer.add(makeBreadcrumb(message: shortMessage));

      final all = buffer.getAll();
      expect(all.first.message, equals(shortMessage));
    });

    test('clear resets buffer', () {
      buffer.add(makeBreadcrumb(message: 'one'));
      buffer.add(makeBreadcrumb(message: 'two'));
      expect(buffer.size, equals(2));

      buffer.clear();
      expect(buffer.size, equals(0));
      expect(buffer.getAll(), isEmpty);
    });

    test('clear allows re-use of buffer', () {
      for (var i = 0; i < 5; i++) {
        buffer.add(makeBreadcrumb(message: 'before-$i'));
      }
      buffer.clear();

      buffer.add(makeBreadcrumb(message: 'after'));
      expect(buffer.size, equals(1));
      expect(buffer.getAll().first.message, equals('after'));
    });

    test('size returns current count', () {
      expect(buffer.size, equals(0));
      buffer.add(makeBreadcrumb());
      expect(buffer.size, equals(1));
      buffer.add(makeBreadcrumb());
      expect(buffer.size, equals(2));
    });

    test('size does not exceed capacity', () {
      for (var i = 0; i < 10; i++) {
        buffer.add(makeBreadcrumb());
      }
      expect(buffer.size, equals(5));
    });

    test('capacity is clamped to minimum 1', () {
      final tiny = BreadcrumbBuffer(capacity: 0);
      expect(tiny.capacity, equals(1));

      final negative = BreadcrumbBuffer(capacity: -10);
      expect(negative.capacity, equals(1));
    });

    test('buffer with capacity 1 keeps only latest', () {
      final single = BreadcrumbBuffer(capacity: 1);
      single.add(makeBreadcrumb(message: 'first'));
      single.add(makeBreadcrumb(message: 'second'));

      expect(single.size, equals(1));
      expect(single.getAll().first.message, equals('second'));
    });

    test('overflow: adding 20x capacity items maintains capacity', () {
      final buf = BreadcrumbBuffer(capacity: 10);
      for (var i = 0; i < 200; i++) {
        buf.add(makeBreadcrumb(message: 'item-$i'));
      }
      expect(buf.size, equals(10));

      final all = buf.getAll();
      expect(all, hasLength(10));
      // Should have the last 10 items.
      for (var i = 0; i < 10; i++) {
        expect(all[i].message, equals('item-${190 + i}'));
      }
    });

    test('getAll returns empty list when empty', () {
      expect(buffer.getAll(), isEmpty);
      expect(buffer.getAll(), isA<List<Breadcrumb>>());
    });

    test('data field is preserved', () {
      final data = {'key': 'value', 'count': 42};
      buffer.add(makeBreadcrumb(data: data));

      final all = buffer.getAll();
      expect(all.first.data, equals(data));
    });

    test('null data field is preserved', () {
      buffer.add(makeBreadcrumb());

      final all = buffer.getAll();
      expect(all.first.data, isNull);
    });

    test('default capacity is 50', () {
      final defaultBuffer = BreadcrumbBuffer();
      expect(defaultBuffer.capacity, equals(50));
    });

    test('maintains oldest-first order after wrapping', () {
      // Fill buffer completely then overflow by 2.
      for (var i = 0; i < 7; i++) {
        buffer.add(makeBreadcrumb(message: 'wrap-$i'));
      }

      final all = buffer.getAll();
      // Buffer wraps: oldest 2 evicted, remaining in order.
      expect(all.map((b) => b.message).toList(),
          equals(['wrap-2', 'wrap-3', 'wrap-4', 'wrap-5', 'wrap-6']));
    });
  });
}
