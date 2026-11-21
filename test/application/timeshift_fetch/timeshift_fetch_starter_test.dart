import 'dart:async';

import 'package:comerune/application/timeshift_fetch/timeshift_fetch_controller.dart';
import 'package:comerune/application/timeshift_fetch/timeshift_fetch_starter.dart';
import 'package:comerune/data/connection/timeshift_view_uri_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what [TimeshiftFetchStarter] asked its collaborators to do.
class _Harness {
  _Harness({this.enabled = true});

  final bool enabled;
  String lv = 'lv1';
  TimeshiftFetchStatus status = TimeshiftFetchStatus.idle;
  final List<Uri> fetched = <Uri>[];
  final List<String> lookups = <String>[];
  int resets = 0;
  int unsupportedDialogs = 0;
  final List<TimeshiftViewUriFailure?> unavailableDialogs =
      <TimeshiftViewUriFailure?>[];
  Future<TimeshiftViewUriResult> Function(String lv) lookUp =
      (String lv) async =>
          TimeshiftViewUriResult.resolved(Uri.parse('https://example.com/$lv'));

  late final TimeshiftFetchStarter starter = TimeshiftFetchStarter(
    enabled: enabled,
    currentLv: () => lv,
    status: () => status,
    fetchInitial: (Uri uri) async {
      fetched.add(uri);
      status = TimeshiftFetchStatus.paused;
    },
    cancelAndReset: () async {
      resets += 1;
      status = TimeshiftFetchStatus.idle;
    },
    lookUpViewUri: (String lv) {
      lookups.add(lv);
      return lookUp(lv);
    },
    onUnsupported: () => unsupportedDialogs += 1,
    onUnavailable: unavailableDialogs.add,
  );
}

final Uri _programInfoViewUri = Uri.parse('https://example.com/programinfo');

void main() {
  group('TimeshiftFetchStarter', () {
    test('fetches with the program info view URI without a lookup', () async {
      final _Harness h = _Harness();

      await h.starter.onTimeshiftDetected(_programInfoViewUri);

      expect(h.fetched, <Uri>[_programInfoViewUri]);
      expect(h.lookups, isEmpty);
      expect(h.starter.acceptsMessages, isTrue);
    });

    test('looks up the view URI when program info had none (#654)', () async {
      final _Harness h = _Harness();

      await h.starter.onTimeshiftDetected(null);

      expect(h.lookups, <String>['lv1']);
      expect(h.fetched, <Uri>[Uri.parse('https://example.com/lv1')]);
    });

    test('reports the failure once through onUnavailable and does not '
        'fetch', () async {
      final _Harness h = _Harness()
        ..lookUp = (String lv) async => const TimeshiftViewUriResult.failed(
          TimeshiftViewUriFailure.notWatchable,
        );

      await h.starter.onTimeshiftDetected(null);

      expect(h.unavailableDialogs, <TimeshiftViewUriFailure?>[
        TimeshiftViewUriFailure.notWatchable,
      ]);
      expect(h.fetched, isEmpty);
    });

    test('reports a lookup that throws as an unavailable failure', () async {
      final _Harness h = _Harness()
        ..lookUp = (String lv) async => throw StateError('storage failed');

      await h.starter.onTimeshiftDetected(null);

      expect(h.unavailableDialogs, <TimeshiftViewUriFailure?>[null]);
      expect(h.fetched, isEmpty);
    });

    test('runs only one lookup at a time for the same program', () async {
      final Completer<TimeshiftViewUriResult> pending =
          Completer<TimeshiftViewUriResult>();
      final _Harness h = _Harness()..lookUp = (String lv) => pending.future;

      final Future<void> first = h.starter.onTimeshiftDetected(null);
      await h.starter.onTimeshiftDetected(null);
      pending.complete(
        TimeshiftViewUriResult.resolved(Uri.parse('https://example.com/a')),
      );
      await first;

      expect(h.lookups, hasLength(1));
      expect(h.fetched, hasLength(1));
    });

    test('drops a lookup result after the user switched programs', () async {
      final Completer<TimeshiftViewUriResult> pending =
          Completer<TimeshiftViewUriResult>();
      final _Harness h = _Harness()..lookUp = (String lv) => pending.future;
      await h.starter.onProgramChanged('lv1');

      final Future<void> detecting = h.starter.onTimeshiftDetected(null);
      h.lv = 'lv2';
      await h.starter.onProgramChanged('lv2');
      pending.complete(
        TimeshiftViewUriResult.resolved(Uri.parse('https://example.com/a')),
      );
      await detecting;

      expect(h.fetched, isEmpty);
      expect(h.unavailableDialogs, isEmpty);
    });

    test('resets the fetch state only when the program changes', () async {
      final _Harness h = _Harness();
      await h.starter.onProgramChanged('lv1');
      await h.starter.onTimeshiftDetected(_programInfoViewUri);
      expect(h.status, TimeshiftFetchStatus.paused);

      // Reconnecting to the same program keeps the fetched state.
      await h.starter.onProgramChanged('lv1');
      expect(h.resets, 1);
      expect(h.status, TimeshiftFetchStatus.paused);

      // A different program starts from idle and can fetch again.
      h.lv = 'lv2';
      await h.starter.onProgramChanged('lv2');
      expect(h.resets, 2);
      expect(h.starter.acceptsMessages, isFalse);
      await h.starter.onTimeshiftDetected(_programInfoViewUri);
      expect(h.fetched, hasLength(2));
    });

    test('drops messages of a program the user has left', () async {
      final _Harness h = _Harness();
      await h.starter.onTimeshiftDetected(_programInfoViewUri);
      expect(h.starter.acceptsMessages, isTrue);

      h.lv = 'lv2';

      expect(h.starter.acceptsMessages, isFalse);
    });

    test('skips silently when live comments were received for the program '
        '(#1017)', () async {
      final _Harness h = _Harness();
      await h.starter.onProgramChanged('lv1');
      h.starter.markLiveCommentsReceived();

      await h.starter.onTimeshiftDetected(null);

      expect(h.lookups, isEmpty);
      expect(h.fetched, isEmpty);
      expect(h.unavailableDialogs, isEmpty);
    });

    test('skips while a fetch is already running or done', () async {
      final _Harness h = _Harness()..status = TimeshiftFetchStatus.completed;

      await h.starter.onTimeshiftDetected(null);

      expect(h.lookups, isEmpty);
      expect(h.fetched, isEmpty);
    });

    test(
      'shows the unsupported notice instead of fetching when disabled',
      () async {
        final _Harness h = _Harness(enabled: false);

        await h.starter.onTimeshiftDetected(_programInfoViewUri);

        expect(h.unsupportedDialogs, 1);
        expect(h.fetched, isEmpty);
        expect(h.lookups, isEmpty);
      },
    );
  });
}
