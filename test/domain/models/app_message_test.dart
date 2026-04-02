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

  test('AppMessage equality and hashCode are value-based for core fields', () {
    final DateTime timestamp = DateTime.parse('2026-03-22T00:00:02Z');

    final AppMessage left = AppMessage(
      id: 'message-003',
      timestamp: timestamp,
      userId: 'user-1',
      content: 'same',
      type: AppMessageType.chat,
      raw: <String, Object?>{'source': 'ndgr'},
    );
    final AppMessage right = AppMessage(
      id: 'message-003',
      timestamp: timestamp,
      userId: 'user-1',
      content: 'same',
      type: AppMessageType.chat,
      raw: <String, Object?>{'source': 'legacy'},
    );

    expect(left, equals(right));
    expect(left.hashCode, right.hashCode);
  });

  // TODO(issue-2/O1): 不等価テスト（異なる id → not equal）を追加して
  // equality の positive / negative 両方向を検証する。

  test('AppMessageType has expected values', () {
    expect(AppMessageType.values, <AppMessageType>[
      AppMessageType.chat,
      AppMessageType.operator,
      AppMessageType.notification,
      AppMessageType.gift,
      AppMessageType.nicoad,
    ]);
  });
}
