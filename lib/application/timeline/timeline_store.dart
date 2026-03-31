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

  int get capacity => _capacity;

  UnmodifiableListView<AppMessage> get messages =>
      UnmodifiableListView<AppMessage>(_messages);

  void add(AppMessage message) {
    if (_knownIds.contains(message.id)) {
      return;
    }

    _insertSorted(message);
    _knownIds.add(message.id);
    _trimOverflow();
    notifyListeners();
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
    notifyListeners();
  }

  void clear() {
    if (_messages.isEmpty) {
      return;
    }

    _messages.clear();
    _knownIds.clear();
    notifyListeners();
  }

  void setCapacity(int value) {
    final int next = _validateCapacity(value);
    if (_capacity == next) {
      return;
    }

    _capacity = next;
    _trimOverflow();
    notifyListeners();
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
