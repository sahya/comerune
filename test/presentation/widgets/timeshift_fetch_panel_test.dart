import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/timeshift_fetch/timeshift_fetch_controller.dart';
import 'package:comerune/presentation/widgets/timeshift_fetch_panel.dart';

void main() {
  group('TimeshiftFetchPanel', () {
    testWidgets('shows nothing when idle', (WidgetTester tester) async {
      final _FakeController controller = _FakeController(
        status: TimeshiftFetchStatus.idle,
      );

      await tester.pumpWidget(_wrap(controller));

      expect(find.byType(TimeshiftFetchPanel), findsOneWidget);
      expect(find.text('500件取得'), findsNothing);
      expect(find.text('取得中...'), findsNothing);
    });

    testWidgets('shows fetch buttons when paused with hasMore', (
      WidgetTester tester,
    ) async {
      final _FakeController controller = _FakeController(
        status: TimeshiftFetchStatus.paused,
        hasMore: true,
        totalFetched: 5000,
      );

      await tester.pumpWidget(_wrap(controller));

      expect(find.text('500件取得'), findsOneWidget);
      expect(find.text('1000件取得'), findsOneWidget);
      expect(find.text('全件取得'), findsOneWidget);
      expect(find.text('取得済み: 5000件'), findsOneWidget);
    });

    testWidgets('shows progress indicator and cancel when fetching', (
      WidgetTester tester,
    ) async {
      final _FakeController controller = _FakeController(
        status: TimeshiftFetchStatus.fetching,
        totalFetched: 2000,
      );

      await tester.pumpWidget(_wrap(controller));

      expect(find.text('取得中...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);
      expect(find.text('500件取得'), findsNothing);
    });

    testWidgets('shows completed status', (WidgetTester tester) async {
      final _FakeController controller = _FakeController(
        status: TimeshiftFetchStatus.completed,
        totalFetched: 10000,
      );

      await tester.pumpWidget(_wrap(controller));

      expect(find.text('取得完了'), findsOneWidget);
      expect(find.text('500件取得'), findsNothing);
    });

    testWidgets('shows retry button on error', (WidgetTester tester) async {
      final _FakeController controller = _FakeController(
        status: TimeshiftFetchStatus.error,
      );

      await tester.pumpWidget(_wrap(controller));

      expect(find.text('取得に失敗しました'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('fetch button callbacks are invoked', (
      WidgetTester tester,
    ) async {
      bool fetch500Called = false;
      bool fetch1000Called = false;
      bool fetchAllCalled = false;

      final _FakeController controller = _FakeController(
        status: TimeshiftFetchStatus.paused,
        hasMore: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeshiftFetchPanel(
              controller: controller,
              onFetch500: () => fetch500Called = true,
              onFetch1000: () => fetch1000Called = true,
              onFetchAll: () => fetchAllCalled = true,
              onCancel: () {},
              onRetry: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('500件取得'));
      expect(fetch500Called, isTrue);

      await tester.tap(find.text('1000件取得'));
      expect(fetch1000Called, isTrue);

      await tester.tap(find.text('全件取得'));
      expect(fetchAllCalled, isTrue);
    });

    testWidgets('cancel callback is invoked', (WidgetTester tester) async {
      bool cancelCalled = false;

      final _FakeController controller = _FakeController(
        status: TimeshiftFetchStatus.fetching,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeshiftFetchPanel(
              controller: controller,
              onFetch500: () {},
              onFetch1000: () {},
              onFetchAll: () {},
              onCancel: () => cancelCalled = true,
              onRetry: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('キャンセル'));
      expect(cancelCalled, isTrue);
    });

    testWidgets('retry callback is invoked', (WidgetTester tester) async {
      bool retryCalled = false;

      final _FakeController controller = _FakeController(
        status: TimeshiftFetchStatus.error,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeshiftFetchPanel(
              controller: controller,
              onFetch500: () {},
              onFetch1000: () {},
              onFetchAll: () {},
              onCancel: () {},
              onRetry: () => retryCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('再試行'));
      expect(retryCalled, isTrue);
    });
  });
}

Widget _wrap(_FakeController controller) {
  return MaterialApp(
    home: Scaffold(
      body: TimeshiftFetchPanel(
        controller: controller,
        onFetch500: () {},
        onFetch1000: () {},
        onFetchAll: () {},
        onCancel: () {},
        onRetry: () {},
      ),
    ),
  );
}

class _FakeController extends ChangeNotifier
    implements TimeshiftFetchController {
  _FakeController({
    TimeshiftFetchStatus status = TimeshiftFetchStatus.idle,
    bool hasMore = false,
    int totalFetched = 0,
    bool isFetchingAll = false,
  }) : _status = status,
       _hasMore = hasMore,
       _totalFetched = totalFetched,
       _isFetchingAll = isFetchingAll;

  TimeshiftFetchStatus _status;
  final bool _hasMore;
  final int _totalFetched;
  final bool _isFetchingAll;

  @override
  TimeshiftFetchStatus get status => _status;

  @override
  bool get hasMore => _hasMore;

  @override
  int get totalFetched => _totalFetched;

  @override
  bool get isFetchingAll => _isFetchingAll;

  @override
  Object? get lastError => null;

  @override
  Future<void> fetchInitial(Uri viewApiUri) async {}

  @override
  Future<void> fetchMore(int count) async {}

  @override
  Future<void> fetchAll() async {}

  @override
  Future<void> cancel() async {}

  @override
  void reset() {
    _status = TimeshiftFetchStatus.idle;
    notifyListeners();
  }
}
