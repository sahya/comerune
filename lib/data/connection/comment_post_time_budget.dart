import '../../domain/connection/session_ws_client.dart';
import 'watch_page_web_socket_url_resolver.dart';

/// Upper bounds for each step of posting a comment over a freshly opened
/// comment-only session WebSocket (Issue #1029).
///
/// The comment-post path is bounded step by step instead of being wrapped
/// in one outer `Future.timeout`: an outer timeout would report a failure
/// to the user while the inner steps keep running, and the comment could
/// still be sent afterwards. Keep [stepsTotal] within [total] whenever a
/// step value changes (enforced by a unit test).
abstract final class CommentPostTimeBudget {
  /// Disposing the previous (possibly half-open) client.
  static const Duration disposePrevious = Duration(seconds: 2);

  /// Fetching the watch page to resolve the authenticated WebSocket URL.
  static const Duration watchPageFetch =
      WatchPageWebSocketUrlResolver.defaultFetchTimeout;

  /// Opening the WebSocket.
  static const Duration connect = SessionWsClient.defaultConnectTimeout;

  /// Waiting for `postCommentResult`.
  static const Duration response = SessionWsClient.defaultPostCommentTimeout;

  /// The longest a single post may take before it returns to the caller.
  static const Duration total = Duration(seconds: 30);

  /// Sum of the step bounds above.
  static Duration get stepsTotal =>
      disposePrevious + watchPageFetch + connect + response;
}
