import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/connection/foreground_service_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel methodChannel;
  late List<MethodCall> log;

  setUp(() {
    log = <MethodCall>[];
    methodChannel = const MethodChannel(
      'com.example.comerune/foreground_service',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
      log.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  group('ForegroundServiceChannel (non-Android)', () {
    late ForegroundServiceChannel channel;

    setUp(() {
      channel = ForegroundServiceChannel(
        channel: methodChannel,
        platformOverride: false,
      );
    });

    test('isRunning is false initially', () {
      expect(channel.isRunning, isFalse);
    });

    test('startService is a no-op on non-Android', () async {
      await channel.startService(title: 'Test', body: 'Body');
      expect(log, isEmpty);
      expect(channel.isRunning, isFalse);
    });

    test('stopService is a no-op on non-Android', () async {
      await channel.stopService();
      expect(log, isEmpty);
    });

    test('updateNotification is a no-op on non-Android', () async {
      await channel.updateNotification(title: 'T', body: 'B');
      expect(log, isEmpty);
    });
  });

  group('ForegroundServiceChannel (Android)', () {
    late ForegroundServiceChannel channel;

    setUp(() {
      channel = ForegroundServiceChannel(
        channel: methodChannel,
        platformOverride: true,
      );
    });

    test('isRunning is false initially', () {
      expect(channel.isRunning, isFalse);
    });

    test('startService invokes platform channel and sets isRunning', () async {
      await channel.startService(title: 'Test Title', body: 'Test Body');

      expect(log, hasLength(1));
      expect(log.first.method, 'startService');
      expect(log.first.arguments, <String, String>{
        'title': 'Test Title',
        'body': 'Test Body',
      });
      expect(channel.isRunning, isTrue);
    });

    test('startService uses default title and body', () async {
      await channel.startService();

      expect(log, hasLength(1));
      expect(log.first.arguments, <String, String>{
        'title': 'comerune',
        'body': '接続中...',
      });
    });

    test('stopService invokes platform channel and clears isRunning', () async {
      await channel.startService();
      expect(channel.isRunning, isTrue);

      log.clear();
      await channel.stopService();

      expect(log, hasLength(1));
      expect(log.first.method, 'stopService');
      expect(channel.isRunning, isFalse);
    });

    test('stopService is a no-op when not running', () async {
      await channel.stopService();
      expect(log, isEmpty);
      expect(channel.isRunning, isFalse);
    });

    test('updateNotification invokes platform channel when running', () async {
      await channel.startService(title: 'Initial', body: 'Init');
      log.clear();

      await channel.updateNotification(title: 'Updated', body: 'New body');

      expect(log, hasLength(1));
      expect(log.first.method, 'updateNotification');
      expect(log.first.arguments, <String, String>{
        'title': 'Updated',
        'body': 'New body',
      });
    });

    test('updateNotification is a no-op when not running', () async {
      await channel.updateNotification(title: 'T', body: 'B');
      expect(log, isEmpty);
    });

    test('startService handles exception without crashing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
        throw PlatformException(code: 'ERROR', message: 'test error');
      });

      await channel.startService(title: 'T', body: 'B');
      expect(channel.isRunning, isFalse);
    });

    test('stopService handles exception without crashing', () async {
      // First start successfully.
      await channel.startService();
      expect(channel.isRunning, isTrue);

      // Now mock a failure for stop.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
        throw PlatformException(code: 'ERROR', message: 'test error');
      });

      await channel.stopService();
      // isRunning remains true because stop failed.
      expect(channel.isRunning, isTrue);
    });

    test('updateNotification handles exception without crashing', () async {
      await channel.startService();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
        throw PlatformException(code: 'ERROR', message: 'test error');
      });

      await channel.updateNotification(title: 'T', body: 'B');
      // Should not crash; isRunning remains true.
      expect(channel.isRunning, isTrue);
    });
  });
}
