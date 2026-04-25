import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/matchers/ng_matcher.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/screens/comment_screen_config.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// Widget integration tests for `_messagesForLog()` on [CommentScreen].
///
/// Accesses the private helper via the [CommentScreenTestAccess] interface
/// that `_CommentScreenState` implements in production code. The interface is
/// the single production-surface concession for these tests (see
/// `@visibleForTesting` on [CommentScreenTestAccess] in `comment_screen.dart`).
void main() {
  group('CommentScreen._messagesForLog', () {
    late WakelockPlusPlatformInterface previousWakelockPlatform;

    setUpAll(() async {
      // Prime the rootBundle cache for `preset_ng_words.json` once for the
      // whole suite. `_loadPresetNgWordsFromAsset()` inside the widget uses
      // the same cached Future, so subsequent calls resolve synchronously
      // even inside the fake-async zone used by [WidgetTester].
      await rootBundle.loadString(
        'android/app/src/main/assets/preset_ng_words.json',
      );
    });

    setUp(() {
      previousWakelockPlatform = wakelockPlusPlatformInstance;
      wakelockPlusPlatformInstance = _FakeWakelockPlusPlatform();
    });

    tearDown(() {
      wakelockPlusPlatformInstance = previousWakelockPlatform;
    });

    testWidgets('returns empty list when no messages are present', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: const <AppMessage>[]),
      );
      await _settlePresetLoad(tester);

      final List<AppMessage> log = _logFor(tester);

      expect(log, isEmpty);
    });

    testWidgets(
      'scenario 1: clean messages (no preset or user-NG hits) → all kept without tags',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _chat(id: 'chat-1', content: 'こんにちは', second: 1),
          _chat(id: 'chat-2', content: 'よろしく', second: 2),
          _chat(id: 'chat-3', content: '配信お疲れ様', second: 3),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            // Display toggles are irrelevant to `_messagesForLog` — it never
            // consults `NgDisplayPreferences`. We set all four `allow*` flags
            // to `true` only to make this explicit: even with the "most
            // permissive" UI configuration, clean content must round-trip
            // untagged.
            ngDisplayPreferences: const NgDisplayPreferences(
              allowViolence: true,
              allowSexual: true,
              allowDiscrimination: true,
              allowMinors: true,
            ),
          ),
        );
        await _settlePresetLoad(tester);

        final List<AppMessage> log = _logFor(tester);

        expect(log.map((AppMessage m) => m.id), <String>[
          'chat-1',
          'chat-2',
          'chat-3',
        ]);
        for (final AppMessage m in log) {
          expect(
            m.content,
            isNot(startsWith('[filtered:')),
            reason: 'clean content must not be tagged: ${m.content}',
          );
          expect(m.content, isNot(startsWith('[speech_blocked:')));
        }
      },
    );

    testWidgets(
      'scenario 2: preset violence hit with showViolentComment=false → tagged [filtered:violence]',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _chat(id: 'chat-clean', content: 'こんばんは', second: 1),
          _chat(id: 'chat-violent', content: '爆弾の話', second: 2),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            // Display toggle off — but _messagesForLog() ignores display prefs
            // and always tags preset matches for the log.
            ngDisplayPreferences: const NgDisplayPreferences(),
          ),
        );
        await _settlePresetLoad(tester);

        final List<AppMessage> log = _logFor(tester);

        expect(log, hasLength(2));
        expect(log[0].id, 'chat-clean');
        expect(log[0].content, 'こんばんは');
        expect(log[1].id, 'chat-violent');
        expect(log[1].content, '[filtered:violence] 爆弾の話');
      },
    );

    testWidgets(
      'scenario 3: preset violence hit with showViolentComment=true → still tagged [filtered:violence] (log always tags preset matches)',
      (WidgetTester tester) async {
        // The log-side helper deliberately does not consult
        // NgDisplayPreferences — the display toggles only affect list
        // rendering. This test locks that contract in so a refactor that
        // accidentally suppresses the tag when the toggle is on is caught.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _chat(id: 'chat-violent', content: '爆弾の話', second: 1),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            ngDisplayPreferences: const NgDisplayPreferences(
              allowViolence: true,
            ),
          ),
        );
        await _settlePresetLoad(tester);

        final List<AppMessage> log = _logFor(tester);

        expect(log, hasLength(1));
        expect(log[0].content, '[filtered:violence] 爆弾の話');
        // Regression guard: the `speech_blocked` reason is reserved for a
        // future wiring (see CommentLogTag.reasonSpeechBlocked). The current
        // helper must not emit it.
        expect(log[0].content, isNot(startsWith('[speech_blocked:')));
      },
    );

    testWidgets(
      'scenario 4: user-defined NG word hit → dropped from log (no tag, matches impl)',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _chat(id: 'chat-clean', content: 'おつかれさま', second: 1),
          _chat(id: 'chat-user-ng', content: 'ばなな食べたい', second: 2),
          _chat(id: 'chat-tail', content: 'じゃあね', second: 3),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            ngWords: const <String>['ばなな'],
          ),
        );
        await _settlePresetLoad(tester);

        final List<AppMessage> log = _logFor(tester);

        expect(log.map((AppMessage m) => m.id), <String>[
          'chat-clean',
          'chat-tail',
        ]);
        // User-NG matches are excluded entirely, not tagged.
        expect(
          log.any(
            (AppMessage m) =>
                m.content.startsWith('[filtered:') ||
                m.content.startsWith('[speech_blocked:'),
          ),
          isFalse,
        );
      },
    );

    testWidgets(
      'scenario 5: display-blocked and user-NG-blocked rows still emerge in timestamp ascending order',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        // Interleave clean rows, preset-blocked rows, and user-NG rows so
        // that the returned list must preserve input order (which is already
        // timestamp-ascending by construction of widget.messages).
        final List<AppMessage> messages = <AppMessage>[
          _chat(id: 'a-clean', content: 'あいさつ', second: 1),
          _chat(id: 'b-user-ng', content: 'ばなな大好き', second: 2),
          _chat(id: 'c-preset', content: '爆弾の話その2', second: 3),
          _chat(id: 'd-clean', content: 'ふつうのコメント', second: 4),
          _chat(id: 'e-preset', content: '児童ポルノ関連', second: 5),
          _chat(id: 'f-clean', content: 'しめのあいさつ', second: 6),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            ngWords: const <String>['ばなな'],
          ),
        );
        await _settlePresetLoad(tester);

        final List<AppMessage> log = _logFor(tester);

        // user-NG hits are dropped; preset hits are kept with a tag.
        expect(log.map((AppMessage m) => m.id), <String>[
          'a-clean',
          'c-preset',
          'd-clean',
          'e-preset',
          'f-clean',
        ]);

        // Timestamps must remain strictly ascending — the helper must not
        // reorder entries when emitting the merged view.
        for (int i = 1; i < log.length; i++) {
          expect(
            log[i].timestamp.isAfter(log[i - 1].timestamp),
            isTrue,
            reason:
                'expected ascending timestamps, got ${log[i - 1].timestamp} → ${log[i].timestamp}',
          );
        }

        // Spot-check the tag wire format on one of the preset hits.
        expect(
          log.firstWhere((AppMessage m) => m.id == 'c-preset').content,
          startsWith('[filtered:violence]'),
        );
        expect(
          log.firstWhere((AppMessage m) => m.id == 'e-preset').content,
          startsWith('[filtered:minors]'),
        );
      },
    );

    testWidgets(
      'scenario 6: gift and nicoad rows are always excluded from the log',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _chat(id: 'chat-1', content: 'よろしく', second: 1),
          AppMessage(
            id: 'gift-1',
            timestamp: _ts(second: 2),
            userId: 'u-2',
            content: 'ギフト送付',
            type: AppMessageType.gift,
          ),
          AppMessage(
            id: 'nicoad-1',
            timestamp: _ts(second: 3),
            userId: 'u-3',
            content: 'ニコニ広告',
            type: AppMessageType.nicoad,
          ),
          _chat(id: 'chat-2', content: 'ありがとう', second: 4),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );
        await _settlePresetLoad(tester);

        final List<AppMessage> log = _logFor(tester);

        expect(log.map((AppMessage m) => m.id), <String>['chat-1', 'chat-2']);
      },
    );

    testWidgets(
      'scenario 7: operator and system messages are kept in the log',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          AppMessage(
            id: 'op-1',
            timestamp: _ts(second: 1),
            userId: null,
            content: '運営アナウンス',
            type: AppMessageType.operator,
          ),
          AppMessage(
            id: 'sys-1',
            timestamp: _ts(second: 2),
            userId: null,
            content: '市場からのお知らせ',
            type: AppMessageType.system,
          ),
          _chat(id: 'chat-1', content: 'はーい', second: 3),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );
        await _settlePresetLoad(tester);

        final List<AppMessage> log = _logFor(tester);

        expect(log.map((AppMessage m) => m.id), <String>[
          'op-1',
          'sys-1',
          'chat-1',
        ]);
      },
    );

    testWidgets(
      'scenario 8: synthetic broadcast-ended system row is excluded from the log',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _chat(id: 'chat-1', content: 'こんにちは', second: 1),
          AppMessage(
            id: buildBroadcastEndedNotificationId(
              epochMilliseconds: 1700000000000,
              sequence: 0,
            ),
            timestamp: _ts(second: 2),
            userId: null,
            content: '配信が終了しました',
            type: AppMessageType.notification,
          ),
          _chat(id: 'chat-2', content: 'またね', second: 3),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );
        await _settlePresetLoad(tester);

        final List<AppMessage> log = _logFor(tester);

        expect(log.map((AppMessage m) => m.id), <String>['chat-1', 'chat-2']);
      },
    );

    testWidgets('scenario 9: NG user ids drop the user entirely (no tag)', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _chat(id: 'chat-1', content: 'おはよう', second: 1, userId: 'spammer'),
        _chat(id: 'chat-2', content: 'こんにちは', second: 2, userId: 'good-user'),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          ngUserIds: const <String>{'spammer'},
        ),
      );
      await _settlePresetLoad(tester);

      final List<AppMessage> log = _logFor(tester);

      expect(log.map((AppMessage m) => m.id), <String>['chat-2']);
    });

    testWidgets(
      'scenario 10: preset hit + user-NG hit on the same row → preset wins (tagged, not dropped)',
      (WidgetTester tester) async {
        // Locks the branch ordering in `_messagesForLog`: the preset NG match
        // is evaluated before `_containsNgWord`, so a row that matches BOTH a
        // preset category AND a user-defined NG word must still be kept with
        // a `[filtered:<subcategory>]` tag. A refactor that swaps the order
        // would silently drop these rows from the log.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _chat(id: 'chat-mixed', content: '爆弾とばなな', second: 1),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            // 'ばなな' is a user-NG; '爆弾' is a preset violence hit.
            ngWords: const <String>['ばなな'],
          ),
        );
        await _settlePresetLoad(tester);

        final List<AppMessage> log = _logFor(tester);

        expect(log, hasLength(1));
        expect(log[0].id, 'chat-mixed');
        expect(log[0].content, startsWith('[filtered:violence]'));
      },
    );

    testWidgets(
      'scenario 11: returned list is unmodifiable (defensive copy contract)',
      (WidgetTester tester) async {
        // `_messagesForLog()` wraps its output in `List.unmodifiable`. This
        // locks that contract so a refactor that returns the growable buffer
        // directly is caught — callers of the log path assume they can hold
        // a reference without worrying about mutation.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _chat(id: 'chat-1', content: 'こんにちは', second: 1),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );
        await _settlePresetLoad(tester);

        final List<AppMessage> log = _logFor(tester);

        expect(() => log.add(messages.first), throwsUnsupportedError);
        expect(() => log.removeAt(0), throwsUnsupportedError);
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Drains the `_loadPresetNgWordsFromAsset() -> setState()` chain triggered
/// by [CommentScreen.initState].
///
/// `preset_ng_words.json` is primed by [setUpAll], but even so
/// `rootBundle.loadString` resolves through a microtask that the fake-async
/// zone [WidgetTester] uses does not always flush via [pumpAndSettle] alone.
/// A zero-duration real-async gap plus a [WidgetTester.pump] inside
/// [WidgetTester.runAsync] reliably lets the awaited load land; the trailing
/// [pumpAndSettle] processes the resulting setState rebuild.
Future<void> _settlePresetLoad(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
    await tester.pump();
  });
  await tester.pumpAndSettle();
}

