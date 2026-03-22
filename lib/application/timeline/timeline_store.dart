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
  final ListQueue<AppMessage> _messages = ListQueue<AppMessage>();
  final Set<String> _knownIds = <String>{};

  int get capacity => _capacity;

  UnmodifiableListView<AppMessage> get messages =>
      UnmodifiableListView<AppMessage>(_messages);

  void add(AppMessage message) {
    if (_knownIds.contains(message.id)) {
      return;
    }

    _messages.addLast(message);
    _knownIds.add(message.id);
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

  void _trimOverflow() {
    while (_messages.length > _capacity) {
      final AppMessage removed = _messages.removeFirst();
      _knownIds.remove(removed.id);
    }
  }
}
