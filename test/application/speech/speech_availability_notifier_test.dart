import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/speech/speech_availability_notifier.dart';

void main() {
  group('SpeechAvailabilityNotifier (Issue #694)', () {
    test('initial value is unknown', () {
      final SpeechAvailabilityNotifier notifier = SpeechAvailabilityNotifier();
      addTearDown(notifier.dispose);

      expect(notifier.value, SpeechAvailability.unknown);
    });

    test(
      'publishAvailable transitions to available and notifies listeners',
      () {
        final SpeechAvailabilityNotifier notifier =
            SpeechAvailabilityNotifier();
        addTearDown(notifier.dispose);
        int callCount = 0;
        notifier.addListener(() => callCount++);

        notifier.publishAvailable();

        expect(notifier.value, SpeechAvailability.available);
        expect(
          callCount,
          1,
          reason:
              'Listeners must be notified exactly once when the value changes.',
        );
      },
    );

    test(
      'publishUnavailable transitions to unavailable and notifies listeners',
      () {
        final SpeechAvailabilityNotifier notifier =
            SpeechAvailabilityNotifier();
        addTearDown(notifier.dispose);
        int callCount = 0;
        notifier.addListener(() => callCount++);

        notifier.publishUnavailable();

        expect(notifier.value, SpeechAvailability.unavailable);
        expect(callCount, 1);
      },
    );

    test('publishing the same value twice does not double-notify', () {
      // Regression guard: equality dedup must hold so subscribers (e.g. the
      // AppBar icon) do not rebuild on no-op publishes from idempotent
      // re-checks.
      final SpeechAvailabilityNotifier notifier = SpeechAvailabilityNotifier();
      addTearDown(notifier.dispose);
      int callCount = 0;
      notifier.addListener(() => callCount++);

      notifier.publishUnavailable();
      notifier.publishUnavailable();
      notifier.publishUnavailable();

      expect(notifier.value, SpeechAvailability.unavailable);
      expect(callCount, 1);
    });

    test('reset returns to unknown and notifies', () {
      final SpeechAvailabilityNotifier notifier = SpeechAvailabilityNotifier();
      addTearDown(notifier.dispose);
      notifier.publishAvailable();
      int resetCalls = 0;
      notifier.addListener(() => resetCalls++);

      notifier.reset();

      expect(notifier.value, SpeechAvailability.unknown);
      expect(resetCalls, 1);
    });

    test('reset is a no-op when already unknown', () {
      final SpeechAvailabilityNotifier notifier = SpeechAvailabilityNotifier();
      addTearDown(notifier.dispose);
      int callCount = 0;
      notifier.addListener(() => callCount++);

      notifier.reset();

      expect(notifier.value, SpeechAvailability.unknown);
      expect(callCount, 0);
    });

    test('publish(available: true) is equivalent to publishAvailable', () {
      // Helper for the common bool-from-platform flow. Should not introduce
      // any extra notifications beyond the underlying enum transition.
      final SpeechAvailabilityNotifier notifier = SpeechAvailabilityNotifier();
      addTearDown(notifier.dispose);
      int callCount = 0;
      notifier.addListener(() => callCount++);

      notifier.publish(available: true);

      expect(notifier.value, SpeechAvailability.available);
      expect(callCount, 1);
    });

    test('publish(available: false) is equivalent to publishUnavailable', () {
      final SpeechAvailabilityNotifier notifier = SpeechAvailabilityNotifier();
      addTearDown(notifier.dispose);

      notifier.publish(available: false);

      expect(notifier.value, SpeechAvailability.unavailable);
      expect(notifier.isUnavailable, isTrue);
    });

    test('isUnavailable getter mirrors the enum', () {
      final SpeechAvailabilityNotifier notifier = SpeechAvailabilityNotifier();
      addTearDown(notifier.dispose);

      expect(notifier.isUnavailable, isFalse);
      notifier.publishAvailable();
      expect(notifier.isUnavailable, isFalse);
      notifier.publishUnavailable();
      expect(notifier.isUnavailable, isTrue);
      notifier.reset();
      expect(notifier.isUnavailable, isFalse);
    });

    test('can transition between every state pair', () {
      // Smoke test for the full state machine.
      final SpeechAvailabilityNotifier notifier = SpeechAvailabilityNotifier();
      addTearDown(notifier.dispose);
      final List<SpeechAvailability> seen = <SpeechAvailability>[];
      notifier.addListener(() => seen.add(notifier.value));

      notifier.publishAvailable();
      notifier.publishUnavailable();
      notifier.publishAvailable();
      notifier.reset();
      notifier.publishUnavailable();

      expect(seen, <SpeechAvailability>[
        SpeechAvailability.available,
        SpeechAvailability.unavailable,
        SpeechAvailability.available,
        SpeechAvailability.unknown,
        SpeechAvailability.unavailable,
      ]);
    });
  });
}
