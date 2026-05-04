/// Type-safe identifier for an extension UI slot.
///
/// External code cannot construct arbitrary [SlotId] values: the only
/// constructor is private and the canonical instances live in [SlotIds].
/// This prevents typos at registration sites and makes the catalogue of
/// slots explicit.
final class SlotId {
  const SlotId._(this.value);

  /// Stable string identifier. Used for diagnostics and as the key in
  /// the registry's slot-widget map. Not intended to be parsed by
  /// external code.
  final String value;

  @override
  bool operator ==(Object other) => other is SlotId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'SlotId($value)';
}

/// Catalogue of UI slots that the host exposes for extension widgets.
///
/// Each slot has a documented contract describing where it renders and
/// what widget types are accepted. The contract for each slot must stay
/// stable once published (extensions in forks rely on it).
abstract final class SlotIds {
  /// Broadcaster-only AppBar menu actions on the live comment screen.
  ///
  /// Contract:
  /// - Renders inside the AppBar `PopupMenuButton` shown while the
  ///   logged-in user is the broadcaster of the program.
  /// - Registered widgets must be `PopupMenuEntry` instances.
  /// - The host hides this slot entirely when the user is not the
  ///   broadcaster, regardless of registered widgets.
  static const SlotId broadcasterScreenActions = SlotId._(
    'broadcaster.screen.actions',
  );
}
