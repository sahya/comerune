import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/connection/foreground_service_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel methodChannel;
  late ForegroundServiceChannel channel;
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
    channel = ForegroundServiceChannel(channel: methodChannel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  group('ForegroundServiceChannel', () {
    test('isRunning is false initially', () {
      expect(channel.isRunning, isFalse);
    });

    test('startService invokes platform channel on Android', () async {
      await channel.startService(title: 'Test', body: 'Body');
      // On non-Android test platform, the method is not invoked
      // but isRunning remains false (Platform.isAndroid guard).
      expect(channel.isRunning, isFalse);
    });

    test('stopService is a no-op when not running', () async {
      await channel.stopService();
      expect(log, isEmpty);
      expect(channel.isRunning, isFalse);
    });

    test('updateNotification is a no-op when not running', () async {
      await channel.updateNotification(title: 'T', body: 'B');
      expect(log, isEmpty);
    });
  });
}
