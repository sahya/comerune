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

    test('toMap includes all fields with defaults', () {
      const settings = SpeechSettings();
      final map = settings.toMap();
      expect(map.length, 19);
      expect(map['enabled'], true);
      expect(map['synthesisMode'], 'AUDIO_QUERY');
      expect(map['speedScale'], 1.15);
      expect(map['dictionaryRules'], isEmpty);
      expect(map['ngWords'], isEmpty);
      expect(map['playerType'], 'audio_track');
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
      });
      expect(status.enabled, true);
      expect(status.engineState, 'READY');
      expect(status.playerState, 'IDLE');
      expect(status.queueSize, 5);
      expect(status.currentCommentId, 'c1');
      expect(status.currentText, 'hello');
      expect(status.currentSpeakerId, 2);
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
