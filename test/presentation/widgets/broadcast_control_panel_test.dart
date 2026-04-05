import 'dart:async';

import 'package:comerune/data/broadcast/broadcast_control_repository.dart';
import 'package:comerune/data/follow/follow_program.dart';
import 'package:comerune/presentation/widgets/broadcast_control_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BroadcastControlPanel', () {
    testWidgets('shows nothing when program status is null', (
      WidgetTester tester,
    ) async {
      final FollowProgram program = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BroadcastControlPanel(
              program: program,
              onStart: () async => const BroadcastControlResult(success: true),
              onEnd: () async => const BroadcastControlResult(success: true),
            ),
          ),
        ),
      );

      expect(find.byType(BroadcastControlPanel), findsOneWidget);
      // SizedBox.shrink is rendered, no buttons visible.
      expect(find.text('放送を開始'), findsNothing);
      expect(find.text('スライドして放送を終了'), findsNothing);
    });

    testWidgets(
        'start button is hidden for reserved program (pending API verification)',
        (
      WidgetTester tester,
    ) async {
      final FollowProgram program = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
        status: ProgramStatus.reserved,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BroadcastControlPanel(
              program: program,
              onStart: () async => const BroadcastControlResult(success: true),
              onEnd: () async => const BroadcastControlResult(success: true),
            ),
          ),
        ),
      );

      // 放送開始ボタンはAPI実機検証完了まで非表示。
      expect(find.text('放送を開始'), findsNothing);
      expect(find.text('スライドして放送を終了'), findsNothing);
    });

    testWidgets('shows slide-to-end for on-air program', (
      WidgetTester tester,
    ) async {
      final FollowProgram program = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
        status: ProgramStatus.onAir,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BroadcastControlPanel(
              program: program,
              onStart: () async => const BroadcastControlResult(success: true),
              onEnd: () async => const BroadcastControlResult(success: true),
            ),
          ),
        ),
      );

      expect(find.text('放送を開始'), findsNothing);
      expect(find.text('スライドして放送を終了'), findsOneWidget);
    });

    testWidgets('shows remaining time for on-air program with endAt', (
      WidgetTester tester,
    ) async {
      final FollowProgram program = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
        status: ProgramStatus.onAir,
        endAt: DateTime.now().add(const Duration(hours: 1)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BroadcastControlPanel(
              program: program,
              onStart: () async => const BroadcastControlResult(success: true),
              onEnd: () async => const BroadcastControlResult(success: true),
            ),
          ),
        ),
      );

      // Should show remaining time with timer icon.
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      expect(find.textContaining('残り'), findsOneWidget);
    });

    // 以下の開始ボタン関連テストは、UIで非表示にしている間はスキップ。
    // 有効化時にskipを外すこと。
    testWidgets('start button shows countdown dialog on tap', (
      WidgetTester tester,
    ) async {
      final FollowProgram program = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
        status: ProgramStatus.reserved,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BroadcastControlPanel(
              program: program,
              onStart: () async => const BroadcastControlResult(success: true),
              onEnd: () async => const BroadcastControlResult(success: true),
            ),
          ),
        ),
      );

      await tester.tap(find.text('放送を開始'));
      await tester.pump();

      // Countdown dialog should appear.
      expect(find.text('放送を開始します'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);
    }, skip: true); // 放送開始ボタンはAPI実機検証完了まで非表示

    testWidgets('countdown dialog can be cancelled', (
      WidgetTester tester,
    ) async {
      bool startCalled = false;
      final FollowProgram program = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
        status: ProgramStatus.reserved,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BroadcastControlPanel(
              program: program,
              onStart: () async {
                startCalled = true;
                return const BroadcastControlResult(success: true);
              },
              onEnd: () async => const BroadcastControlResult(success: true),
            ),
          ),
        ),
      );

      await tester.tap(find.text('放送を開始'));
      await tester.pump();

      // Cancel the countdown.
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      // Start callback should NOT have been called.
      expect(startCalled, isFalse);
      // Dialog should be dismissed.
      expect(find.text('放送を開始します'), findsNothing);
    }, skip: true); // 放送開始ボタンはAPI実機検証完了まで非表示

    testWidgets('countdown completes and calls onStart', (
      WidgetTester tester,
    ) async {
      final Completer<BroadcastControlResult> completer =
          Completer<BroadcastControlResult>();
      final FollowProgram program = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
        status: ProgramStatus.reserved,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BroadcastControlPanel(
              program: program,
              onStart: () => completer.future,
              onEnd: () async => const BroadcastControlResult(success: true),
            ),
          ),
        ),
      );

      await tester.tap(find.text('放送を開始'));
      await tester.pump();

      // Advance through 3 seconds of countdown.
      await tester.pump(const Duration(seconds: 1)); // 3 → 2
      expect(find.text('2'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1)); // 2 → 1
      expect(find.text('1'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1)); // 1 → done
      await tester.pump(); // dialog closes

      // Complete the future to finish the async flow.
      completer.complete(const BroadcastControlResult(success: true));
      await tester.pumpAndSettle();

      // Success snackbar.
      expect(find.text('放送を開始しました'), findsOneWidget);
    }, skip: true); // 放送開始ボタンはAPI実機検証完了まで非表示

    testWidgets('shows login-required message for INVALID_PARAMS error', (
      WidgetTester tester,
    ) async {
      final FollowProgram program = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
        status: ProgramStatus.reserved,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BroadcastControlPanel(
              program: program,
              onStart: () async => const BroadcastControlResult(
                success: false,
                errorCode: 'INVALID_PARAMS',
              ),
              onEnd: () async => const BroadcastControlResult(success: true),
            ),
          ),
        ),
      );

      // Tap start → countdown → wait for completion.
      await tester.tap(find.text('放送を開始'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('ログインが必要です'), findsOneWidget);
    }, skip: true); // 放送開始ボタンはAPI実機検証完了まで非表示

    testWidgets('disabled state prevents interaction', (
      WidgetTester tester,
    ) async {
      bool startCalled = false;
      final FollowProgram program = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
        status: ProgramStatus.reserved,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BroadcastControlPanel(
              program: program,
              enabled: false,
              onStart: () async {
                startCalled = true;
                return const BroadcastControlResult(success: true);
              },
              onEnd: () async => const BroadcastControlResult(success: true),
            ),
          ),
        ),
      );

      // Button text should be present but tapping does nothing.
      expect(find.text('放送を開始'), findsOneWidget);
      await tester.tap(find.text('放送を開始'));
      await tester.pumpAndSettle();

      expect(startCalled, isFalse);
      // No dialog should appear.
      expect(find.text('放送を開始します'), findsNothing);
    }, skip: true); // 放送開始ボタンはAPI実機検証完了まで非表示

    testWidgets('shows ended program with no controls', (
      WidgetTester tester,
    ) async {
      final FollowProgram program = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
        status: ProgramStatus.ended,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BroadcastControlPanel(
              program: program,
              onStart: () async => const BroadcastControlResult(success: true),
              onEnd: () async => const BroadcastControlResult(success: true),
            ),
          ),
        ),
      );

      expect(find.text('放送を開始'), findsNothing);
      expect(find.text('スライドして放送を終了'), findsNothing);
    });
  });

  group('userFacingBroadcastError', () {
    test('returns login message for INVALID_PARAMS', () {
      expect(
        userFacingBroadcastError(
          '開始',
          const BroadcastControlResult(
            success: false,
            errorCode: 'INVALID_PARAMS',
          ),
        ),
        'ログインが必要です',
      );
    });

    test('returns login message for UNAUTHORIZED', () {
      expect(
        userFacingBroadcastError(
          '終了',
          const BroadcastControlResult(
            success: false,
            errorCode: 'UNAUTHORIZED',
          ),
        ),
        'ログインが必要です',
      );
    });

    test('returns permission message for FORBIDDEN', () {
      expect(
        userFacingBroadcastError(
          '開始',
          const BroadcastControlResult(
            success: false,
            errorCode: 'FORBIDDEN',
          ),
        ),
        '放送の開始権限がありません',
      );
    });

    test('returns not-found message for NOT_FOUND', () {
      expect(
        userFacingBroadcastError(
          '終了',
          const BroadcastControlResult(
            success: false,
            errorCode: 'NOT_FOUND',
          ),
        ),
        '番組が見つかりません',
      );
    });

    test('returns network message for NETWORK_ERROR', () {
      expect(
        userFacingBroadcastError(
          '開始',
          const BroadcastControlResult(
            success: false,
            errorCode: 'NETWORK_ERROR',
          ),
        ),
        'ネットワークエラーが発生しました',
      );
    });

    test('returns generic message for unknown error code', () {
      expect(
        userFacingBroadcastError(
          '終了',
          const BroadcastControlResult(
            success: false,
            errorCode: 'HTTP_500',
          ),
        ),
        '放送の終了に失敗しました',
      );
    });

    test('uses operation name in FORBIDDEN and default messages', () {
      final String startForbidden = userFacingBroadcastError(
        '開始',
        const BroadcastControlResult(
          success: false,
          errorCode: 'FORBIDDEN',
        ),
      );
      final String endForbidden = userFacingBroadcastError(
        '終了',
        const BroadcastControlResult(
          success: false,
          errorCode: 'FORBIDDEN',
        ),
      );
      expect(startForbidden, contains('開始'));
      expect(endForbidden, contains('終了'));
    });
  });
}
