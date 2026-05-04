/// Rendering order for an extension UI slot that may contain both
/// host-provided and extension-provided widgets.
enum SlotInsertOrder {
  /// Render host widgets first, then append extension widgets. Default
  /// for slots where host UI defines the primary affordances and the
  /// extension augments them.
  hostFirst,

  /// Render extension widgets first, then host widgets. Used when an
  /// extension wants to surface a primary action above existing host UI.
  extensionFirst,

  /// Only render host widgets. Extension widgets registered for this
  /// slot are ignored.
  hostOnly,

  /// Only render extension widgets. Host-provided children passed to the
  /// slot are ignored.
  extensionOnly,
}
