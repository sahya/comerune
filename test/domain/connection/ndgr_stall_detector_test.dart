import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/connection/ndgr_stall_detector.dart';

void main() {
  group('NdgrStallDetector', () {
    test('notifies stall only once until next receive', () {
      DateTime now = DateTime.parse('2026-03-22T00:00:00Z');

      final NdgrStallDetector detector = NdgrStallDetector(
        threshold: const Duration(seconds: 15),
        now: () => now,
      );

      detector.markReceived();

      now = now.add(const Duration(seconds: 14));
      expect(detector.isStalled, isFalse);
      expect(detector.shouldNotifyStall(), isFalse);

      now = now.add(const Duration(seconds: 1));
      expect(detector.isStalled, isTrue);
      expect(detector.shouldNotifyStall(), isTrue);
      expect(detector.shouldNotifyStall(), isFalse);

      detector.markReceived(now);
      now = now.add(const Duration(seconds: 15));
      expect(detector.shouldNotifyStall(), isTrue);
    });

    test('is not stalled before first receive', () {
      DateTime now = DateTime.parse('2026-03-22T00:00:00Z');

      final NdgrStallDetector detector = NdgrStallDetector(
        threshold: const Duration(seconds: 15),
        now: () => now,
      );

      now = now.add(const Duration(minutes: 1));
      expect(detector.isStalled, isFalse);
      expect(detector.shouldNotifyStall(), isFalse);
      expect(detector.elapsedSinceLastReceived(), isNull);
    });

    test('reset clears last received timestamp and notification state', () {
      DateTime now = DateTime.parse('2026-03-22T00:00:00Z');

      final NdgrStallDetector detector = NdgrStallDetector(
        threshold: const Duration(seconds: 15),
        now: () => now,
      );

      detector.markReceived(now);
      now = now.add(const Duration(seconds: 15));
      expect(detector.shouldNotifyStall(), isTrue);

      detector.reset();
      expect(detector.lastReceivedAt, isNull);
      expect(detector.shouldNotifyStall(), isFalse);
    });
  });
}
