import 'package:comerune/application/filter/broadcaster_ng_export_codec.dart';
import 'package:comerune/data/filter/broadcaster_ng_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_shared_preferences.dart';

/// Issue #727: codec-level edge cases for
/// [BroadcasterNgExportCodec.applyExportBlock].
///
/// Settings-level coverage lives in
/// `test/application/settings/settings_store_export_import_test.dart`;
/// this file targets behaviour that is most naturally asserted at the
/// codec boundary (oversized keys, etc.).
void main() {
  group('applyExportBlock — oversized broadcasterId', () {
    test('drops broadcaster keys longer than the codec limit', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final BroadcasterNgStore ngStore = SharedPreferencesBroadcasterNgStore(
        prefs: prefs,
      );
      final BroadcasterNgExportCodec codec = BroadcasterNgExportCodec(
        store: ngStore,
      );

      final String oversized = 'x' * 300;
      const String validId = 'b1';

      await codec.applyExportBlock(<String, dynamic>{
        'version': 1,
        'template': <String, dynamic>{
          'ngUserIds': <String>[],
          'ngWordRules': <Map<String, dynamic>>[],
        },
        'broadcasters': <String, dynamic>{
          oversized: <String, dynamic>{
            'ngUserIds': <String>['leaked'],
            'ngWordRules': <Map<String, dynamic>>[],
          },
          validId: <String, dynamic>{
            'ngUserIds': <String>['kept'],
            'ngWordRules': <Map<String, dynamic>>[],
          },
        },
      });
      await ngStore.flushPendingWrites();

      final List<String> known = ngStore.listBroadcasters();
      expect(known, contains(validId));
      expect(
        known.any((String id) => id.length > 256),
        isFalse,
        reason: 'Oversized broadcaster IDs must be skipped during import.',
      );
      expect(known, isNot(contains(oversized)));

      final BroadcasterNgPayload kept = await ngStore
          .loadBroadcasterNgAttributes(validId);
      expect(kept.ngUserIds, <String>{'kept'});
    });
  });
}