/// Reaches into the state via [CommentScreenTestAccess] and returns the
/// current `_messagesForLog()` output.
List<AppMessage> _logFor(WidgetTester tester) {
  final State<CommentScreen> state = tester.state<State<CommentScreen>>(
    find.byType(CommentScreen),
  );
  return (state as CommentScreenTestAccess).messagesForLogForTesting();
}

/// Fixed base timestamp used by [_ts] / [_chat]. Keeping a single base means
/// every test message has a deterministic, monotonically-spaced timestamp.
final DateTime _base = DateTime.utc(2026, 3, 22, 12, 0, 0);

DateTime _ts({required int second}) => _base.add(Duration(seconds: second));

AppMessage _chat({
  required String id,
  required String content,
  required int second,
  String? userId = 'user-1',
  String? userName,
}) {
  return AppMessage(
    id: id,
    timestamp: _ts(second: second),
    userId: userId,
    userName: userName,
    content: content,
    type: AppMessageType.chat,
  );
}

Widget _buildScreen({
  required ConnectionSupervisor supervisor,
  required List<AppMessage> messages,
  Set<String> ngUserIds = const <String>{},
  List<String> ngWords = const <String>[],
  NgDisplayPreferences ngDisplayPreferences = NgDisplayPreferences.defaults,
}) {
  return MaterialApp(
    home: CommentScreen(
      programInfo: const CommentProgramInfo(lv: 'lv123456789'),
      connectionSupervisor: supervisor,
      messages: messages,
      callbacks: CommentCallbacks(
        onStopAllConnections: () async {},
        onReconnectSameLv: () async {},
        onDifferentLvConnected: (_, _) async {},
      ),
      themeMode: AppThemeMode.light,
      contentFilter: ContentFilterConfig(
        ngUserIds: ngUserIds,
        ngWords: ngWords,
        // Empty so initState() triggers _loadPresetNgWordsFromAsset(). The
        // asset bundle declared in pubspec.yaml makes the real file
        // available to the test binding, which in turn populates the
        // structured `_effectivePresetCategories` list used by the log
        // tagging branch.
        presetNgWords: const <String>[],
        ngDisplayPreferences: ngDisplayPreferences,
      ),
    ),
  );
}

ConnectionSupervisor _buildStreamingSupervisor() {
  final ConnectionSupervisor supervisor = ConnectionSupervisor();
  expect(supervisor.startConnection(), isTrue);
  expect(supervisor.onSessionWsConnected(), isTrue);
  expect(supervisor.onNdgrEndpointResolved(), isTrue);
  return supervisor;
}

class _FakeWakelockPlusPlatform extends WakelockPlusPlatformInterface {
  bool _enabled = false;

  @override
  Future<bool> get enabled async => _enabled;

  @override
  Future<void> toggle({required bool enable}) async {
    _enabled = enable;
  }
}
