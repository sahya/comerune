import 'package:flutter_test/flutter_test.dart';
import 'package:comerune/domain/models/app_message.dart';

void main() {
  test('AppMessage can be created with required fields', () {
    final DateTime timestamp = DateTime.parse('2026-03-22T00:00:00Z');
    final Map<String, Object?> raw = <String, Object?>{'source': 'ndgr'};

    final AppMessage message = AppMessage(
      id: 'message-001',
      timestamp: timestamp,
      userId: 'user-123',
      content: 'hello',
      type: AppMessageType.chat,
      raw: raw,
    );

    expect(message.id, 'message-001');
    expect(message.timestamp, timestamp);
    expect(message.userId, 'user-123');
    expect(message.content, 'hello');
    expect(message.type, AppMessageType.chat);
    expect(message.raw, raw);
  });

  test('AppMessage can be created without userId', () {
    final AppMessage message = AppMessage(
      id: 'message-002',
      timestamp: DateTime.parse('2026-03-22T00:00:01Z'),
      content: 'no user',
      type: AppMessageType.notification,
    );

    expect(message.userId, isNull);
    expect(message.raw, isNull);
  });

  test('AppMessage equality is based on id only', () {
    final AppMessage left = AppMessage(
      id: 'message-003',
      timestamp: DateTime.parse('2026-03-22T00:00:02Z'),
      userId: 'user-1',
      content: 'same',
      type: AppMessageType.chat,
      raw: <String, Object?>{'source': 'ndgr'},
    );
    final AppMessage right = AppMessage(
      id: 'message-003',
      timestamp: DateTime.parse('2026-03-22T00:00:05Z'),
      userId: 'user-2',
      content: 'different',
      type: AppMessageType.notification,
      raw: <String, Object?>{'source': 'legacy'},
    );

    expect(left, equals(right));
    expect(left.hashCode, right.hashCode);
  });

  test('AppMessage with different id is not equal', () {
    final DateTime timestamp = DateTime.parse('2026-03-22T00:00:02Z');

    final AppMessage left = AppMessage(
      id: 'message-003',
      timestamp: timestamp,
      userId: 'user-1',
      content: 'same',
      type: AppMessageType.chat,
    );
    final AppMessage right = AppMessage(
      id: 'message-004',
      timestamp: timestamp,
      userId: 'user-1',
      content: 'same',
      type: AppMessageType.chat,
    );

    expect(left, isNot(equals(right)));
    expect(left.hashCode, isNot(equals(right.hashCode)));
  });

  test('AppMessageType has expected values', () {
    expect(AppMessageType.values, <AppMessageType>[
      AppMessageType.chat,
      AppMessageType.operator,
      AppMessageType.notification,
      AppMessageType.system,
      AppMessageType.emotion,
      AppMessageType.gift,
      AppMessageType.nicoad,
    ]);
  });
}
