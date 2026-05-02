import 'dart:developer' as developer;

import '../../data/filter/broadcaster_ng_store.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/ng_word_rule.dart';
import 'broadcaster_id_redaction.dart';
import 'legacy_ng_parser.dart';

/// Issue #727: serializes the per-broadcaster + template NG layout to and
/// from the export JSON's `broadcasterNgFilter` block.
///
/// Extracted from `SharedPreferencesSettingsStore` so the settings store
/// is not also responsible for the export schema. Keeps the schema
/// version, key name, and parsing rules co-located with the codec.
///
/// Forward-compat policy (see [schemaVersion]): newer-than-app schemas
/// are applied best-effort — known fields (`template`, `broadcasters`)
/// are read; unknown sibling fields under the block are ignored without
/// warning. Importers must NOT abort on `version > schemaVersion`.
class BroadcasterNgExportCodec {
  const BroadcasterNgExportCodec({required this.store});

  /// Backing store the codec reads from / writes through.
  final BroadcasterNgStore store;

  /// Top-level export key carrying the per-broadcaster NG layout.
  ///
  /// Documented as a public constant so tests and the importer can
  /// detect "new schema present" without re-declaring the literal.
  static const String exportKey = 'broadcasterNgFilter';

  /// Schema version for [exportKey]. Bumped only when the JSON shape
  /// changes incompatibly.
  ///
  /// Forward-compat policy: newer-than-app schemas are applied
  /// best-effort. Known fields (`template`, `broadcasters`) are read;
  /// unknown sibling fields under the block are ignored without
  /// warning. Importers MUST NOT abort on `version > schemaVersion` —
  /// dropping the user's NG state silently is worse than tolerating an
  /// unrecognized version. Only bump this when an existing field's
  /// shape changes incompatibly, and add explicit handling for the new
  /// version when you do.
  static const int schemaVersion = 1;

  /// Maximum allowed length of a `broadcasterId` key under
  /// `broadcasters`. Keys longer than this are dropped during import as
  /// a defense against oversized / malicious JSON payloads. Real
  /// broadcaster IDs are short numeric strings, so 256 is well above
  /// the legitimate range.
  static const int _maxBroadcasterIdLength = 256;

