import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comerune/data/user/file_user_attribute_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;
  late FileUserAttributeStore store;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('user_attr_store_test_');
    store = FileUserAttributeStore(
      root: Directory(p.join(tempRoot.path, 'user_attributes')),
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('FileUserAttributeStore — basic CRUD', () {
    test('setColor then loadColors returns the saved color', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      final Map<String, int> colors = await store.loadColors('b1');
      expect(colors['u1'], 0xFFE53935);
    });

    test('setNickname then loadNicknames returns the saved nickname', () async {
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u1',
        nickname: 'テスト',
      );
      final Map<String, String> nicknames = await store.loadNicknames('b1');
      expect(nicknames['u1'], 'テスト');
    });

    test('color and nickname coexist for the same user', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u1',
        nickname: 'テスト',
      );

      expect(
        (await store.loadColors('b1'))['u1'],
        0xFFE53935,
        reason: 'Color must not be clobbered by nickname set',
      );
      expect((await store.loadNicknames('b1'))['u1'], 'テスト');
    });

    test('removeColor leaves nickname intact', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u1',
        nickname: 'テスト',
      );
      await store.removeColor(broadcasterId: 'b1', userId: 'u1');

      expect((await store.loadColors('b1'))['u1'], isNull);
      expect((await store.loadNicknames('b1'))['u1'], 'テスト');
    });

    test('removeNickname leaves color intact', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u1',
        nickname: 'テスト',
      );
      await store.removeNickname(broadcasterId: 'b1', userId: 'u1');

      expect((await store.loadColors('b1'))['u1'], 0xFFE53935);
      expect((await store.loadNicknames('b1'))['u1'], isNull);
    });

    test('loadColors for unknown broadcaster returns empty map', () async {
      expect(await store.loadColors('unknown'), isEmpty);
    });

    test('removeColor on missing entry is a no-op', () async {
      await store.removeColor(broadcasterId: 'b1', userId: 'missing');
      expect(await store.loadColors('b1'), isEmpty);
    });
  });

  group('FileUserAttributeStore — scoping by broadcaster', () {
    test('different broadcasters have independent data', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      await store.setColor(
        broadcasterId: 'b2',
        userId: 'u1',
        colorValue: 0xFF1E88E5,
      );

      expect((await store.loadColors('b1'))['u1'], 0xFFE53935);
      expect((await store.loadColors('b2'))['u1'], 0xFF1E88E5);
    });
  });

  group('FileUserAttributeStore — durability', () {
    test(
      'data persists across store instances (simulating app restart)',
      () async {
        await store.setColor(
          broadcasterId: 'b1',
          userId: 'u1',
          colorValue: 0xFFE53935,
        );
        await store.setNickname(
          broadcasterId: 'b1',
          userId: 'u2',
          nickname: 'テスト',
        );

        // Simulate app restart by creating a new store pointing at the
        // same directory.
        final FileUserAttributeStore restarted = FileUserAttributeStore(
          root: Directory(p.join(tempRoot.path, 'user_attributes')),
        );

        expect(
          (await restarted.loadColors('b1'))['u1'],
          0xFFE53935,
          reason: 'Color must survive restart',
        );
        expect(
          (await restarted.loadNicknames('b1'))['u2'],
          'テスト',
          reason: 'Nickname must survive restart',
        );
      },
    );
  });

  group('FileUserAttributeStore — concurrency (serialised writes)', () {
    test(
      'rapid concurrent setColor calls all persist without lost updates',
      () async {
        // Simulates the `unawaited` pattern: fire many writes at once.
        await Future.wait(<Future<void>>[
          for (int i = 0; i < 20; i++)
            store.setColor(
              broadcasterId: 'b1',
              userId: 'u$i',
              colorValue: 0xFF000000 + i,
            ),
        ]);

        final Map<String, int> colors = await store.loadColors('b1');
        for (int i = 0; i < 20; i++) {
          expect(
            colors['u$i'],
            0xFF000000 + i,
            reason: 'Entry u$i must survive concurrent writes',
          );
        }
      },
    );

    test(
      'interleaved setColor + setNickname for same user both persist',
      () async {
        await Future.wait(<Future<void>>[
          store.setColor(
            broadcasterId: 'b1',
            userId: 'u1',
            colorValue: 0xFFE53935,
          ),
          store.setNickname(broadcasterId: 'b1', userId: 'u1', nickname: 'テスト'),
        ]);

        expect((await store.loadColors('b1'))['u1'], 0xFFE53935);
        expect((await store.loadNicknames('b1'))['u1'], 'テスト');
      },
    );
  });

  group('FileUserAttributeStore — cleanup', () {
    test('removes entries older than maxAge and keeps recent ones', () async {
      await store.setColor(
        broadcasterId: 'b-old',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      await store.setColor(
        broadcasterId: 'b-new',
        userId: 'u1',
        colorValue: 0xFF1E88E5,
      );

      // Age the b-old entry by rewriting its file with an old timestamp.
      final File oldFile = File(
        p.join(tempRoot.path, 'user_attributes', 'b-old.json'),
      );
      final Map<String, dynamic> rawOld =
          json.decode(await oldFile.readAsString()) as Map<String, dynamic>;
      rawOld['_lastUsedAt'] = DateTime.now()
          .subtract(const Duration(days: 400))
          .millisecondsSinceEpoch;
      await oldFile.writeAsString(json.encode(rawOld), flush: true);

      final int removed = await store.cleanup();
      expect(removed, 1);
      expect(await oldFile.exists(), isFalse);
      expect((await store.loadColors('b-new'))['u1'], 0xFF1E88E5);
    });
  });

  group('FileUserAttributeStore — legacy JSON compatibility', () {
    test('reads legacy color-only (plain int) entries', () async {
      final Directory root = Directory(p.join(tempRoot.path, 'user_attributes'))
        ..createSync(recursive: true);
      File(
        p.join(root.path, 'b1.json'),
      ).writeAsStringSync('{"u1": 4293212469, "_lastUsedAt": 1}');

      final Map<String, int> colors = await store.loadColors('b1');
      expect(colors['u1'], 4293212469);
      expect(await store.loadNicknames('b1'), isEmpty);
    });

    test('reads nickname-only entries', () async {
      final Directory root = Directory(p.join(tempRoot.path, 'user_attributes'))
        ..createSync(recursive: true);
      File(
        p.join(root.path, 'b1.json'),
      ).writeAsStringSync('{"u1": {"n": "のみ"}, "_lastUsedAt": 1}');

      expect(await store.loadColors('b1'), isEmpty);
      expect((await store.loadNicknames('b1'))['u1'], 'のみ');
    });

    test('reads combined color + nickname entries', () async {
      final Directory root = Directory(p.join(tempRoot.path, 'user_attributes'))
        ..createSync(recursive: true);
      File(p.join(root.path, 'b1.json')).writeAsStringSync(
        '{"u1": {"c": 4293212469, "n": "両方"}, "_lastUsedAt": 1}',
      );

      expect((await store.loadColors('b1'))['u1'], 4293212469);
      expect((await store.loadNicknames('b1'))['u1'], '両方');
    });

    test('corrupt JSON file falls back to empty maps', () async {
      final Directory root = Directory(p.join(tempRoot.path, 'user_attributes'))
        ..createSync(recursive: true);
      File(p.join(root.path, 'b1.json')).writeAsStringSync('{not json');

      expect(await store.loadColors('b1'), isEmpty);
      expect(await store.loadNicknames('b1'), isEmpty);
    });
  });

  group('FileUserAttributeStore — importRawJson', () {
    test('imports legacy payload verbatim', () async {
      await store.importRawJson(
        'b1',
        '{"u1": 4293212469, "u2": {"n": "コテ"}, "_lastUsedAt": 1}',
      );

      expect((await store.loadColors('b1'))['u1'], 4293212469);
      expect((await store.loadNicknames('b1'))['u2'], 'コテ');
    });

    test('ignores non-object JSON', () async {
      await store.importRawJson('b1', '[1, 2, 3]');
      expect(await store.loadColors('b1'), isEmpty);
    });
  });

  group('FileUserAttributeStore — filesystem safety', () {
    test(
      'sanitises broadcasterId with illegal filesystem characters',
      () async {
        // Broadcaster IDs that would otherwise escape the root directory.
        await store.setColor(
          broadcasterId: '../../../escape',
          userId: 'u1',
          colorValue: 0xFFE53935,
        );

        // Verify no file was written outside the root.
        final Directory root = Directory(
          p.join(tempRoot.path, 'user_attributes'),
        );
        expect(await root.exists(), isTrue);
        final List<FileSystemEntity> entries = root.listSync();
        for (final FileSystemEntity entry in entries) {
          expect(
            p.isWithin(root.path, entry.path),
            isTrue,
            reason: 'File must stay within the root: ${entry.path}',
          );
        }

        // And the data is still retrievable via the same (sanitised) ID.
        expect((await store.loadColors('../../../escape'))['u1'], 0xFFE53935);
      },
    );
  });

  group('FileUserAttributeStore — flushPendingWrites', () {
    test(
      'flushPendingWrites waits for all unawaited writes to complete',
      () async {
        // Fire several writes without awaiting.
        final Future<void> f1 = store.setColor(
          broadcasterId: 'b1',
          userId: 'u1',
          colorValue: 0xFFE53935,
        );
        final Future<void> f2 = store.setNickname(
          broadcasterId: 'b1',
          userId: 'u2',
          nickname: 'フラッシュ',
        );
        final Future<void> f3 = store.setColor(
          broadcasterId: 'b2',
          userId: 'u1',
          colorValue: 0xFF1E88E5,
        );

        // Flush should wait for all three to complete.
        await store.flushPendingWrites();

        // Verify all data was persisted.
        expect((await store.loadColors('b1'))['u1'], 0xFFE53935);
        expect((await store.loadNicknames('b1'))['u2'], 'フラッシュ');
        expect((await store.loadColors('b2'))['u1'], 0xFF1E88E5);

        // Ensure the individual futures also completed without error.
        await f1;
        await f2;
        await f3;
      },
    );

    test('flushPendingWrites is a no-op when nothing is pending', () async {
      await store.flushPendingWrites();
    });
  });

  group('FileUserAttributeStore — loadAttributes', () {
    test('returns colors and nicknames combined in a single call', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u2',
        nickname: 'たろう',
      );
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u3',
        colorValue: 0xFF1E88E5,
      );
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u3',
        nickname: 'じろう',
      );

      final ({Map<String, int> colors, Map<String, String> nicknames}) result =
          await store.loadAttributes('b1');

      expect(result.colors, <String, int>{'u1': 0xFFE53935, 'u3': 0xFF1E88E5});
      expect(result.nicknames, <String, String>{'u2': 'たろう', 'u3': 'じろう'});
    });

    test('result is equivalent to loadColors + loadNicknames', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u2',
        nickname: 'テスト',
      );

      final Map<String, int> viaLoadColors = await store.loadColors('b1');
      final Map<String, String> viaLoadNicknames = await store.loadNicknames(
        'b1',
      );
      final ({Map<String, int> colors, Map<String, String> nicknames})
      viaLoadAttributes = await store.loadAttributes('b1');

      expect(viaLoadAttributes.colors, viaLoadColors);
      expect(viaLoadAttributes.nicknames, viaLoadNicknames);
    });

    test('returns empty maps for unknown broadcaster', () async {
      final ({Map<String, int> colors, Map<String, String> nicknames}) result =
          await store.loadAttributes('unknown');

      expect(result.colors, isEmpty);
      expect(result.nicknames, isEmpty);
    });

    test('updates _lastUsedAt exactly once (single I/O round-trip)', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );

      final File file = File(
        p.join(tempRoot.path, 'user_attributes', 'b1.json'),
      );
      // Push the timestamp into the past so any touch should clearly
      // overwrite it (and we can detect a missed update).
      final Map<String, dynamic> raw =
          json.decode(await file.readAsString()) as Map<String, dynamic>;
      raw['_lastUsedAt'] = 1;
      await file.writeAsString(json.encode(raw), flush: true);

      await store.loadAttributes('b1');

      final Map<String, dynamic> after =
          json.decode(await file.readAsString()) as Map<String, dynamic>;
      expect(
        after['_lastUsedAt'] is int && (after['_lastUsedAt'] as int) > 1,
        isTrue,
        reason: '_lastUsedAt must be touched by loadAttributes',
      );
    });

    test(
      'does not write when broadcaster has no data (no _lastUsedAt created)',
      () async {
        await store.loadAttributes('never_seen');

        final File file = File(
          p.join(tempRoot.path, 'user_attributes', 'never_seen.json'),
        );
        expect(
          await file.exists(),
          isFalse,
          reason: 'loadAttributes on empty broadcaster must not create file',
        );
      },
    );

    test('writes the broadcaster file at most once per loadAttributes call '
        '(regression: prevent loadColors+loadNicknames double I/O)', () async {
      // Pre-seed the file via a normal write so the broadcaster JSON
      // exists on disk before we start watching.
      await store.setColor(
        broadcasterId: 'b-watch',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );

      final File file = File(
        p.join(tempRoot.path, 'user_attributes', 'b-watch.json'),
      );

      // Watch the broadcaster file and capture distinct, non-empty
      // content snapshots.  Each writeAsString produces a transient
      // empty state plus the final content; counting distinct
      // non-empty contents tells us how many logical writes happened.
      // _writeRaw stamps a fresh DateTime.now() into _lastUsedAt on
      // every call, so two back-to-back writes produce two distinct
      // contents (assuming millisecond clock advances; we add a small
      // pre-call delay after seeding to maximise that distinction).
      final Set<String> snapshots = <String>{};
      final List<FileSystemEvent> events = <FileSystemEvent>[];
      final StreamSubscription<FileSystemEvent> sub = file
          .watch(events: FileSystemEvent.modify)
          .listen((FileSystemEvent event) {
            events.add(event);
            try {
              snapshots.add(file.readAsStringSync());
            } on Object {
              // Ignore transient read errors during write.
            }
          });
      // Let the watcher attach.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      // Ensure any new write definitely uses a different millisecond
      // value than the seed write above so distinct contents show up
      // even if loadAttributes only calls _writeRaw once.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await store.loadAttributes('b-watch');

      // Allow any pending file events to drain.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await sub.cancel();

      final Set<String> nonEmpty = snapshots
          .where((String s) => s.isNotEmpty)
          .toSet();

      expect(
        nonEmpty,
        hasLength(1),
        reason:
            'loadAttributes must call _writeRaw exactly once. '
            'Observing more than one distinct non-empty file content '
            'indicates the legacy double-touch behaviour has regressed. '
            'events=${events.length} snapshots=$snapshots',
      );
    });

    test('reads legacy color-only entries', () async {
      final Directory root = Directory(p.join(tempRoot.path, 'user_attributes'))
        ..createSync(recursive: true);
      File(p.join(root.path, 'b1.json')).writeAsStringSync(
        '{"u1": 4293212469, "u2": {"n": "のみ"}, "_lastUsedAt": 1}',
      );

      final ({Map<String, int> colors, Map<String, String> nicknames}) result =
          await store.loadAttributes('b1');

      expect(result.colors, <String, int>{'u1': 4293212469});
      expect(result.nicknames, <String, String>{'u2': 'のみ'});
    });
  });

  group('FileUserAttributeStore — index lock', () {
    test('concurrent writes to different broadcasters '
        'produce a correct index', () async {
      await Future.wait(<Future<void>>[
        store.setColor(broadcasterId: 'a', userId: 'u1', colorValue: 1),
        store.setColor(broadcasterId: 'b', userId: 'u1', colorValue: 2),
        store.setColor(broadcasterId: 'c', userId: 'u1', colorValue: 3),
      ]);

      // All three broadcasters must be in the index — no lost updates.
      expect((await store.loadColors('a'))['u1'], 1);
      expect((await store.loadColors('b'))['u1'], 2);
      expect((await store.loadColors('c'))['u1'], 3);

      // Verify the index file itself is consistent.
      final File indexFile = File(
        p.join(tempRoot.path, 'user_attributes', '_index.json'),
      );
      final List<dynamic> index =
          json.decode(await indexFile.readAsString()) as List<dynamic>;
      expect(index, containsAll(<String>['a', 'b', 'c']));
    });
  });
}
