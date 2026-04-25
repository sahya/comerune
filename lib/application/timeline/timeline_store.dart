import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../domain/models/app_message.dart';

class TimelineStore extends ChangeNotifier {
  TimelineStore({int capacity = 100}) : _capacity = _validateCapacity(capacity);

  static int _validateCapacity(int value) {
    if (value < 1) {
      throw ArgumentError.value(value, 'capacity', 'must be 1 or greater');
    }
    return value;
  }

  int _capacity;
  final List<AppMessage> _messages = <AppMessage>[];
  final Set<String> _knownIds = <String>{};

  /// Snapshot of [_messages] published to outside consumers via [messages].
  ///
  /// Re-built once per mutation that fires [notifyListeners] (Issue #709 /
  /// #670). Consumers cache this list across rebuilds to detect new
  /// arrivals via reference identity / tail diff; returning a live view
  /// of [_messages] would alias every snapshot to the same underlying
  /// list and silently break those checks.
  List<AppMessage> _publishedMessages = const <AppMessage>[];

  /// Cached unmodifiable view over [_publishedMessages]. Re-allocated
  /// only when [_publishSnapshot] runs, so two consecutive `messages`
  /// reads between mutations return the **same instance** — both for
  /// the inner snapshot and its outer view wrapper.
  UnmodifiableListView<AppMessage> _publishedView =
      UnmodifiableListView<AppMessage>(const <AppMessage>[]);

  int get capacity => _capacity;

  /// Snapshot of the timeline at the time of the last mutation. The
  /// returned view is cheap (O(1)) and stable across reads — the inner
  /// snapshot is published in [_publishSnapshot] just before
  /// [notifyListeners] fires, so two consecutive reads between
  /// mutations return the same instance.
  ///
  /// Snapshot semantics: subsequent calls to [add] / [addAll] / [clear]
  /// / [setCapacity] do NOT mutate previously returned lists; the new
  /// state is exposed only after the next [notifyListeners].
  UnmodifiableListView<AppMessage> get messages => _publishedView;

  void add(AppMessage message) {
    if (_knownIds.contains(message.id)) {
      return;
    }

    _insertSorted(message);
    _knownIds.add(message.id);
    _trimOverflow();
    _publishAndNotify();
  }

  void addAll(List<AppMessage> messages) {
    bool changed = false;

    for (final AppMessage message in messages) {
      if (_knownIds.contains(message.id)) {
        continue;
      }

      _insertSorted(message);
      _knownIds.add(message.id);
      changed = true;
    }

    if (!changed) {
      return;
    }

    _trimOverflow();
    _publishAndNotify();
  }

  void clear() {
    if (_messages.isEmpty) {
      return;
    }

    _messages.clear();
    _knownIds.clear();
    _publishAndNotify();
  }

  void setCapacity(int value) {
    final int next = _validateCapacity(value);
    if (_capacity == next) {
      return;
    }

    final int previousLength = _messages.length;
    _capacity = next;
    _trimOverflow();
    // setCapacity always notifies listeners (capacity itself is part of
    // observable state), but the timeline contents may be unchanged
    // (capacity grew, or the existing length was already <= the new
    // capacity). Re-publish the snapshot only when [_trimOverflow]
    // actually evicted entries — that way consumers that diff via
    // identity see a stable list reference across pure-capacity
    // changes, mirroring the no-op behaviour of duplicate add().
    if (_messages.length != previousLength) {
      _publishSnapshot();
    }
    notifyListeners();
  }

  /// Convenience helper: re-publishes the snapshot and fires
  /// [notifyListeners] in one step. Use this from every mutation path
  /// whose change to [_messages] should be both observable to identity
  /// diffs AND trigger a rebuild. Centralising the pair guards against
  /// future contributors adding a new mutation method (e.g. `removeBy`,
  /// `update`) and forgetting to call [_publishSnapshot] before
  /// [notifyListeners] — the resulting bug would silently re-introduce
  /// the aliasing trap that broke `_hasNewMessages` (Issue #670).
  ///
  /// `setCapacity` deliberately does NOT call this helper because it
  /// must notify even when the contents are unchanged.
  void _publishAndNotify() {
    _publishSnapshot();
    notifyListeners();
  }

  /// Re-publishes a fresh, immutable snapshot of [_messages] for outside
  /// consumers. Both the inner [_publishedMessages] list and the cached
  /// [_publishedView] wrapper are re-allocated together so that consumers
  /// caching the getter result see a consistent identity boundary.
  ///
  /// Cost: O(N) pointer copy of immutable [AppMessage] references. At
  /// the documented timeline cap (15,000) this is sub-millisecond on
  /// typical mobile hardware (covered by the
  /// `snapshot publish at cap stays well under one frame budget` test)
  /// and runs at most once per [notifyListeners] emission, which itself
  /// is gated by real state change.
  void _publishSnapshot() {
    _publishedMessages = List<AppMessage>.unmodifiable(_messages);
    _publishedView = UnmodifiableListView<AppMessage>(_publishedMessages);
  }

  /// Inserts [message] at the correct position to maintain ascending
  /// timestamp order. Searches from the end since most arrivals are
  /// newer than existing messages.
  void _insertSorted(AppMessage message) {
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (!message.timestamp.isBefore(_messages[i].timestamp)) {
        _messages.insert(i + 1, message);
        return;
      }
    }
    // message is older than all existing messages.
    _messages.insert(0, message);
  }

  void _trimOverflow() {
    while (_messages.length > _capacity) {
      final AppMessage removed = _messages.removeAt(0);
      _knownIds.remove(removed.id);
    }
  }
}
