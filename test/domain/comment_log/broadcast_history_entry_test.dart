import 'dart:convert';

import 'package:comerune/domain/comment_log/broadcast_history_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BroadcastHistoryEntry.toJson / tryFromJson', () {
    test('round-trip preserves all populated fields', () {
      final BroadcastHistoryEntry entry = BroadcastHistoryEntry(
        lv: 'lv999',
        recordedAt: DateTime.utc(2026, 5, 1, 12, 30),
        programTitle: 'タイトル',
        broadcasterUserId: '12345',
        broadcasterName: '放送者A',
        beginAt: DateTime.utc(2026, 5, 1, 12, 0),
        endedAt: DateTime.utc(2026, 5, 1, 12, 30),
        totalComments: 100,
        uniqueUserCount: 30,
        durationSeconds: 1800,
        peakMinuteOffset: 25,
        peakMinuteCount: 18,
        peaks: const <BroadcastHistoryPeak>[
          BroadcastHistoryPeak(
            minuteOffset: 25,
            label: '開始25分',
            commentCount: 18,
          ),
        ],
      );

      final BroadcastHistoryEntry? round = BroadcastHistoryEntry.tryFromJson(
        entry.toJson(),
      );
      expect(round, isNotNull);
      expect(round!.lv, 'lv999');
      expect(round.programTitle, 'タイトル');
      expect(round.broadcasterUserId, '12345');
      expect(round.broadcasterName, '放送者A');
      expect(round.totalComments, 100);
      expect(round.uniqueUserCount, 30);
      expect(round.durationSeconds, 1800);
      expect(round.peakMinuteOffset, 25);
      expect(round.peakMinuteCount, 18);
      expect(round.peaks, hasLength(1));
      expect(round.peaks.first.label, '開始25分');
      expect(round.peaks.first.commentCount, 18);
    });

    test('tryFromJson returns null on missing required keys', () {
      expect(
        BroadcastHistoryEntry.tryFromJson(<String, Object?>{
          'recordedAt': DateTime.utc(2026, 5, 1).toIso8601String(),
        }),
        isNull,
      );
      expect(
        BroadcastHistoryEntry.tryFromJson(<String, Object?>{'lv': 'lv1'}),
        isNull,
      );
      expect(BroadcastHistoryEntry.tryFromJson('not a map'), isNull);
    });

    test('tryFromJson tolerates extra unknown keys (forward-compat)', () {
      final BroadcastHistoryEntry? round =
          BroadcastHistoryEntry.tryFromJson(<String, Object?>{
            'lv': 'lv1',
            'recordedAt': DateTime.utc(2026, 5, 1).toIso8601String(),
            'totalComments': 5,
            'uniqueUserCount': 2,
            'durationSeconds': 60,
            'unknownFutureKey': 'ignored',
          });
      expect(round, isNotNull);
      expect(round!.lv, 'lv1');
    });

    test('tryFromJson rejects malformed lv values (defensive)', () {
      // lv must match `^lv\d+$`; anything with extras (e.g. query
      // injection attempts, traversal, suffixes) is dropped.
      const List<String> malformed = <String>[
        '',
        'foo',
        'LV1',
        'lv',
        'lv 1',
        'lv1?evil=1',
        'lv1/x',
        '../etc',
        'lv1#hash',
      ];
      for (final String bad in malformed) {
        final BroadcastHistoryEntry? round =
            BroadcastHistoryEntry.tryFromJson(<String, Object?>{
              'lv': bad,
              'recordedAt': DateTime.utc(2026, 5, 1).toIso8601String(),
              'totalComments': 0,
              'uniqueUserCount': 0,
              'durationSeconds': 0,
            });
        expect(round, isNull, reason: 'should reject lv="$bad"');
      }
    });

    test('tryFromJson clamps negative integer fields to 0', () {
      final BroadcastHistoryEntry? round =
          BroadcastHistoryEntry.tryFromJson(<String, Object?>{
            'lv': 'lv1',
            'recordedAt': DateTime.utc(2026, 5, 1).toIso8601String(),
            'totalComments': -3,
            'uniqueUserCount': -2,
            'durationSeconds': -100,
            'peakMinuteCount': -5,
            'peakMinuteOffset': -1,
          });
      expect(round, isNotNull);
      expect(round!.totalComments, 0);
      expect(round.uniqueUserCount, 0);
      expect(round.durationSeconds, 0);
      expect(round.peakMinuteCount, 0);
      expect(round.peakMinuteOffset, isNull);
    });

    test('encodeJson / tryDecodeJson round-trips through a String', () {
      final BroadcastHistoryEntry entry = BroadcastHistoryEntry(
        lv: 'lv2',
        recordedAt: DateTime.utc(2026, 5, 1, 8),
        totalComments: 1,
        uniqueUserCount: 1,
        durationSeconds: 1,
      );
      final String encoded = entry.encodeJson();
      // sanity: decoded JSON object includes the lv key
      final Object decoded = json.decode(encoded) as Object;
      expect(decoded, isA<Map<String, Object?>>());
      final BroadcastHistoryEntry? round = BroadcastHistoryEntry.tryDecodeJson(
        encoded,
      );
      expect(round, isNotNull);
      expect(round!.lv, 'lv2');
    });
  });

  group('BroadcastHistoryEntry.programPageUrl / peakMinuteLabel', () {
    test('programPageUrl points at the official niconico watch URL', () {
      final BroadcastHistoryEntry entry = BroadcastHistoryEntry(
        lv: 'lv348712105',
        recordedAt: DateTime.utc(2026, 5, 1),
        totalComments: 0,
        uniqueUserCount: 0,
        durationSeconds: 0,
      );
      expect(
        entry.programPageUrl,
        'https://live.nicovideo.jp/watch/lv348712105',
      );
    });

    test('peakMinuteLabel formats hour-spanning offsets', () {
      final BroadcastHistoryEntry entry = BroadcastHistoryEntry(
        lv: 'lv1',
        recordedAt: DateTime.utc(2026, 5, 1),
        totalComments: 0,
        uniqueUserCount: 0,
        durationSeconds: 0,
        peakMinuteOffset: 75,
        peakMinuteCount: 3,
      );
      expect(entry.peakMinuteLabel, '開始1時間15分');
    });
  });
}
