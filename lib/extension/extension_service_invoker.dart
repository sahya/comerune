import 'package:flutter/foundation.dart';

import '../app_logging.dart';
import 'extension_registry.dart';
import 'extension_result.dart';
import 'service_override_policy.dart';

/// Resolves a service contract registration against the host's
/// fallback implementation, applying a [ServiceOverridePolicy] and
/// catching every exception that crosses the extension boundary.
///
/// Generic parameters:
/// - `S` — the service contract type stored in the registry. Must
///   extend `Object` because the registry rejects nullable services
///   (a missing service is signalled by the look-up returning `null`).
/// - `R` — the return type produced by both the extension call and the
///   host fallback. The result is wrapped in an [ExtensionResult] so
///   call sites can pattern-match on success / unsupported / failure
///   without try/catch noise.
///
/// Defensive guarantees:
/// - Extension `callExtension` exceptions become
///   [ExtensionResultFailure]; the host is never crashed by a
///   misbehaving integration.
/// - Host `hostFallback` exceptions are **not** caught — they are real
///   bugs in host code and should surface so they can be fixed.
/// - When the registry is empty (no extension registered) or the
///   policy disables the extension path, the host fallback runs as
///   normal Dart code.
class ExtensionServiceInvoker {
  const ExtensionServiceInvoker._();

  /// Invoke a service contract.
  ///
  /// Both [callExtension] and [hostFallback] return
  /// `Future<ExtensionResult<R>>`, allowing each side to signal
  /// "unsupported" without exceptions:
  /// - Return [ExtensionResultOk] with the produced value.
  /// - Return [ExtensionResultUnsupported] when the path cannot
  ///   service the request (capability not implemented for this
  ///   input, no host implementation, etc.).
  /// - Throwing from [callExtension] is caught and reported as
  ///   [ExtensionResultFailure]; throwing from [hostFallback]
  ///   propagates to the caller (host bugs must surface).
  ///
  /// [policy] selects which side runs first; see
  /// [ServiceOverridePolicy] for the four supported strategies. The
  /// default is [ServiceOverridePolicy.extensionFirstFallback], the
  /// canonical choice for capabilities the host can only partially
  /// provide.
  static Future<ExtensionResult<R>> invoke<S extends Object, R>(
    ExtensionRegistry registry, {
    required Future<ExtensionResult<R>> Function(S) callExtension,
    Future<ExtensionResult<R>> Function()? hostFallback,
    ServiceOverridePolicy policy = ServiceOverridePolicy.extensionFirstFallback,
  }) async {
    final S? extension = registry.service<S>();

    switch (policy) {
      case ServiceOverridePolicy.hostOnly:
        return _runHost<R>(hostFallback);

      case ServiceOverridePolicy.hostFirstFallback:
        final ExtensionResult<R> hostResult = await _runHost<R>(hostFallback);
        if (hostResult is! ExtensionResultUnsupported<R>) {
          return hostResult;
        }
        if (extension == null) {
          return ExtensionResultUnsupported<R>();
        }
        return _runExtension<S, R>(extension, callExtension);

      case ServiceOverridePolicy.extensionFirstFallback:
        if (extension != null) {
          final ExtensionResult<R> extResult = await _runExtension<S, R>(
            extension,
            callExtension,
          );
          if (extResult is ExtensionResultOk<R>) {
            return extResult;
          }
          // Unsupported / failure — fall through to host.
        }
        return _runHost<R>(hostFallback);

      case ServiceOverridePolicy.extensionOnly:
        if (extension == null) {
          return ExtensionResultUnsupported<R>();
        }
        return _runExtension<S, R>(extension, callExtension);
    }
  }

  static Future<ExtensionResult<R>> _runHost<R>(
    Future<ExtensionResult<R>> Function()? hostFallback,
  ) async {
    if (hostFallback == null) {
      return ExtensionResultUnsupported<R>();
    }
    // Intentionally NOT wrapped in try/catch: host bugs should
    // surface so they can be fixed. Caller code that needs to
    // tolerate host failures must wrap them itself.
    return hostFallback();
  }

  static Future<ExtensionResult<R>> _runExtension<S extends Object, R>(
    S extension,
    Future<ExtensionResult<R>> Function(S) callExtension,
  ) async {
    try {
      return await callExtension(extension);
    } catch (error, stackTrace) {
      _logFailure(error, stackTrace);
      return ExtensionResultFailure<R>(error);
    }
  }

  // Logger name in debug includes the subsystem for greppability;
  // release builds emit only the generic 'comerune' name so that
  // platform logs (logcat / Console) do not advertise the existence
  // of an optional-integration subsystem.
  static const String _logName = kDebugMode ? 'comerune.extension' : 'comerune';

  static void _logFailure(Object error, StackTrace stackTrace) {
    appErrorLog(
      name: _logName,
      message: 'optional integration call failed',
      error: kDebugMode ? error : null,
      stackTrace: kDebugMode ? stackTrace : null,
    );
  }
}
