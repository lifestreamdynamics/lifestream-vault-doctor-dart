import 'package:lifestream_doctor/src/crash_queue.dart';
import 'package:lifestream_doctor/src/memory_storage.dart';
import 'package:lifestream_doctor/src/types.dart';
import 'package:test/test.dart';

MemoryStorage makeStorage() => MemoryStorage();
CrashQueue makeQueue([MemoryStorage? storage]) =>
    CrashQueue(storage ?? makeStorage());

void main() {
  group('CrashQueue', () {
    test('enqueue adds report to queue', () async {
      final queue = makeQueue();
      await queue.enqueue('report content', '/crashes/test.md');
      expect(await queue.size(), equals(1));
    });

    test('dequeue returns oldest entry', () async {
      final queue = makeQueue();
      await queue.enqueue('first', '/path/first.md');
      await queue.enqueue('second', '/path/second.md');

      final entry = await queue.dequeue();
      expect(entry, isNotNull);
      expect(entry!.content, equals('first'));
      expect(entry.path, equals('/path/first.md'));
    });

    test('dequeue returns null when empty', () async {
      final queue = makeQueue();
      final entry = await queue.dequeue();
      expect(entry, isNull);
    });

    test('remove removes entry by id', () async {
      final queue = makeQueue();
      await queue.enqueue('report', '/path/report.md');

      final entry = await queue.dequeue();
      expect(entry, isNotNull);

      await queue.remove(entry!.id);
      expect(await queue.size(), equals(0));
    });

    test('markAttempted increments attempts count', () async {
      final queue = makeQueue();
      await queue.enqueue('report', '/path/report.md');

      final entry = await queue.dequeue();
      expect(entry, isNotNull);
      expect(entry!.attempts, equals(0));

      await queue.markAttempted(entry.id);

      final updated = await queue.dequeue();
      expect(updated, isNotNull);
      expect(updated!.attempts, equals(1));
    });

    test('markAttempted sets lastAttemptAt', () async {
      final queue = makeQueue();
      await queue.enqueue('report', '/path/report.md');

      final entry = await queue.dequeue();
      expect(entry, isNotNull);
      expect(entry!.lastAttemptAt, isNull);

      await queue.markAttempted(entry.id);

      final updated = await queue.dequeue();
      expect(updated, isNotNull);
      expect(updated!.lastAttemptAt, isNotNull);
      // Verify it's a valid ISO-8601 timestamp
      expect(() => DateTime.parse(updated.lastAttemptAt!), returnsNormally);
    });

    test('size returns correct count', () async {
      final queue = makeQueue();
      expect(await queue.size(), equals(0));

      await queue.enqueue('a', '/path/a.md');
      expect(await queue.size(), equals(1));

      await queue.enqueue('b', '/path/b.md');
      expect(await queue.size(), equals(2));

      await queue.enqueue('c', '/path/c.md');
      expect(await queue.size(), equals(3));
    });

    test('flush with successful handler sends all reports', () async {
      final queue = makeQueue();
      await queue.enqueue('a', '/path/a.md');
      await queue.enqueue('b', '/path/b.md');
      await queue.enqueue('c', '/path/c.md');

      final sent = <String>[];
      final result = await queue.flush((report) async {
        sent.add(report.content);
      });

      expect(result.sent, equals(3));
      expect(result.failed, equals(0));
      expect(result.deadLettered, equals(0));
      expect(sent, equals(['a', 'b', 'c']));
      expect(await queue.size(), equals(0));
    });

    test('flush with failing handler marks as failed', () async {
      final queue = makeQueue();
      await queue.enqueue('report', '/path/report.md');

      final result = await queue.flush((report) async {
        throw Exception('network error');
      });

      expect(result.sent, equals(0));
      expect(result.failed, equals(1));
      expect(result.deadLettered, equals(0));
      expect(await queue.size(), equals(1));
    });

    test('flush dead-letters after MAX_ATTEMPTS failures', () async {
      final storage = makeStorage();
      final queue = CrashQueue(storage);
      await queue.enqueue('report', '/path/report.md');

      // Fail maxAttempts - 1 times (so attempts = 4 after these flushes)
      for (var i = 0; i < CrashQueue.maxAttempts - 1; i++) {
        await queue.flush((report) async {
          throw Exception('fail');
        });
      }

      // At this point the report has 4 attempts. One more failure -> dead letter.
      expect(await queue.size(), equals(1));

      final result = await queue.flush((report) async {
        throw Exception('fail again');
      });

      expect(result.deadLettered, equals(1));
      expect(result.failed, equals(0));
      expect(await queue.size(), equals(0));
    });

    test('flush mixed: some succeed, some fail, some dead-lettered', () async {
      final storage = makeStorage();
      final queue = CrashQueue(storage);

      // Build up the dead-letter candidate by repeatedly enqueuing and
      // flushing a single entry until it has maxAttempts-1 failures.
      await queue.enqueue('will-dead-letter', '/path/dead.md');
      for (var i = 0; i < CrashQueue.maxAttempts - 1; i++) {
        await queue.flush((report) async {
          throw Exception('fail');
        });
      }
      // "will-dead-letter" now has maxAttempts-1 attempts.

      // Add the other two entries after so they have 0 attempts.
      await queue.enqueue('will-succeed', '/path/success.md');
      await queue.enqueue('will-fail', '/path/fail.md');

      // Final flush: "will-dead-letter" fails and exceeds threshold -> dead
      // lettered. "will-succeed" succeeds -> sent. "will-fail" fails once ->
      // stays in queue.
      final result = await queue.flush((report) async {
        if (report.content != 'will-succeed') {
          throw Exception('fail');
        }
      });

      expect(result.sent, equals(1));
      expect(result.deadLettered, equals(1));
      expect(result.failed, equals(1));
    });

    test('clear empties the queue', () async {
      final queue = makeQueue();
      await queue.enqueue('a', '/path/a.md');
      await queue.enqueue('b', '/path/b.md');
      expect(await queue.size(), equals(2));

      await queue.clear();
      expect(await queue.size(), equals(0));
    });

    test('overflow: enqueue more than maxQueueSize drops oldest', () async {
      final queue = makeQueue();

      // Enqueue maxQueueSize + 5 items
      for (var i = 0; i < CrashQueue.maxQueueSize + 5; i++) {
        await queue.enqueue('report-$i', '/path/report-$i.md');
      }

      expect(await queue.size(), equals(CrashQueue.maxQueueSize));

      // The oldest 5 should have been dropped
      final oldest = await queue.dequeue();
      expect(oldest, isNotNull);
      expect(oldest!.content, equals('report-5'));
    });

    test('persistence: data survives across queue instances', () async {
      final storage = makeStorage();
      final queue1 = CrashQueue(storage);

      await queue1.enqueue('persisted-report', '/path/persisted.md');
      await queue1.enqueue('second-report', '/path/second.md');

      // Create a new queue with the same storage
      final queue2 = CrashQueue(storage);

      expect(await queue2.size(), equals(2));
      final entry = await queue2.dequeue();
      expect(entry, isNotNull);
      expect(entry!.content, equals('persisted-report'));
    });

    test('corrupted storage: invalid JSON returns empty queue', () async {
      final storage = makeStorage();
      await storage.setItem('doctor:queue', 'not valid json!!!');

      final queue = CrashQueue(storage);
      expect(await queue.size(), equals(0));
      expect(await queue.dequeue(), isNull);
    });

    test('corrupted storage: non-array JSON returns empty queue', () async {
      final storage = makeStorage();
      await storage.setItem('doctor:queue', '{"not": "an array"}');

      final queue = CrashQueue(storage);
      expect(await queue.size(), equals(0));
      expect(await queue.dequeue(), isNull);
    });

    test('corrupted storage: null returns empty queue', () async {
      final storage = makeStorage();
      // Don't set anything — getItem returns null

      final queue = CrashQueue(storage);
      expect(await queue.size(), equals(0));
      expect(await queue.dequeue(), isNull);
    });

    test('FlushResult has correct counts', () async {
      final queue = makeQueue();
      await queue.enqueue('a', '/path/a.md');
      await queue.enqueue('b', '/path/b.md');

      final result = await queue.flush((report) async {
        if (report.content == 'b') {
          throw Exception('fail');
        }
      });

      expect(result.sent, equals(1));
      expect(result.failed, equals(1));
      expect(result.deadLettered, equals(0));
    });

    test('queue entry has correct queuedAt timestamp', () async {
      final before = DateTime.now().toUtc();
      final queue = makeQueue();
      await queue.enqueue('report', '/path/report.md');
      final after = DateTime.now().toUtc();

      final entry = await queue.dequeue();
      expect(entry, isNotNull);

      final queuedAt = DateTime.parse(entry!.queuedAt);
      expect(
        queuedAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        queuedAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('multiple enqueue/dequeue cycles', () async {
      final queue = makeQueue();

      // Cycle 1: enqueue and dequeue
      await queue.enqueue('cycle-1', '/path/cycle1.md');
      expect(await queue.size(), equals(1));
      final entry1 = await queue.dequeue();
      expect(entry1!.content, equals('cycle-1'));
      await queue.remove(entry1.id);
      expect(await queue.size(), equals(0));

      // Cycle 2: enqueue multiple, dequeue one at a time
      await queue.enqueue('cycle-2a', '/path/cycle2a.md');
      await queue.enqueue('cycle-2b', '/path/cycle2b.md');
      expect(await queue.size(), equals(2));

      final entry2a = await queue.dequeue();
      expect(entry2a!.content, equals('cycle-2a'));
      await queue.remove(entry2a.id);

      final entry2b = await queue.dequeue();
      expect(entry2b!.content, equals('cycle-2b'));
      await queue.remove(entry2b.id);
      expect(await queue.size(), equals(0));

      // Cycle 3: enqueue after clearing
      await queue.enqueue('cycle-3', '/path/cycle3.md');
      await queue.clear();
      expect(await queue.size(), equals(0));
      expect(await queue.dequeue(), isNull);
    });

    test('remove non-existent id does not affect queue', () async {
      final queue = makeQueue();
      await queue.enqueue('report', '/path/report.md');
      await queue.remove('non-existent-id');
      expect(await queue.size(), equals(1));
    });

    test('markAttempted on non-existent id does not affect queue', () async {
      final queue = makeQueue();
      await queue.enqueue('report', '/path/report.md');
      await queue.markAttempted('non-existent-id');

      final entry = await queue.dequeue();
      expect(entry!.attempts, equals(0));
    });

    test('enqueue preserves path correctly', () async {
      final queue = makeQueue();
      await queue.enqueue('content', '/crashes/2025/01/report.md');

      final entry = await queue.dequeue();
      expect(entry!.path, equals('/crashes/2025/01/report.md'));
    });

    test('each enqueued entry has a unique id', () async {
      final queue = makeQueue();
      await queue.enqueue('a', '/path/a.md');
      await queue.enqueue('b', '/path/b.md');
      await queue.enqueue('c', '/path/c.md');

      final ids = <String>{};
      var entry = await queue.dequeue();
      while (entry != null) {
        ids.add(entry.id);
        await queue.remove(entry.id);
        entry = await queue.dequeue();
      }
      expect(ids, hasLength(3));
    });

    test('corrupted storage: list of non-map entries returns empty queue',
        () async {
      final storage = makeStorage();
      await storage.setItem('doctor:queue', '[1, 2, 3]');
      final queue = CrashQueue(storage);
      expect(await queue.size(), equals(0));
    });

    test('flush with empty queue returns zero counts', () async {
      final queue = makeQueue();
      Future<void> handler(QueuedReport report) async {}
      final result = await queue.flush(handler);
      expect(result.sent, equals(0));
      expect(result.failed, equals(0));
      expect(result.deadLettered, equals(0));
    });

    test('custom storage key isolates queues', () async {
      final storage = makeStorage();
      final queue1 = CrashQueue(storage, storageKey: 'queue:alpha');
      final queue2 = CrashQueue(storage, storageKey: 'queue:beta');

      await queue1.enqueue('alpha-report', '/path/alpha.md');
      await queue2.enqueue('beta-report', '/path/beta.md');

      expect(await queue1.size(), equals(1));
      expect(await queue2.size(), equals(1));

      final entry1 = await queue1.dequeue();
      expect(entry1!.content, equals('alpha-report'));

      final entry2 = await queue2.dequeue();
      expect(entry2!.content, equals('beta-report'));
    });
  });
}
