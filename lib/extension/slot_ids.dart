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
  /// - **Registered widgets must be `PopupMenuEntry<Object>`**
  ///   (typically `PopupMenuItem<Object>`). Dart's invariant
  ///   generics mean `PopupMenuItem<int>`, `PopupMenuItem<MyEnum>`,
  ///   `PopupMenuItem<void>` etc. compile fine on the extension
  ///   side but will be silently dropped at slot-composition time
  ///   because they are not subtypes of `PopupMenuEntry<Object>`.
  ///   Use `Object` as the type parameter and any value type for
  ///   the `value:` field; the host's runtime type guard isolates
  ///   its own dispatch from extension values.
  /// - Each entry's `onTap` (or other interaction handling) is the
  ///   extension's responsibility — the host does not invoke any
  ///   callback for non-host menu values.
  /// - The host hides this slot entirely when the user is not the
  ///   broadcaster, regardless of registered widgets.
  static const SlotId broadcasterScreenActions = SlotId._(
    'broadcaster.screen.actions',
  );
}
