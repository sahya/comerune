import '../utils/begin_at_parser.dart';
import '../../domain/utils/nico_icon_url.dart';
import 'follow_program.dart';

/// Shared parsing helpers for niconico program API responses.
///
/// Both [FollowProgramRepository] and [MyProgramRepository] parse the same
/// `programProvider` / `supplier` JSON structures. These helpers avoid
/// duplicating the extraction logic so that future API changes only need
/// a single update.

/// Extracts the broadcaster display name from a program JSON item.
///
/// Checks `programProvider.name` first, then falls back to `supplier.name`.
String? extractProviderName(Map<String, dynamic> item) {
  final Object? provider = item['programProvider'];
  if (provider is Map<String, dynamic>) {
    final Object? name = provider['name'];
    if (name is String && name.isNotEmpty) {
      return name;
    }
  }

  final Object? supplier = item['supplier'];
  if (supplier is Map<String, dynamic>) {
    final Object? name = supplier['name'];
    if (name is String && name.isNotEmpty) {
      return name;
    }
  }

  return null;
}

/// Extracts the broadcaster icon URL from a program JSON item.
///
/// Priority:
/// 1) provider/supplier explicit icon fields
/// 2) direct icon fields (`iconUrl` / `providerIconUrl`)
/// 3) numeric provider IDs -> generated niconico user icon URL fallback
/// Only returns HTTPS URLs.
String? extractProviderIconUrl(Map<String, dynamic> item) {
  final Object? provider = item['programProvider'];
  if (provider is Map<String, dynamic>) {
    final Object? iconSmall = provider['iconSmall'];
    if (iconSmall is String && isHttpsUrl(iconSmall)) {
      return iconSmall;
    }
    final Object? icon = provider['icon'];
    if (icon is String && isHttpsUrl(icon)) {
      return icon;
    }
    final Object? icons = provider['icons'];
    if (icons is Map<String, dynamic>) {
      final Object? uri50 = icons['uri50x50'];
      if (uri50 is String && isHttpsUrl(uri50)) {
        return uri50;
      }
      final Object? uri150 = icons['uri150x150'];
      if (uri150 is String && isHttpsUrl(uri150)) {
        return uri150;
      }
    }
  }

  final Object? supplier = item['supplier'];
  if (supplier is Map<String, dynamic>) {
    final Object? icons = supplier['icons'];
    if (icons is Map<String, dynamic>) {
      final Object? uri50 = icons['uri50x50'];
      if (uri50 is String && isHttpsUrl(uri50)) {
        return uri50;
      }
      final Object? uri150 = icons['uri150x150'];
      if (uri150 is String && isHttpsUrl(uri150)) {
        return uri150;
      }
    }
  }

  // Keep direct icon fields ahead of ID-based generation.
  final String? iconUrl = _extractDirectIconUrl(item);
  if (iconUrl != null) {
    return iconUrl;
  }

  // Final fallback: synthesize niconico usericon URL from numeric provider IDs.
  final String? providerUserId = _extractProviderUserId(item);
  if (providerUserId != null) {
    return buildNicoIconUrl(providerUserId);
  }

  return null;
}

/// Extracts the community or channel name from a program JSON item.
String? extractCommunityName(Map<String, dynamic> item) {
  final Object? socialGroup = item['socialGroup'];
  if (socialGroup is Map<String, dynamic>) {
    final Object? name = socialGroup['name'];
    if (name is String && name.isNotEmpty) {
      return name;
    }
  }
  return null;
}

/// Returns `true` if [url] is a non-empty HTTPS URL.
bool isHttpsUrl(String url) {
  return url.isNotEmpty && url.startsWith('https://');
}

String? _extractDirectIconUrl(Map<String, dynamic> item) {
  final Object? topLevelIcon = item['iconUrl'];
  if (topLevelIcon is String && isHttpsUrl(topLevelIcon)) {
    return topLevelIcon;
  }

  final Object? topLevelProviderIcon = item['providerIconUrl'];
  if (topLevelProviderIcon is String && isHttpsUrl(topLevelProviderIcon)) {
    return topLevelProviderIcon;
  }

  final Object? provider = item['programProvider'];
  if (provider is Map<String, dynamic>) {
    final Object? providerIconUrl = provider['iconUrl'];
    if (providerIconUrl is String && isHttpsUrl(providerIconUrl)) {
      return providerIconUrl;
    }
  }

  final Object? supplier = item['supplier'];
  if (supplier is Map<String, dynamic>) {
    final Object? supplierIconUrl = supplier['iconUrl'];
    if (supplierIconUrl is String && isHttpsUrl(supplierIconUrl)) {
      return supplierIconUrl;
    }
  }

  return null;
}

String? _extractProviderUserId(Map<String, dynamic> item) {
  final Object? provider = item['programProvider'];
  if (provider is Map<String, dynamic>) {
    final String? userId = _asNumericUserId(provider['programProviderId']);
    if (userId != null) {
      return userId;
    }
    final String? providerId = _asNumericUserId(provider['id']);
    if (providerId != null) {
      return providerId;
    }
  }

  final Object? supplier = item['supplier'];
  if (supplier is Map<String, dynamic>) {
    final String? userId = _asNumericUserId(supplier['programProviderId']);
    if (userId != null) {
      return userId;
    }
    final String? supplierId = _asNumericUserId(supplier['id']);
    if (supplierId != null) {
      return supplierId;
    }
  }

  final String? directId = _asNumericUserId(item['programProviderId']);
  if (directId != null) {
    return directId;
  }

  return _asNumericUserId(item['supplierUserId']);
}

String? _asNumericUserId(Object? value) {
  if (value is int && value > 0) {
    return value.toString();
  }
  if (value is String && value.isNotEmpty) {
    final int? parsed = int.tryParse(value);
    if (parsed != null && parsed > 0) {
      return parsed.toString();
    }
  }
  return null;
}

/// Parses a single program JSON item into a [FollowProgram].
///
/// Returns `null` if required fields (`id`, `title`) are missing.
/// When [requireProviderName] is `true` (default), items without a
/// provider name are also skipped (matching follow-list behavior).
FollowProgram? parseProgramItem(
  Map<String, dynamic> item, {
  bool requireProviderName = true,
  bool isOwnBroadcast = false,
}) {
  final String? programId = item['id'] as String?;
  final String? title = item['title'] as String?;
  if (programId == null || title == null) {
    return null;
  }

  final String? providerName = extractProviderName(item);
  if (requireProviderName && providerName == null) {
    return null;
  }

  final String? providerIconUrl = extractProviderIconUrl(item);
  final String? communityName = extractCommunityName(item);
  final DateTime? beginAt = parseBeginAt(item);

  return FollowProgram(
    programId: programId,
    title: title,
    providerName: providerName ?? '',
    providerIconUrl: providerIconUrl,
    communityName: communityName,
    beginAt: beginAt,
    isOwnBroadcast: isOwnBroadcast,
  );
}