  /// Builds the `broadcasterNgFilter` block from the current
  /// [BroadcasterNgStore] snapshot.
  ///
  /// Failures while reading individual broadcaster slots are logged and
  /// the offending slot is skipped — a single malformed slot must not
  /// abort the whole export.
  Future<Map<String, dynamic>> buildExportBlock() async {
    final Set<String> templateIds = await store.loadTemplateNgUserIds();
    final List<NgWordRule> templateRules = await store
        .loadTemplateNgWordRules();

    final Map<String, dynamic> broadcasters = <String, dynamic>{};
    for (final String id in store.listBroadcasters()) {
      if (id.isEmpty) {
        continue;
      }
      try {
        final BroadcasterNgPayload payload = await store
            .loadBroadcasterNgAttributes(id);
        broadcasters[id] = <String, dynamic>{
          'ngUserIds': payload.ngUserIds.toList(),
          'ngWordRules': payload.rules
              .map((NgWordRule r) => r.toMap())
              .toList(),
        };
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to read NG slot for export; skipping broadcaster '
          '${redactBroadcasterId(id)}: $error',
          name: 'BroadcasterNgExportCodec',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    return <String, dynamic>{
      'version': schemaVersion,
      'template': <String, dynamic>{
        'ngUserIds': templateIds.toList(),
        'ngWordRules': templateRules.map((NgWordRule r) => r.toMap()).toList(),
      },
      'broadcasters': broadcasters,
    };
  }

  /// Applies the parsed `broadcasterNgFilter` block to [store].
  ///
  /// Skips malformed inner sections (logged) instead of throwing — a
  /// single bad slot must not abort the whole import. Per the
  /// forward-compat policy on [schemaVersion], higher versions are
  /// tolerated and unknown sibling keys are silently ignored.
  Future<void> applyExportBlock(Map<String, dynamic> block) async {
    // Forward-compat: tolerate any version. Known fields below are
    // read; unknown siblings are ignored without warning.
    // (We intentionally do NOT abort on `version > schemaVersion`.)

    // Template.
    final Object? rawTemplate = block['template'];
    if (rawTemplate is Map<String, dynamic>) {
      final Set<String> templateIds = _parseNgUserIdsList(
        rawTemplate['ngUserIds'],
      );
      final List<NgWordRule> templateRules = _parseNgWordRulesList(
        rawTemplate['ngWordRules'],
      );
      try {
        await store.saveTemplateNgUserIds(templateIds);
        await store.saveTemplateNgWordRules(templateRules);
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to apply imported NG template: $error',
          name: 'BroadcasterNgExportCodec',
          error: error,
          stackTrace: stackTrace,
        );
      }
    } else if (rawTemplate != null) {
      developer.log(
        'broadcasterNgFilter.template is not a Map; skipping template.',
        name: 'BroadcasterNgExportCodec',
      );
    }

    // Broadcasters.
    int applied = 0;
    final Object? rawBroadcasters = block['broadcasters'];
    if (rawBroadcasters is Map<String, dynamic>) {
      for (final MapEntry<String, dynamic> entry in rawBroadcasters.entries) {
        final String broadcasterId = entry.key;
        if (broadcasterId.isEmpty) {
          developer.log(
            'Skipping empty broadcasterId key in broadcasterNgFilter.',
            name: 'BroadcasterNgExportCodec',
          );
          continue;
        }
        if (broadcasterId.length > _maxBroadcasterIdLength) {
          developer.log(
            'Skipping oversized broadcasterId key '
            '(${broadcasterId.length} chars > $_maxBroadcasterIdLength).',
            name: 'BroadcasterNgExportCodec',
          );
          continue;
        }
        final Object? slot = entry.value;
        if (slot is! Map) {
          developer.log(
            'broadcasterNgFilter.broadcasters['
            '${redactBroadcasterId(broadcasterId)}] is not a Map; skipping.',
            name: 'BroadcasterNgExportCodec',
          );
          continue;
        }
        final Map<String, dynamic> typed = slot.cast<String, dynamic>();
        final Set<String> ids = _parseNgUserIdsList(typed['ngUserIds']);
        final List<NgWordRule> rules = _parseNgWordRulesList(
          typed['ngWordRules'],
        );
        try {
          await store.saveNgUserIds(broadcasterId, ids);
          await store.saveNgWordRules(broadcasterId, rules);
          applied++;
        } on Object catch (error, stackTrace) {
          developer.log(
            'Failed to apply imported NG slot for broadcaster '
            '${redactBroadcasterId(broadcasterId)}: $error',
            name: 'BroadcasterNgExportCodec',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    } else if (rawBroadcasters != null) {
      developer.log(
        'broadcasterNgFilter.broadcasters is not a Map; skipping all '
        'per-broadcaster slots.',
        name: 'BroadcasterNgExportCodec',
      );
    }
    developer.log(
      'Imported broadcasterNgFilter: $applied broadcaster slot(s) applied.',
      name: 'BroadcasterNgExportCodec',
    );
  }

  /// Legacy fallback: when the import JSON has no `broadcasterNgFilter`
  /// block, treat the legacy global NG fields as the user's prior
  /// state. Seeds the template AND every already-known broadcaster
  /// slot with the legacy values so "import = restore my old NG
  /// settings everywhere" matches the user's mental model.
  ///
  /// Broadcasters that are not yet in the store's index are NOT created
  /// — this matches the migrator's "known broadcasters only" rule.
  Future<void> applyLegacyFallback(AppSettings imported) async {
    final Set<String> legacyIds = imported.ngUserIdSet;
    final List<NgWordRule> legacyRules = LegacyNgParser.mergeLegacyNgWordRules(
      structuredRules: imported.ngWordRules,
      legacyNgWords: imported.ngWords,
    );

    try {
      await store.saveTemplateNgUserIds(legacyIds);
      await store.saveTemplateNgWordRules(legacyRules);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Legacy import: failed to seed NG template: $error',
        name: 'BroadcasterNgExportCodec',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }

    int reseeded = 0;
    for (final String broadcasterId in store.listBroadcasters()) {
      if (broadcasterId.isEmpty) {
        continue;
      }
      try {
        await store.saveNgUserIds(broadcasterId, legacyIds);
        await store.saveNgWordRules(broadcasterId, legacyRules);
        reseeded++;
      } on Object catch (error, stackTrace) {
        developer.log(
          'Legacy import: failed to reseed broadcaster '
          '${redactBroadcasterId(broadcasterId)}: $error',
          name: 'BroadcasterNgExportCodec',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    developer.log(
      'Legacy NG import: $reseeded broadcaster slot(s) reseeded from legacy '
      'fields.',
      name: 'BroadcasterNgExportCodec',
    );
  }

  static Set<String> _parseNgUserIdsList(Object? raw) {
    if (raw is! List) {
      return <String>{};
    }
    final Set<String> ids = <String>{};
    for (final Object? item in raw) {
      if (item is String) {
        final String trimmed = item.trim();
        if (trimmed.isNotEmpty) {
          ids.add(trimmed);
        }
      }
    }
    return ids;
  }

  static List<NgWordRule> _parseNgWordRulesList(Object? raw) {
    if (raw is! List) {
      return <NgWordRule>[];
    }
    final List<NgWordRule> rules = <NgWordRule>[];
    final Set<String> seen = <String>{};
    for (final Object? item in raw) {
      if (item is! Map) {
        continue;
      }
      try {
        final NgWordRule rule = NgWordRule.fromMap(
          item.cast<String, dynamic>(),
        );
        if (rule.pattern.isEmpty) {
          continue;
        }
        if (seen.add(rule.pattern)) {
          rules.add(rule);
        }
      } on Object catch (error) {
        developer.log(
          'Skipped malformed ngWordRules entry during import: $error',
          name: 'BroadcasterNgExportCodec',
        );
      }
    }
    return rules;
  }
}
