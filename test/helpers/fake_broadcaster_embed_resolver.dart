import 'dart:async';

import 'package:comerune/data/niconico/broadcaster_embed_resolver.dart';

/// In-memory test double for [BroadcasterEmbedResolver].
///
/// Stores a fixed mapping from `lv` → [BroadcasterEmbedInfo] and records
/// every `resolve` call so widget tests can assert on the call count.
/// Returns `null` for any lv that has not been registered, mirroring the
/// real resolver's "best-effort, never throws" contract.
///
/// Optionally each lv can be paired with a [Future] gate — the resolve
/// future stays pending until the gate completes, letting widget tests
/// exercise race-condition behaviour (e.g. lv switched mid-flight).
class FakeBroadcasterEmbedResolver implements BroadcasterEmbedResolver {
  FakeBroadcasterEmbedResolver({Map<String, BroadcasterEmbedInfo>? results})
    : _results = <String, BroadcasterEmbedInfo>{...?results};

  final Map<String, BroadcasterEmbedInfo> _results;
  final Map<String, Future<void>> _gates = <String, Future<void>>{};
  final List<String> resolvedLvs = <String>[];
  bool disposed = false;

  void setResult(String lv, BroadcasterEmbedInfo? info) {
    if (info == null) {
      _results.remove(lv);
    } else {
      _results[lv] = info;
    }
  }

  /// Holds the resolve future for [lv] until [gate] completes. Used by
  /// race-condition tests to keep an embed resolution pending while the
  /// user switches to a different lv.
  void setGate(String lv, Future<void> gate) {
    _gates[lv] = gate;
  }

  @override
  Future<BroadcasterEmbedInfo?> resolve(String lv) async {
    resolvedLvs.add(lv);
    final Future<void>? gate = _gates[lv];
    if (gate != null) {
      await gate;
    }
    return _results[lv];
  }

  @override
  void dispose() {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}
