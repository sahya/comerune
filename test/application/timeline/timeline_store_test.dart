import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/timeline/timeline_store.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';

AppMessage _message(int index) {
  return AppMessage(
    id: 'id-$index',
    timestamp: DateTime.parse(
      '2026-03-22T00:00:00Z',
    ).add(Duration(seconds: index)),
    userId: 'user-$index',
    content: 'content-$index',
    type: AppMessageType.chat,
  );
}

void main() {
  test('default capacity is 100', () {
    final TimelineStore store = TimelineStore();

    expect(store.capacity, 100);
  });

  test('adds messages and keeps ascending order', () {
    final TimelineStore store = TimelineStore(capacity: 10);
    store.add(_message(1));
    store.add(_message(2));
    store.add(_message(3));

    expect(store.messages.map((AppMessage m) => m.id).toList(), <String>[
      'id-1',
      'id-2',
      'id-3',
    ]);
  });

  test('drops oldest message when capacity is exceeded', () {
    final TimelineStore store = TimelineStore(capacity: 2);
    store.add(_message(1));
    store.add(_message(2));
    store.add(_message(3));

    expect(store.messages.map((AppMessage m) => m.id).toList(), <String>[
      'id-2',
      'id-3',
    ]);
  });

  test('addAll keeps only unique ids from incoming batch', () {
    final TimelineStore store = TimelineStore(capacity: 10);

    store.addAll(<AppMessage>[
      _message(1),
      _message(2),
      _message(1),
      _message(3),
    ]);

    expect(store.messages.map((AppMessage m) => m.id).toList(), <String>[
      'id-1',
      'id-2',
      'id-3',
    ]);
  });

  test('addAll notifies listeners once when state changes', () {
    final TimelineStore store = TimelineStore(capacity: 10);
    int notifyCount = 0;
    store.addListener(() {
      notifyCount += 1;
    });

    store.addAll(<AppMessage>[_message(1), _message(2), _message(3)]);
    expect(notifyCount, 1);

    store.addAll(<AppMessage>[_message(1), _message(2)]);
    expect(notifyCount, 1);
  });

  test('addAll trims oldest messages when capacity is exceeded', () {
    final TimelineStore store = TimelineStore(capacity: 2);

    store.addAll(<AppMessage>[_message(1), _message(2), _message(3)]);

    expect(store.messages.map((AppMessage m) => m.id).toList(), <String>[
      'id-2',
      'id-3',
    ]);
  });

  test('does not add duplicate id', () {
    final TimelineStore store = TimelineStore(capacity: 10);
    final AppMessage original = _message(1);
    final AppMessage duplicateWithDifferentBody = AppMessage(
      id: original.id,
      timestamp: original.timestamp.add(const Duration(seconds: 1)),
      userId: 'another-user',
      content: 'another-content',
      type: AppMessageType.operator,
    );

    store.add(original);
    store.add(duplicateWithDifferentBody);

    expect(store.messages.length, 1);
    expect(store.messages.first.content, 'content-1');
  });

  test('allows re-adding same id after older one is evicted by overflow', () {
    final TimelineStore store = TimelineStore(capacity: 2);
    final AppMessage first = _message(1);

    store.add(first);
    store.add(_message(2));
    store.add(_message(3));

    // id-1 was evicted, so adding it again is treated as a new message.
    // Because sorted insertion places it before id-2 and id-3, it gets
    // immediately trimmed again (oldest by timestamp).
    store.add(first);

    expect(store.messages.map((AppMessage m) => m.id).toList(), <String>[
      'id-2',
      'id-3',
    ]);
  });

  test('can add a message with null userId', () {
    final TimelineStore store = TimelineStore(capacity: 10);
    final AppMessage message = AppMessage(
      id: 'null-user-id',
      timestamp: DateTime.parse('2026-03-22T00:00:10Z'),
      userId: null,
      content: 'system message',
      type: AppMessageType.notification,
    );

    store.add(message);

    expect(store.messages.single.userId, isNull);
  });

  test('setCapacity trims oldest messages when reduced', () {
    final TimelineStore store = TimelineStore(capacity: 4);
    store.add(_message(1));
    store.add(_message(2));
    store.add(_message(3));
    store.add(_message(4));

    store.setCapacity(2);

    expect(store.capacity, 2);
    expect(store.messages.map((AppMessage m) => m.id).toList(), <String>[
      'id-3',
      'id-4',
    ]);
  });

  test('clear removes all messages', () {
    final TimelineStore store = TimelineStore(capacity: 10);
    store.add(_message(1));
    store.add(_message(2));

    store.clear();

    expect(store.messages, isEmpty);
  });

  test('capacity must be 1 or greater', () {
    expect(() => TimelineStore(capacity: 0), throwsArgumentError);
    expect(() => TimelineStore(capacity: -1), throwsArgumentError);

    final TimelineStore store = TimelineStore(capacity: 10);
    expect(() => store.setCapacity(0), throwsArgumentError);
  });

  test('notifies listeners when add, setCapacity and clear change state', () {
    final TimelineStore store = TimelineStore(capacity: 10);
    int notifyCount = 0;
    store.addListener(() {
      notifyCount += 1;
    });

    store.add(_message(1));
    store.setCapacity(5);
    store.clear();

    expect(notifyCount, 3);
  });

  test('does not notify listeners for duplicate add and no-op updates', () {
    final TimelineStore store = TimelineStore(capacity: 10);
    int notifyCount = 0;
    store.addListener(() {
      notifyCount += 1;
    });

    store.add(_message(1));
    store.add(_message(1));
    store.setCapacity(10);
    store.clear();
    store.clear();

    expect(notifyCount, 2);
  });

  test('add inserts out-of-order message at correct timestamp position', () {
    final TimelineStore store = TimelineStore(capacity: 10);
    store.add(_message(1));
    store.add(_message(3));
    store.add(_message(2)); // arrives late but has earlier timestamp

    expect(store.messages.map((AppMessage m) => m.id).toList(), <String>[
      'id-1',
      'id-2',
      'id-3',
    ]);
  });

  test('addAll sorts interleaved messages by timestamp', () {
    final TimelineStore store = TimelineStore(capacity: 10);
    store.add(_message(1));
    store.add(_message(5));

    // Batch arrives with timestamps between existing messages.
    store.addAll(<AppMessage>[_message(3), _message(2), _message(4)]);

    expect(store.messages.map((AppMessage m) => m.id).toList(), <String>[
      'id-1',
      'id-2',
      'id-3',
      'id-4',
      'id-5',
    ]);
  });

  test('add places message with equal timestamp after existing ones', () {
    final DateTime sameTime = DateTime.parse('2026-03-22T00:00:01Z');
    final TimelineStore store = TimelineStore(capacity: 10);
    store.add(
      AppMessage(
        id: 'a',
        timestamp: sameTime,
        content: 'first',
        type: AppMessageType.chat,
      ),
    );
    store.add(
      AppMessage(
        id: 'b',
        timestamp: sameTime,
        content: 'second',
        type: AppMessageType.chat,
      ),
    );

    expect(store.messages.map((AppMessage m) => m.id).toList(), <String>[
      'a',
      'b',
    ]);
  });

  test('trimming after sorted insert removes oldest by timestamp', () {
    final TimelineStore store = TimelineStore(capacity: 2);
    store.add(_message(3));
    store.add(_message(1)); // inserted at front due to earlier timestamp
    store.add(_message(2)); // inserted in middle; front (id-1) is trimmed

    expect(store.messages.map((AppMessage m) => m.id).toList(), <String>[
      'id-2',
      'id-3',
    ]);
  });

  group('displayCapacity preserves fetched history under live influx', () {
    // Regression for the bug where `TimelineStore.capacity` was wired to
    // `pastCommentFetchCount.historyCount`, causing every new live comment
    // to evict one freshly fetched past comment.
    //
    // Post-fix contract: capacity is `historyCount + timelineLiveCommentBufferSize`,
    // so the full fetched history survives while new live comments fill the
    // extra buffer.
    for (final PastCommentFetchCount value in PastCommentFetchCount.values) {
      test(
        'for ${value.name}: N past + buffer-sized live influx keeps all N past',
        () {
          final int historyCount = value.historyCount;
          final TimelineStore store = TimelineStore(
            capacity: value.displayCapacity,
          );

          // Seed the store with `historyCount` past comments (indices 1..N).
          final List<AppMessage> past = <AppMessage>[
            for (int i = 1; i <= historyCount; i++) _message(i),
          ];
          store.addAll(past);
          expect(store.messages.length, historyCount);

          // Fill the live buffer completely so the store is at max capacity,
          // but no past comment should be evicted yet.
          for (int i = 1; i <= timelineLiveCommentBufferSize; i++) {
            store.add(_message(historyCount + i));
          }

          expect(store.messages.length, value.displayCapacity);
          // The very first past comment (id-1) must still be present.
          expect(store.messages.first.id, 'id-1');
          expect(
            store.messages.take(historyCount).map((AppMessage m) => m.id),
            past.map((AppMessage m) => m.id),
          );
        },
      );
    }

    test(
      'one extra live comment past capacity evicts only the oldest past',
      () {
        // Smaller scale reproduction to assert first eviction timing precisely.
        const int historyCount = 3;
        const int liveBuffer = 2;
        final TimelineStore store = TimelineStore(
          capacity: historyCount + liveBuffer,
        );

        store.addAll(<AppMessage>[_message(1), _message(2), _message(3)]);
        store.add(_message(4));
        store.add(_message(5));
        // Now full (5/5). Past 1..3 all still present.
        expect(store.messages.map((AppMessage m) => m.id).toList(), <String>[
          'id-1',
          'id-2',
          'id-3',
          'id-4',
          'id-5',
        ]);

        // One more new live comment: the oldest past (id-1) is evicted.
        store.add(_message(6));
        expect(store.messages.map((AppMessage m) => m.id).toList(), <String>[
          'id-2',
          'id-3',
          'id-4',
          'id-5',
          'id-6',
        ]);
      },
    );
  });
}
