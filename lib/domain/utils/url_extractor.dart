/// Utilities for finding and validating URLs that appear inside free-form
/// comment text.
///
/// These helpers are intentionally pure (no Flutter dependencies) so that the
/// URL detection and safety rules can be covered by fast unit tests without a
/// widget test harness.

/// Represents a single URL occurrence inside a larger piece of text.
///
/// [start] and [end] are offsets into the source string using the exclusive
/// end convention, so `text.substring(match.start, match.end) == match.url`.
class UrlMatch {
  const UrlMatch({required this.start, required this.end, required this.url});

  final int start;
  final int end;
  final String url;
}

// Trailing characters that are commonly adjacent to a URL in Japanese and
// English prose but should not be treated as part of the URL itself.
const String _trailingPunctuation = '.,;:!?)]}>」』】、。，．・…';

// Compiled once at load time so that `findUrls` does not pay the cost of
// building a fresh [RegExp] for every comment row rebuild in the chat list.
//
// The character class restricts the URL body to RFC 3986 reserved/unreserved
// characters so that trailing CJK text such as 「、次へ」 is never consumed
// into the match.
final RegExp _urlRegex = RegExp(
  r"https?://[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+",
  caseSensitive: false,
);

/// Finds all `http://` / `https://` URLs inside [text].
///
/// The function is conservative: it only recognises the two HTTP(S) schemes,
/// stops at whitespace, and trims trailing punctuation so that a URL followed
/// by a period or closing bracket is matched without the punctuation.
///
/// A closing parenthesis at the very end is preserved when the URL also
/// contains an opening parenthesis, so that Wikipedia-style URLs such as
/// `https://en.wikipedia.org/wiki/Example_(disambiguation)` are returned
/// intact.
List<UrlMatch> findUrls(String text) {
  if (text.isEmpty) {
    return const <UrlMatch>[];
  }

  final List<UrlMatch> matches = <UrlMatch>[];
  for (final RegExpMatch match in _urlRegex.allMatches(text)) {
    final int start = match.start;
    int end = match.end;
    while (end > start) {
      final String lastChar = text.substring(end - 1, end);
      if (lastChar == ')' && text.substring(start, end - 1).contains('(')) {
        break;
      }
      if (_trailingPunctuation.contains(lastChar)) {
        end -= 1;
        continue;
      }
      break;
    }
    if (end <= start) {
      continue;
    }
    final String url = text.substring(start, end);
    if (!isSafeHttpUrl(url)) {
      continue;
    }
    matches.add(UrlMatch(start: start, end: end, url: url));
  }
  return matches;
}

/// Returns `true` when [url] parses to an absolute `http` or `https` URL with
/// a non-empty host.
///
/// This is the single place where the app decides whether a string that looks
/// like a URL is safe enough to hand off to the OS browser. Any future scheme
/// allow-list changes should go here.
bool isSafeHttpUrl(String url) {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null) {
    return false;
  }
  if (!uri.hasScheme) {
    return false;
  }
  final String scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return false;
  }
  if (uri.host.isEmpty) {
    return false;
  }
  return true;
}
