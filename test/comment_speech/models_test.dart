import 'package:flutter_test/flutter_test.dart';
import 'package:comerune/comment_speech/src/models/raw_comment.dart';
import 'package:comerune/comment_speech/src/models/submit_result.dart';
import 'package:comerune/comment_speech/src/models/speech_settings.dart';
import 'package:comerune/comment_speech/src/models/replace_rule.dart';
import 'package:comerune/comment_speech/src/models/speech_runtime_status.dart';
import 'package:comerune/comment_speech/src/models/speech_event.dart';

void main() {
  group('RawComment', () {
    test('toMap includes all fields', () {
      const comment = RawComment(
        id: 'c1',
        text: 'hello',
        userId: 'u1',
        postedAtEpochMs: 1700000000000,
        score: 5,
        isOwner: true,
      );
      final map = comment.toMap();
      expect(map['id'], 'c1');
      expect(map['text'], 'hello');
      expect(map['userId'], 'u1');
      expect(map['postedAtEpochMs'], 1700000000000);
      expect(map['score'], 5);
      expect(map['isOwner'], true);
    });

    test('toMap handles null optional fields', () {
      const comment = RawComment(id: 'c2', text: 'test', postedAtEpochMs: 0);
      final map = comment.toMap();
      expect(map['userId'], isNull);
      expect(map['score'], isNull);
      expect(map['isOwner'], false);
    });
  });

  group('SubmitResult', () {
    test('fromMap parses all fields', () {
      final result = SubmitResult.fromMap({
        'accepted': true,
        'skipped': false,
        'normalizedText': 'hello',
        'skipReason': null,
        'queueSize': 3,
      });
      expect(result.accepted, true);
      expect(result.skipped, false);
      expect(result.normalizedText, 'hello');
      expect(result.skipReason, isNull);
      expect(result.queueSize, 3);
    });

    test('fromMap uses defaults for missing fields', () {
      final result = SubmitResult.fromMap({});
      expect(result.accepted, false);
      expect(result.skipped, false);
      expect(result.normalizedText, isNull);
      expect(result.skipReason, isNull);
      expect(result.queueSize, 0);
    });

    test('fromMap handles skipped result', () {
      final result = SubmitResult.fromMap({
        'accepted': false,
        'skipped': true,
        'normalizedText': 'bad word here',
        'skipReason': 'ng_word',
        'queueSize': 0,
      });
      expect(result.accepted, false);
      expect(result.skipped, true);
      expect(result.skipReason, 'ng_word');
    });
  });

  group('SpeechSettings', () {
    test('default values match Kotlin side', () {
      const settings = SpeechSettings();
      expect(settings.enabled, true);
      expect(settings.speakerId, 10004); // VOICEVOX Nemo・女声3
      expect(settings.speedScale, 1.15);
      expect(settings.pitchScale, 0.0);
      expect(settings.intonationScale, 1.0);
      expect(settings.volumeScale, 0.7);
      expect(settings.prePhonemeLength, 0.1);
      expect(settings.postPhonemeLength, 0.1);
      expect(settings.maxTextLength, 50);
      expect(settings.maxQueueSize, 20);
      expect(settings.duplicateWindowMs, 5000);
      expect(settings.skipEmojiOnly, true);
      expect(settings.skipUrlOnly, true);
      expect(settings.replaceUrlWith, 'URL省略');
      expect(settings.trimLongTextSuffix, '、以下省略');
      expect(settings.dictionaryRules, isEmpty);
      expect(settings.ngWords, isEmpty);
      expect(settings.engineType, 'voicevox');
      expect(settings.androidTtsSpeed, 1.0);
      expect(settings.androidTtsPitch, 1.0);
      expect(settings.androidTtsVolume, 1.0);
      // Issue #965: configurable safety-net timeout default mirrors
      // AndroidTtsSpeaker.DEFAULT_SPEAK_TIMEOUT_MS (15s) so PR #963 behaviour
      // is preserved when callers do not override it.
      expect(settings.speakTimeoutMs, 15000);
    });

    test('SynthesisMode round-trip via storageValue', () {
      for (final mode in SynthesisMode.values) {
        expect(SynthesisMode.fromStorageValue(mode.storageValue), mode);
      }
    });

    test('SynthesisMode fromStorageValue defaults to audioQuery', () {
      expect(SynthesisMode.fromStorageValue(null), SynthesisMode.audioQuery);
      expect(
        SynthesisMode.fromStorageValue('UNKNOWN'),
        SynthesisMode.audioQuery,
      );
    });

    test('SynthesisMode fromStorageValue stays defensive against empty / '
        'literally bogus values', () {
      // 永続化値が空文字や旧バージョン由来の未知文字列でも、
      // 例外を投げず必ずデフォルトへフォールバックすること
      // （`SettingsStore.load()` 全体が倒れて画面が無限スピナーに
      // ならないための防御）。
      expect(SynthesisMode.fromStorageValue(''), SynthesisMode.audioQuery);
      expect(
        SynthesisMode.fromStorageValue('__not_a_real_enum_value__'),
        SynthesisMode.audioQuery,
      );
    });

    test('toMap includes all fields with defaults', () {
      const settings = SpeechSettings();
      final map = settings.toMap();
      // Issue #965: bumped from 23 → 24 after speakTimeoutMs was added.
      expect(map.length, 24);
      expect(map['enabled'], true);
      expect(map['synthesisMode'], 'AUDIO_QUERY');
      expect(map['speedScale'], 1.15);
      expect(map['dictionaryRules'], isEmpty);
      expect(map['ngWords'], isEmpty);
      expect(map['playerType'], 'audio_track');
      expect(map['speakTimeoutMs'], 15000);
    });

    test('toMap propagates a customized speakTimeoutMs '
        '(Issue #965 configurable timeout)', () {
      const settings = SpeechSettings(speakTimeoutMs: 30000);
      final map = settings.toMap();
      expect(map['speakTimeoutMs'], 30000);
    });

    test('equality distinguishes speakTimeoutMs '
        '(Issue #965 configurable timeout)', () {
      const base = SpeechSettings();
      const customized = SpeechSettings(speakTimeoutMs: 30000);
      expect(base, isNot(equals(customized)));
      expect(base.hashCode, isNot(equals(customized.hashCode)));
    });

    test('toMap serializes dictionary rules', () {
      const settings = SpeechSettings(
        dictionaryRules: <ReplaceRule>[
          ReplaceRule(pattern: 'w{2,}', replacement: 'わら'),
        ],
        ngWords: <String>['badword'],
      );
      final map = settings.toMap();
      final rules = map['dictionaryRules'] as List;
      expect(rules.length, 1);
      expect((rules[0] as Map)['pattern'], 'w{2,}');
      expect(map['ngWords'], ['badword']);
    });

    test('toMap includes engineType and androidTts fields', () {
      const settings = SpeechSettings(
        engineType: SpeechEngineType.androidTts,
        androidTtsSpeed: 1.5,
        androidTtsPitch: 0.8,
        androidTtsVolume: 0.6,
      );
      final map = settings.toMap();
      expect(map['engineType'], SpeechEngineType.androidTts);
      expect(map['androidTtsSpeed'], 1.5);
      expect(map['androidTtsPitch'], 0.8);
      expect(map['androidTtsVolume'], 0.6);
    });

    test('equality distinguishes engineType', () {
      const voicevox = SpeechSettings(engineType: SpeechEngineType.voicevox);
      const androidTts = SpeechSettings(
        engineType: SpeechEngineType.androidTts,
      );
      expect(voicevox, isNot(equals(androidTts)));
    });

    test('equality distinguishes androidTts parameters', () {
      const base = SpeechSettings(androidTtsSpeed: 1.0);
      const modified = SpeechSettings(androidTtsSpeed: 1.5);
      expect(base, isNot(equals(modified)));

      const basePitch = SpeechSettings(androidTtsPitch: 1.0);
      const modifiedPitch = SpeechSettings(androidTtsPitch: 0.5);
      expect(basePitch, isNot(equals(modifiedPitch)));

      const baseVolume = SpeechSettings(androidTtsVolume: 1.0);
      const modifiedVolume = SpeechSettings(androidTtsVolume: 0.3);
      expect(baseVolume, isNot(equals(modifiedVolume)));
    });

    test('hashCode differs for different engineType', () {
      const voicevox = SpeechSettings(engineType: SpeechEngineType.voicevox);
      const androidTts = SpeechSettings(
        engineType: SpeechEngineType.androidTts,
      );
      // Not guaranteed by contract, but highly likely for well-distributed hash.
      expect(voicevox.hashCode, isNot(equals(androidTts.hashCode)));
    });

    test('SpeechEngineType constants match Kotlin strings', () {
      expect(SpeechEngineType.voicevox, 'voicevox');
      expect(SpeechEngineType.androidTts, 'android_tts');
    });
  });

  group('ReplaceRule', () {
    test('toMap and fromMap round-trip', () {
      const rule = ReplaceRule(
        pattern: '初見',
        replacement: 'しょけん',
        enabled: true,
      );
      final map = rule.toMap();
      final restored = ReplaceRule.fromMap(map);
      expect(restored.pattern, '初見');
      expect(restored.replacement, 'しょけん');
      expect(restored.enabled, true);
    });

    test('fromMap defaults enabled to true', () {
      final rule = ReplaceRule.fromMap({
        'pattern': 'test',
        'replacement': 'replaced',
      });
      expect(rule.enabled, true);
    });

    test('fromMap respects enabled=false', () {
      final rule = ReplaceRule.fromMap({
        'pattern': 'test',
        'replacement': 'replaced',
        'enabled': false,
      });
      expect(rule.enabled, false);
    });
  });

  group('SpeechRuntimeStatus', () {
    test('fromMap parses all fields', () {
      final status = SpeechRuntimeStatus.fromMap({
        'enabled': true,
        'engineState': 'READY',
        'playerState': 'IDLE',
        'queueSize': 5,
        'currentCommentId': 'c1',
        'currentText': 'hello',
        'currentSpeakerId': 2,
        'started': true,
      });
      expect(status.enabled, true);
      expect(status.engineState, 'READY');
      expect(status.playerState, 'IDLE');
      expect(status.queueSize, 5);
      expect(status.currentCommentId, 'c1');
      expect(status.currentText, 'hello');
      expect(status.currentSpeakerId, 2);
      expect(status.started, true);
    });

    test('fromMap uses defaults for missing fields', () {
      final status = SpeechRuntimeStatus.fromMap({});
      expect(status.enabled, false);
      expect(status.engineState, 'UNKNOWN');
      expect(status.playerState, 'UNKNOWN');
      expect(status.queueSize, 0);
      expect(status.currentCommentId, isNull);
      expect(status.currentText, isNull);
      expect(status.currentSpeakerId, 0);
      expect(status.started, false);
    });

    test('fromMap defaults started to false when key is missing '
        '(Issue #915 backward compat with older native binaries)', () {
      // Older native binaries that have not been rebuilt with the
      // Issue #915 patch will not include `started` in their toMap
      // output. The Dart side must default to `false` (the safe
      // mirror initial value) instead of throwing or carrying the
      // last seen value.
      final status = SpeechRuntimeStatus.fromMap({
        'enabled': true,
        'engineState': 'READY',
        'playerState': 'IDLE',
        'queueSize': 0,
        'currentSpeakerId': 0,
      });
      expect(status.started, false);
    });

    test('fromMap reads started=false explicitly', () {
      final status = SpeechRuntimeStatus.fromMap({
        'enabled': true,
        'engineState': 'READY',
        'playerState': 'IDLE',
        'queueSize': 0,
        'currentSpeakerId': 0,
        'started': false,
      });
      expect(status.started, false);
    });

    test('equality and hashCode include started (Issue #915)', () {
      const a = SpeechRuntimeStatus(
        enabled: true,
        engineState: 'READY',
        playerState: 'IDLE',
        queueSize: 0,
        currentSpeakerId: 0,
        started: true,
      );
      const b = SpeechRuntimeStatus(
        enabled: true,
        engineState: 'READY',
        playerState: 'IDLE',
        queueSize: 0,
        currentSpeakerId: 0,
        started: false,
      );
      expect(a, isNot(equals(b)));
      // Hash differs is not contractually required, but it would be a
      // bug if SpeechRuntimeStatus dropped `started` from its hash —
      // that is exactly the kind of mistake this assertion catches.
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    test('default constructor leaves started=false', () {
      const status = SpeechRuntimeStatus(
        enabled: false,
        engineState: 'UNKNOWN',
        playerState: 'UNKNOWN',
        queueSize: 0,
        currentSpeakerId: 0,
      );
      expect(status.started, false);
    });

    test('fromMap sets startedReported=true when the started key is '
        'present (Issue #915 forward-compat guard)', () {
      // Both an explicit true and an explicit false must count as
      // "reported" — the flag tracks key *presence*, not the value.
      final reportedTrue = SpeechRuntimeStatus.fromMap({
        'enabled': true,
        'engineState': 'READY',
        'playerState': 'IDLE',
        'queueSize': 0,
        'currentSpeakerId': 0,
        'started': true,
      });
      final reportedFalse = SpeechRuntimeStatus.fromMap({
        'enabled': true,
        'engineState': 'READY',
        'playerState': 'IDLE',
        'queueSize': 0,
        'currentSpeakerId': 0,
        'started': false,
      });
      expect(reportedTrue.startedReported, true);
      expect(reportedFalse.startedReported, true);
    });

    test('fromMap sets startedReported=false when the started key is '
        'absent (old native binary, Issue #915 forward-compat guard)', () {
      // An old native binary that has not been rebuilt with the
      // Issue #915 patch omits `started` entirely. The defaulted
      // `started=false` must be distinguishable from a reported
      // `false` so the reconcile guard can refuse to trust it.
      final status = SpeechRuntimeStatus.fromMap({
        'enabled': true,
        'engineState': 'READY',
        'playerState': 'IDLE',
        'queueSize': 0,
        'currentSpeakerId': 0,
      });
      expect(status.started, false);
      expect(status.startedReported, false);
    });

    test('default constructor leaves startedReported=false', () {
      const status = SpeechRuntimeStatus(
        enabled: false,
        engineState: 'UNKNOWN',
        playerState: 'UNKNOWN',
        queueSize: 0,
        currentSpeakerId: 0,
      );
      expect(status.startedReported, false);
    });

    test('startedReported is excluded from == and hashCode '
        '(wire metadata, not logical state — Issue #915)', () {
      // Two statuses describing the SAME runtime must compare equal
      // regardless of whether the `started` key was transported. If
      // startedReported leaked into equality, an old-native status and
      // an otherwise-identical new-native status would spuriously
      // differ, breaking change-detection / dedup at every call site
      // that compares SpeechRuntimeStatus instances.
      final reported = SpeechRuntimeStatus.fromMap({
        'enabled': true,
        'engineState': 'READY',
        'playerState': 'IDLE',
        'queueSize': 0,
        'currentSpeakerId': 0,
        'started': false,
      });
      final notReported = SpeechRuntimeStatus.fromMap({
        'enabled': true,
        'engineState': 'READY',
        'playerState': 'IDLE',
        'queueSize': 0,
        'currentSpeakerId': 0,
      });
      // Same logical runtime (started=false either way), differing only
      // in wire-presence metadata.
      expect(reported.started, notReported.started);
      expect(reported.startedReported, isNot(notReported.startedReported));
      // Equality and hashCode must ignore the metadata difference.
      expect(reported, equals(notReported));
      expect(reported.hashCode, equals(notReported.hashCode));
    });
  });

  group('SpeechEvent', () {
    test('fromMap parses valid event', () {
      final event = SpeechEvent.fromMap({
        'type': 'speech_started',
        'payload': {'commentId': 'c1', 'text': 'hello'},
      });
      expect(event.type, 'speech_started');
      expect(event.payload['commentId'], 'c1');
      expect(event.payload['text'], 'hello');
    });

    test('fromMap handles missing type', () {
      final event = SpeechEvent.fromMap({
        'payload': {'size': 3},
      });
      expect(event.type, 'unknown');
    });

    test('fromMap handles missing payload', () {
      final event = SpeechEvent.fromMap({'type': 'error'});
      expect(event.type, 'error');
      expect(event.payload, isEmpty);
    });

    test('fromMap handles completely empty map', () {
      final event = SpeechEvent.fromMap({});
      expect(event.type, 'unknown');
      expect(event.payload, isEmpty);
    });

    test('fromMap handles all event types', () {
      for (final type in [
        'engine_state_changed',
        'queue_updated',
        'comment_skipped',
        'speech_started',
        'speech_completed',
        'speech_failed',
        'player_state_changed',
        'error',
      ]) {
        final event = SpeechEvent.fromMap({'type': type, 'payload': {}});
        expect(event.type, type);
      }
    });
  });
}
