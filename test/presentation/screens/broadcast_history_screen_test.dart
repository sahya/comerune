import 'package:comerune/data/comment_log/broadcast_history_store.dart';
import 'package:comerune/domain/comment_log/broadcast_history_entry.dart';
import 'package:comerune/presentation/screens/broadcast_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStore implements BroadcastHistoryStore {
  _FakeStore(this._entries);

  final List<BroadcastHistoryEntry> _entries;
  int removeCount = 0;
  int clearCount = 0;
  String? lastRemovedLv;

  @override
  List<BroadcastHistoryEntry> loadAll() =>
      List<BroadcastHistoryEntry>.unmodifiable(_entries);

  @override
  Future<void> add(BroadcastHistoryEntry entry) async {
    _entries.insert(0, entry);
  }

  @override
  Future<void> removeByLv(String lv) async {
    removeCount++;
    lastRemovedLv = lv;
    _entries.removeWhere((BroadcastHistoryEntry e) => e.lv == lv);
  }

  @override
  Future<void> clearAll() async {
    clearCount++;
    _entries.clear();
  }

  @override
  Future<void> flushPendingWrites() async {}
}

BroadcastHistoryEntry _entry(
  String lv, {
  String? title,
  int totalComments = 5,
  int uniqueUserCount = 3,
  int durationSeconds = 600,
}) {
  return BroadcastHistoryEntry(
    lv: lv,
    recordedAt: DateTime.utc(2026, 5, 1, 12, 0),
    programTitle: title,
    totalComments: totalComments,
    uniqueUserCount: uniqueUserCount,
    durationSeconds: durationSeconds,
  );
}

void main() {
  group('BroadcastHistoryScreen', () {
    testWidgets('shows the empty state when there are no entries', (
      WidgetTester tester,
    ) async {
      final _FakeStore store = _FakeStore(<BroadcastHistoryEntry>[]);
      await tester.pumpWidget(
        MaterialApp(home: BroadcastHistoryScreen(store: store)),
      );

      expect(find.byKey(const Key('broadcast-history-empty-title')), findsOne);
      expect(
        find.byKey(const Key('broadcast-history-empty-privacy-note')),
        findsOne,
      );
      expect(find.byKey(const Key('broadcast-history-list')), findsNothing);
      // The clear-all button must be hidden when nothing is recorded.
      expect(
        find.byKey(const Key('broadcast-history-clear-all-button')),
        findsNothing,
      );
    });

    testWidgets('renders one tile per entry with the privacy note shown', (
      WidgetTester tester,
    ) async {
      final _FakeStore store = _FakeStore(<BroadcastHistoryEntry>[
        _entry('lv1', title: '番組A'),
        _entry('lv2', title: '番組B'),
      ]);
      await tester.pumpWidget(
        MaterialApp(home: BroadcastHistoryScreen(store: store)),
      );

      expect(find.byKey(const Key('broadcast-history-tile-lv1')), findsOne);
      expect(find.byKey(const Key('broadcast-history-tile-lv2')), findsOne);
      expect(find.byKey(const Key('broadcast-history-privacy-note')), findsOne);
      // Clear-all action should be visible when at least one entry exists.
      expect(
        find.byKey(const Key('broadcast-history-clear-all-button')),
        findsOne,
      );
    });

    testWidgets('tapping the tile opens the detail sheet', (
      WidgetTester tester,
    ) async {
      final _FakeStore store = _FakeStore(<BroadcastHistoryEntry>[
        _entry('lv1', title: '番組A'),
      ]);
      await tester.pumpWidget(
        MaterialApp(home: BroadcastHistoryScreen(store: store)),
      );

      await tester.tap(find.byKey(const Key('broadcast-history-tile-lv1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('broadcast-history-detail-title')), findsOne);
      expect(find.byKey(const Key('broadcast-history-detail-lv')), findsOne);
      expect(find.byKey(const Key('broadcast-history-detail-total')), findsOne);
      expect(
        find.byKey(const Key('broadcast-history-detail-open-program-page')),
        findsOne,
      );
    });

    testWidgets('clear-all confirmation deletes all entries', (
      WidgetTester tester,
    ) async {
      final _FakeStore store = _FakeStore(<BroadcastHistoryEntry>[
        _entry('lv1'),
        _entry('lv2'),
      ]);
      await tester.pumpWidget(
        MaterialApp(home: BroadcastHistoryScreen(store: store)),
      );

      await tester.tap(
        find.byKey(const Key('broadcast-history-clear-all-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('broadcast-history-clear-all-dialog')),
        findsOne,
      );
      // Tap the second action (確定); both buttons live inside the dialog.
      await tester.tap(find.text('削除').last);
      await tester.pumpAndSettle();

      expect(store.clearCount, 1);
      expect(store.loadAll(), isEmpty);
      expect(
        find.byKey(const Key('broadcast-history-cleared-snackbar')),
        findsOne,
      );
      expect(find.byKey(const Key('broadcast-history-empty-title')), findsOne);
    });

    testWidgets('clear-all cancellation does not delete entries', (
      WidgetTester tester,
    ) async {
      final _FakeStore store = _FakeStore(<BroadcastHistoryEntry>[
        _entry('lv1'),
      ]);
      await tester.pumpWidget(
        MaterialApp(home: BroadcastHistoryScreen(store: store)),
      );

      await tester.tap(
        find.byKey(const Key('broadcast-history-clear-all-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(store.clearCount, 0);
      expect(store.loadAll(), hasLength(1));
    });
  });
}
