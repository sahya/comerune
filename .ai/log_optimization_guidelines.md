# Debug Log Optimization Guidelines

## Overview

Release builds must avoid unnecessary CPU cost from debug logging.
The `app_logging.dart` module provides two functions:

- `appDebugLog(String message)` -- evaluates the string argument on every call,
  even when logging is disabled in release builds.
- `appDebugLogLazy(String Function() messageBuilder)` -- defers string
  construction; the lambda is only called when `kAppDebugLogEnabled` is true.

## Rules

### 1. Use `appDebugLogLazy` for interpolated messages

When a log message contains string interpolation (`$variable` or
`${expression}`), always use the lazy variant so the interpolation is skipped in
release builds:

```dart
// Bad -- string is built even in release
appDebugLog('[Repo] fetched count=${items.length}');

// Good -- lambda is not invoked in release
appDebugLogLazy(() => '[Repo] fetched count=${items.length}');
```

### 2. Plain literals may use `appDebugLog`

Static string literals without interpolation have negligible cost and may use
the direct function:

```dart
appDebugLog('[Repo] fallback path entered');
```

### 3. Hot-path logging

Code that runs on every poll cycle, every frame callback, or inside loops
should use `appDebugLogLazy` regardless of interpolation, to avoid even the
function-call overhead in release builds when the guard short-circuits.

### 4. Wrapper functions

Files that use a local `_debugLog` / `_debugLogLazy` wrapper must follow the
same rules. The wrapper should delegate to `appDebugLogLazy` when its callers
pass interpolated strings.

### 5. Sensitive data

Never log raw session tokens, user IDs, or credentials. Mask or omit values
that could identify a user (see `_maskUserIdForLog` in
`favorite_user_live_checker.dart` for the established pattern).

### 6. Cache operation labels

Repository-level caches that suppress redundant network requests should include
a structured label in their log messages to simplify logcat filtering:

- `cache=Hit` -- cached result returned, network skipped
- `cache=Miss` -- no cached result, network request issued
- `cache=Expire` -- cached result expired, network request issued

Example:

```dart
appDebugLogLazy(
  () => '[MyProgramRepository] tool-fallback cache=Hit '
      '(age=${elapsed.inSeconds}s, ttl=${ttl.inSeconds}s)',
);
```

## Enforcement

The `test/logging/debug_log_policy_test.dart` file contains regression tests
that verify high-frequency files do not use `appDebugLog` with interpolated
strings. When adding a new data-layer file with debug logging, consider adding
it to the test target list.
