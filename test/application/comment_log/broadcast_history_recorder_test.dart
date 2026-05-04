import 'package:comerune/application/comment_log/broadcast_history_recorder.dart';
import 'package:comerune/data/comment_log/broadcast_history_store.dart';
import 'package:comerune/domain/comment_log/broadcast_history_entry.dart';
import 'package:comerune/presentation/screens/comment_screen_config.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapturingStore implements BroadcastHistoryStore {
  final List<BroadcastHistoryEntry> added = <BroadcastHistoryEntry>[];

  @override
  Future<void> add(BroadcastHistoryEntry entry) async {
    added.add(entry);
  }

  @override
  Future<void> clearAll() async {}

  @override
  List<BroadcastHistoryEntry> loadAll() =>
      List<BroadcastHistoryEntry>.from(added);

  @override
  Future<void> removeByLv(String lv) async {
    added.removeWhere((BroadcastHistoryEntry e) => e.lv == lv);
  }

  @override
  Future<void> flushPendingWrites() async {}
}

BroadcastEndedStatsSnapshot _snapshot({
  required String lv,
  required bool isBroadcaster,
  String? programTitle,
  int peakMinuteCount = 3,
  int peakOffset = 5,
}) {
  return BroadcastEndedStatsSnapshot(
    lv: lv,
    endedAt: DateTime.utc(2026, 5, 1, 12, 0),
    totalComments: 10,
    uniqueUserCount: 4,
    durationSeconds: 600,
    programTitle: programTitle,
    broadcasterUserId: '12345',
    broadcasterName: '放送者A',
    beginAt: DateTime.utc(2026, 5, 1, 11, 50),
    peakMinuteOffset: peakOffset,
    peakMinuteCount: peakMinuteCount,
    peaks: const <BroadcastEndedStatsPeak>[
      BroadcastEndedStatsPeak(minuteOffset: 5, label: '開始5分', commentCount: 3),
    ],
    isBroadcaster: isBroadcaster,
  );
}

void main() {
  group('recordBroadcastHistoryFromSnapshot', () {
    test(
      'records the entry when isBroadcaster=true and lv non-empty',
      () async {
        final _CapturingStore store = _CapturingStore();
        final Future<void>? scheduled = recordBroadcastHistoryFromSnapshot(
          snapshot: _snapshot(
            lv: 'lv1',
            isBroadcaster: true,
            programTitle: 'タイトル',
          ),
          store: store,
        );
        expect(scheduled, isNotNull);
        await scheduled;
        expect(store.added, hasLength(1));
        expect(store.added.first.lv, 'lv1');
        expect(store.added.first.programTitle, 'タイトル');
        expect(store.added.first.totalComments, 10);
        expect(store.added.first.peaks, hasLength(1));
        expect(store.added.first.peaks.first.label, '開始5分');
      },
    );

    test(
      'isBroadcaster=false drops the snapshot (viewer-only sessions ignored)',
      () async {
        final _CapturingStore store = _CapturingStore();
        final Future<void>? scheduled = recordBroadcastHistoryFromSnapshot(
          snapshot: _snapshot(lv: 'lv1', isBroadcaster: false),
          store: store,
        );
        expect(scheduled, isNull);
        expect(store.added, isEmpty);
      },
    );

    test(
      'empty lv drops the snapshot (defensive against schema break)',
      () async {
        final _CapturingStore store = _CapturingStore();
        final Future<void>? scheduled = recordBroadcastHistoryFromSnapshot(
          snapshot: _snapshot(lv: '', isBroadcaster: true),
          store: store,
        );
        expect(scheduled, isNull);
        expect(store.added, isEmpty);
      },
    );

    test('peaks list field is preserved through the conversion', () async {
      final _CapturingStore store = _CapturingStore();
      await recordBroadcastHistoryFromSnapshot(
        snapshot: BroadcastEndedStatsSnapshot(
          lv: 'lv1',
          endedAt: DateTime.utc(2026, 5, 1),
          totalComments: 1,
          uniqueUserCount: 1,
          durationSeconds: 1,
          peaks: const <BroadcastEndedStatsPeak>[
            BroadcastEndedStatsPeak(
              minuteOffset: 0,
              label: '開始0分',
              commentCount: 1,
            ),
            BroadcastEndedStatsPeak(
              minuteOffset: 5,
              label: '開始5分',
              commentCount: 2,
            ),
          ],
          isBroadcaster: true,
        ),
        store: store,
      );
      expect(store.added.first.peaks, hasLength(2));
      expect(store.added.first.peaks[0].minuteOffset, 0);
      expect(store.added.first.peaks[1].minuteOffset, 5);
    });
  });
}
