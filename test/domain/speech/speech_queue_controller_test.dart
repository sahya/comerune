import 'package:flutter_test/flutter_test.dart';

import '../../../lib/domain/models/app_message.dart';
import '../../../lib/domain/speech/speech_queue_controller.dart';

void main() {
  group('SpeechQueueController', () {
    test('drops oldest items when queue limit is exceeded', () {
      final SpeechQueueController controller = SpeechQueueController(
        queueLimit: 2,
        maxDelay: const Duration(minutes: 1),
      );

      expect(
        controller.enqueue(_message(id: 'm1', content: 'one', second: 0)),
        isTrue,
      );
      expect(
        controller.enqueue(_message(id: 'm2', content: 'two', second: 1)),
        isTrue,
      );
      expect(
        controller.enqueue(_message(id: 'm3', content: 'three', second: 2)),
        isTrue,
      );

      expect(controller.length, 2);
      expect(
        controller.items.map((SpeechQueueItem item) => item.messageId).toList(),
        <String>['m2', 'm3'],
      );
    });

    test('drops items that exceed max delay', () {
      final DateTime base = DateTime.parse('2026-03-22T00:00:00Z');
      final SpeechQueueController controller = SpeechQueueController(
        maxDelay: const Duration(seconds: 10),
      );

      expect(
        controller.enqueue(
          _message(id: 'm1', content: 'old', second: 0),
          now: base,
        ),
        isTrue,
      );
      expect(
        controller.enqueue(
          _message(id: 'm2', content: 'new', second: 11),
          now: base.add(const Duration(seconds: 11)),
        ),
        isTrue,
      );

      expect(controller.length, 1);
      expect(controller.items.single.messageId, 'm2');
    });

    test('replaces URL with fixed text URL', () {
      final SpeechQueueController controller = SpeechQueueController();

      expect(
        controller.enqueue(
          _message(
            id: 'm1',
            content: 'look https://example.com/path now',
            second: 0,
          ),
        ),
        isTrue,
      );

      final SpeechQueueItem? item = controller.dequeue();
      expect(item, isNotNull);
      expect(item!.text, 'look URL now');
    });

    test('suppresses consecutive same-user comments within one second', () {
      final SpeechQueueController controller = SpeechQueueController();

      expect(
        controller.enqueue(
          _message(
            id: 'm1',
            content: 'first',
            userId: 'u1',
            millisecond: 0,
          ),
        ),
        isTrue,
      );
      expect(
        controller.enqueue(
          _message(
            id: 'm2',
            content: 'second',
            userId: 'u1',
            millisecond: 500,
          ),
        ),
        isFalse,
      );
      expect(
        controller.enqueue(
          _message(
            id: 'm3',
            content: 'third',
            userId: 'u1',
            millisecond: 1000,
          ),
        ),
        isTrue,
      );

      expect(controller.length, 2);
      expect(
        controller.items.map((SpeechQueueItem item) => item.messageId).toList(),
        <String>['m1', 'm3'],
      );
    });

    test('skips comments that match ng word regular expressions', () {
      final SpeechQueueController controller = SpeechQueueController(
        ngWordPatterns: <String>[r'spam|禁止'],
      );

      expect(
        controller.enqueue(_message(id: 'm1', content: 'これはspamです', second: 0)),
        isFalse,
      );
      expect(
        controller.enqueue(_message(id: 'm2', content: 'normal', second: 1)),
        isTrue,
      );

      expect(controller.length, 1);
      expect(controller.items.single.messageId, 'm2');
    });

    test('ignores invalid ng word regular expressions', () {
      final SpeechQueueController controller = SpeechQueueController(
        ngWordPatterns: <String>['[', r'foo\d+'],
      );

      expect(
        controller.enqueue(_message(id: 'm1', content: 'foo123', second: 0)),
        isFalse,
      );
      expect(
        controller.enqueue(_message(id: 'm2', content: 'bar', second: 1)),
        isTrue,
      );

      expect(controller.length, 1);
      expect(controller.items.single.messageId, 'm2');
    });

    test('does not enqueue when auto read is off', () {
      final SpeechQueueController controller = SpeechQueueController(
        autoReadEnabled: false,
      );

      expect(
        controller.enqueue(_message(id: 'm1', content: 'hello', second: 0)),
        isFalse,
      );
      expect(controller.length, 0);

      controller.setAutoReadEnabled(true);
      expect(
        controller.enqueue(_message(id: 'm2', content: 'hello', second: 1)),
        isTrue,
      );
      expect(controller.length, 1);
    });

    test('does not enqueue legacy unsupported format message', () {
      final SpeechQueueController controller = SpeechQueueController();

      expect(
        controller.enqueue(
          _message(
            id: 'm1',
            content: kLegacyUnsupportedFormatMessage,
            second: 0,
          ),
        ),
        isFalse,
      );
      expect(controller.length, 0);
    });
  });
}

AppMessage _message({
  required String id,
  required String content,
  String? userId,
  int second = 0,
  int millisecond = 0,
}) {
  return AppMessage(
    id: id,
    timestamp: DateTime.parse(
      '2026-03-22T00:00:00Z',
    ).add(Duration(seconds: second, milliseconds: millisecond)),
    userId: userId,
    content: content,
    type: AppMessageType.chat,
    raw: const <String, Object?>{'source': 'test'},
  );
}
