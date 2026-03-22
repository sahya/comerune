import 'package:flutter_test/flutter_test.dart';

import '../../../lib/application/timeline/timeline_store.dart';
import '../../../lib/domain/models/app_message.dart';

AppMessage _message(int index) {
  return AppMessage(
    id: 'id-$index',
    timestamp: DateTime.parse('2026-03-22T00:00:00Z')
        .add(Duration(seconds: index)),
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
}
