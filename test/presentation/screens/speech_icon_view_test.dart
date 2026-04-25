import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/comment_speech/src/models/speech_engine_state.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/theme/app_theme.dart';

/// Tests for the pure function [speechIconViewFor] extracted in Issue
/// #717 (ARCH-2). The decision ladder is identical to the previous
/// inline if/else chain inside `_SpeechStatusIcon._buildIcon`, so the
/// boundary cases here also act as a regression guard.
void main() {
  // A neutral light-theme palette is enough for these tests; we only
  // assert that the right [AppThemeColors] member is selected, not the
  // raw color value. Using the real theme colors keeps the assertions
  // robust against unrelated palette tweaks.
  final AppThemeColors theme = AppTheme.colorsFor(AppThemeMode.light);

  SpeechIconView call({
    SpeechEngineState engineState = SpeechEngineState.unknown,
    bool isStarted = false,
    bool isInitialized = false,
    bool isMuted = false,
    bool treatAsError = false,
    bool isAndroidTtsEngine = false,
  }) {
    return speechIconViewFor(
      engineState: engineState,
      isStarted: isStarted,
      isInitialized: isInitialized,
      isMuted: isMuted,
      treatAsError: treatAsError,
      themeColors: theme,
      isAndroidTtsEngine: isAndroidTtsEngine,
    );
  }

  group('speechIconViewFor', () {
    group('priority ladder — ERROR dominates', () {
      test('engineState=error overrides every other input '
          '(even initialised, started, muted)', () {
        // Issue #682's contract: a real failure must not be hidden by
        // the neutral hourglass / pause icons.
        final SpeechIconView v = call(
          engineState: SpeechEngineState.error,
          isInitialized: true,
          isStarted: true,
          isMuted: true,
        );
        expect(v.icon, Icons.error_outline);
        expect(v.color, theme.statusDisconnected);
        expect(v.tooltip, '読み上げ: エラー');
        expect(v.isError, isTrue);
      });

      test(
        'treatAsError=true overrides engineState=ready (cross-screen override)',
        () {
          // Issue #694: cross-screen availability notifier may publish
          // unavailable even when the local engineState has not yet
          // observed an error. The icon must still render ERROR.
          final SpeechIconView v = call(
            engineState: SpeechEngineState.ready,
            isInitialized: true,
            isStarted: true,
            treatAsError: true,
          );
          expect(v.icon, Icons.error_outline);
          expect(v.isError, isTrue);
        },
      );

      test(
        'isAndroidTtsEngine=true switches the error tooltip to the settings hint',
        () {
          // The Android-TTS-specific tooltip points the user at the
          // detailed warning card in 読み上げ設定.
          final SpeechIconView v = call(
            engineState: SpeechEngineState.error,
            isAndroidTtsEngine: true,
          );
          expect(v.tooltip, '読み上げ: エラー（読み上げ設定で詳細を確認してください）');
        },
      );

      test('isAndroidTtsEngine=false keeps the generic error tooltip', () {
        // VOICEVOX errors do not have a settings-side recovery hint
        // ("toggle speech off/on" is the recovery), so the tooltip
        // stays generic.
        final SpeechIconView v = call(
          engineState: SpeechEngineState.error,
          isAndroidTtsEngine: false,
        );
        expect(v.tooltip, '読み上げ: エラー');
      });
    });

    group('priority ladder — non-error states', () {
      test('!isInitialized → hourglass', () {
        final SpeechIconView v = call(); // all defaults: unknown / false
        expect(v.icon, Icons.hourglass_top);
        expect(v.color, theme.subtleTextColor);
        expect(v.tooltip, '読み上げ: 初期化中');
        expect(v.isError, isFalse);
      });

      test('isInitialized && !isStarted → paused', () {
        final SpeechIconView v = call(isInitialized: true);
        expect(v.icon, Icons.pause_circle_outline);
        expect(v.color, theme.subtleTextColor);
        expect(v.tooltip, '読み上げ: 停止中');
        expect(v.isError, isFalse);
      });

      test('isStarted && isMuted → volume_off', () {
        final SpeechIconView v = call(
          isInitialized: true,
          isStarted: true,
          isMuted: true,
          engineState: SpeechEngineState.ready,
        );
        expect(v.icon, Icons.volume_off);
        expect(v.color, theme.statusConnected);
        expect(v.tooltip, 'ミュート解除');
        expect(v.isError, isFalse);
      });

      test('isStarted && !isMuted → volume_up', () {
        final SpeechIconView v = call(
          isInitialized: true,
          isStarted: true,
          engineState: SpeechEngineState.ready,
        );
        expect(v.icon, Icons.volume_up);
        expect(v.color, theme.statusConnected);
        expect(v.tooltip, 'ミュート');
        expect(v.isError, isFalse);
      });
    });

    group('regression boundaries', () {
      test(
        'engineState=unknown with full ready conditions still renders the running icon',
        () {
          // After cross-screen recovery (PR #707) the local state can
          // transition to `unknown` while initialised+started still
          // hold. The icon must show the running state, not the
          // hourglass.
          final SpeechIconView v = call(
            engineState: SpeechEngineState.unknown,
            isInitialized: true,
            isStarted: true,
          );
          // Falls through `engineState == error` (false), `!isInitialized`
          // (false), `!isStarted` (false), `isMuted` (false) → volume_up.
          expect(v.icon, Icons.volume_up);
          expect(v.isError, isFalse);
        },
      );

      test(
        'isError flag is true if either engineState=error OR treatAsError',
        () {
          expect(call(engineState: SpeechEngineState.error).isError, isTrue);
          expect(call(treatAsError: true).isError, isTrue);
          expect(
            call(
              engineState: SpeechEngineState.error,
              treatAsError: true,
            ).isError,
            isTrue,
          );
          expect(call(engineState: SpeechEngineState.unknown).isError, isFalse);
        },
      );
    });
  });
}
