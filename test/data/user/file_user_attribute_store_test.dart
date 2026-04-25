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

  group('FileUserAttributeStore — atomic write tmp orphan handling', () {
    test(
      'cleanup removes orphan tmp files left by a crashed process',
      () async {
        // Seed real data so the directory exists and cleanup runs end-to-end.
        await store.setColor(
          broadcasterId: 'b1',
          userId: 'u1',
          colorValue: 0xFFE53935,
        );

        final Directory root = Directory(
          p.join(tempRoot.path, 'user_attributes'),
        );
        // Simulate a different (crashed) process by using pid + 1 in the name.
        final int otherPid = pid + 1;
        final File orphanData = File(
          p.join(
            root.path,
            'b1.json${FileUserAttributeStore.tmpInfix}'
            '$otherPid.111111.0',
          ),
        );
        final File orphanIndex = File(
          p.join(
            root.path,
            '_index.json${FileUserAttributeStore.tmpInfix}'
            '$otherPid.222222.0',
          ),
        );
        await orphanData.writeAsString('garbage', flush: true);
        await orphanIndex.writeAsString('garbage', flush: true);

        final int removed = await store.cleanup();
        expect(removed, 0, reason: 'No expired entries to remove');
        expect(
          await orphanData.exists(),
          isFalse,
          reason: 'Orphan data tmp must be swept by cleanup',
        );
        expect(
          await orphanIndex.exists(),
          isFalse,
          reason: 'Orphan index tmp must be swept by cleanup',
        );

        // Real data must still be intact.
        expect((await store.loadColors('b1'))['u1'], 0xFFE53935);
      },
    );

    test('orphan tmp files do not pollute _readIndex / load methods', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );

      final Directory root = Directory(
        p.join(tempRoot.path, 'user_attributes'),
      );
      final int otherPid = pid + 1;
      final File orphanIndex = File(
        p.join(
          root.path,
          '_index.json${FileUserAttributeStore.tmpInfix}'
          '$otherPid.222222.0',
        ),
      );
      await orphanIndex.writeAsString('garbage', flush: true);

      // Load methods read from the canonical files only — tmp must be ignored.
      expect((await store.loadColors('b1'))['u1'], 0xFFE53935);

      final File indexFile = File(p.join(root.path, '_index.json'));
      final List<dynamic> index =
          json.decode(await indexFile.readAsString()) as List<dynamic>;
      expect(index, contains('b1'));
      // Orphan must not have been promoted to the canonical index.
      expect(await orphanIndex.exists(), isTrue);
    });

    test('cleanup leaves this process\'s in-flight tmp files alone', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );

      final Directory root = Directory(
        p.join(tempRoot.path, 'user_attributes'),
      );
      // A tmp file embedding the current pid simulates a still-running
      // _atomicWriteString from this process. cleanup must not delete it,
      // otherwise an in-flight rename would race against the sweep.
      final File ownTmp = File(
        p.join(
          root.path,
          'b1.json${FileUserAttributeStore.tmpInfix}'
          '$pid.999999.0',
        ),
      );
      await ownTmp.writeAsString('in-flight', flush: true);

      await store.cleanup();
      expect(
        await ownTmp.exists(),
        isTrue,
        reason: 'Own-pid tmp file must NOT be swept by cleanup',
      );
    });

    test(
      'rename-based atomic write produces readable persisted data',
      () async {
        // Force several writes through the atomic path and verify that the
        // resulting canonical files are well-formed JSON readable by a fresh
        // store instance (proves rename completed successfully).
        for (int i = 0; i < 10; i++) {
          await store.setColor(
            broadcasterId: 'b1',
            userId: 'u$i',
            colorValue: 0xFF000000 + i,
          );
        }

        final FileUserAttributeStore restarted = FileUserAttributeStore(
          root: Directory(p.join(tempRoot.path, 'user_attributes')),
        );
        final Map<String, int> colors = await restarted.loadColors('b1');
        for (int i = 0; i < 10; i++) {
          expect(colors['u$i'], 0xFF000000 + i);
        }

        // No tmp leftovers after a clean run.
        final Directory root = Directory(
          p.join(tempRoot.path, 'user_attributes'),
        );
        final List<FileSystemEntity> entries = root.listSync();
        for (final FileSystemEntity entry in entries) {
          expect(
            entry.path.contains(FileUserAttributeStore.tmpInfix),
            isFalse,
            reason: 'No tmp residue should remain after successful writes',
          );
        }
      },
    );
  });

  group('FileUserAttributeStore — broadcaster ID vs tmp infix collision', () {
    // Regression for a data-corruption bug: a previous version of
    // _sweepTmpOrphans matched any filename containing the (then) ".tmp."
    // infix and treated whatever followed as a pid. A broadcaster ID like
    // "foo.tmp.999" produced "foo.tmp.999.json", which was then misread
    // as a tmp-file from pid 999 and silently deleted.
    //
    // The fix is twofold:
    //   1. Rename the infix to ".atomic-tmp." so it cannot appear in the
    //      sanitised broadcaster ID character set in practice.
    //   2. Tighten the sweep parser to only accept exactly three
    //      dot-separated all-digit tokens after the infix.
    //
    // These tests guard both halves.

    test(
      'broadcaster ID containing the tmp infix and digits is preserved',
      () async {
        // Use the public infix constant so the test stays in sync with
        // any future rename of the infix.
        final String collidingId = 'foo${FileUserAttributeStore.tmpInfix}999';

        await store.setColor(
          broadcasterId: collidingId,
          userId: 'u1',
          colorValue: 0xFFE53935,
        );

        final File f = File(
          p.join(tempRoot.path, 'user_attributes', '$collidingId.json'),
        );
        expect(
          await f.exists(),
          isTrue,
          reason: 'Sanity: setColor must produce a backing file',
        );

        // cleanup must not classify this as a tmp orphan and delete it.
        await store.cleanup();

        expect(
          await f.exists(),
          isTrue,
          reason: 'Broadcaster file must survive cleanup',
        );
        expect((await store.loadColors(collidingId))['u1'], 0xFFE53935);
      },
    );

    test(
      'broadcaster ID matching the full tmp suffix shape is preserved',
      () async {
        // Pathological ID that exactly mimics <pid>.<micros>.<counter>
        // after the infix. The strict suffix parser must still refuse to
        // sweep it — the backing file's full suffix is the tail of
        // "<id>.json", which has the trailing ".json" and so cannot match
        // the all-digit shape.
        final String collidingId =
            'foo${FileUserAttributeStore.tmpInfix}999.111.0';

        await store.setColor(
          broadcasterId: collidingId,
          userId: 'u1',
          colorValue: 0xFF1E88E5,
        );

        final File f = File(
          p.join(tempRoot.path, 'user_attributes', '$collidingId.json'),
        );
        expect(await f.exists(), isTrue);

        await store.cleanup();

        expect(
          await f.exists(),
          isTrue,
          reason: 'Boundary-shaped broadcaster file must survive cleanup',
        );
        expect((await store.loadColors(collidingId))['u1'], 0xFF1E88E5);
      },
    );

    test(
      'broadcaster ID that starts with the tmp infix is preserved',
      () async {
        // The ID begins with the full infix (leading dot included). The
        // on-disk file becomes "<infix>1.2.3.json"; the suffix after the
        // first infix occurrence is "1.2.3.json" — four dot-separated
        // tokens with a non-digit ".json" tail, so the strict parser
        // refuses to classify it as a tmp orphan.
        final String collidingId = '${FileUserAttributeStore.tmpInfix}1.2.3';

        await store.setColor(
          broadcasterId: collidingId,
          userId: 'u1',
          colorValue: 0xFFAA00AA,
        );

        final File f = File(
          p.join(tempRoot.path, 'user_attributes', '$collidingId.json'),
        );
        expect(await f.exists(), isTrue);

        await store.cleanup();

        expect(
          await f.exists(),
          isTrue,
          reason: 'Leading-infix broadcaster file must survive cleanup',
        );
        expect((await store.loadColors(collidingId))['u1'], 0xFFAA00AA);
      },
    );
  });

  group('FileUserAttributeStore — cleanup vs concurrent setColor', () {
    test(
      'concurrent setColor during cleanup keeps file and index consistent',
      () async {
        // Seed two stale entries so cleanup wants to remove both.
        await store.setColor(
          broadcasterId: 'b-old-1',
          userId: 'u1',
          colorValue: 0xFFE53935,
        );
        await store.setColor(
          broadcasterId: 'b-old-2',
          userId: 'u1',
          colorValue: 0xFF1E88E5,
        );

        final Directory root = Directory(
          p.join(tempRoot.path, 'user_attributes'),
        );
        final int oldTimestamp = DateTime.now()
            .subtract(const Duration(days: 400))
            .millisecondsSinceEpoch;
        for (final String id in <String>['b-old-1', 'b-old-2']) {
          final File f = File(p.join(root.path, '$id.json'));
          final Map<String, dynamic> raw =
              json.decode(await f.readAsString()) as Map<String, dynamic>;
          raw['_lastUsedAt'] = oldTimestamp;
          await f.writeAsString(json.encode(raw), flush: true);
        }

        // Race cleanup against a setColor that revives one stale broadcaster
        // and a setColor for a brand-new broadcaster added during cleanup.
        await Future.wait(<Future<void>>[
          store.cleanup(),
          store.setColor(
            broadcasterId: 'b-old-1',
            userId: 'u1',
            colorValue: 0xFFAA0000,
          ),
          store.setColor(
            broadcasterId: 'b-new',
            userId: 'u1',
            colorValue: 0xFF00AA00,
          ),
        ]);

        // b-new must persist regardless of cleanup ordering.
        expect(
          (await store.loadColors('b-new'))['u1'],
          0xFF00AA00,
          reason: 'b-new must persist across the race',
        );

        // After settling, every indexed broadcaster must have a file and
        // every broadcaster file must be in the index. No lost updates and
        // no dangling index entries.
        final File indexFile = File(p.join(root.path, '_index.json'));
        expect(await indexFile.exists(), isTrue);
        final List<String> index =
            (json.decode(await indexFile.readAsString()) as List<dynamic>)
                .cast<String>();

        for (final String id in index) {
          expect(
            await File(p.join(root.path, '$id.json')).exists(),
            isTrue,
            reason: 'Indexed broadcaster $id must have a backing file',
          );
        }

        final List<FileSystemEntity> entries = root.listSync();
        for (final FileSystemEntity entry in entries) {
          if (entry is! File) {
            continue;
          }
          final String name = entry.path.split(Platform.pathSeparator).last;
          if (name == '_index.json' ||
              name.contains(FileUserAttributeStore.tmpInfix)) {
            continue;
          }
          if (!name.endsWith('.json')) {
            continue;
          }
          final String id = name.substring(0, name.length - '.json'.length);
          expect(
            index,
            contains(id),
            reason: 'File $name exists but $id is missing from the index',
          );
        }

        // If b-old-1 was revived by the racing setColor (file exists), its
        // value must be the new color, not lost to cleanup's deletion.
        if (await File(p.join(root.path, 'b-old-1.json')).exists()) {
          expect((await store.loadColors('b-old-1'))['u1'], 0xFFAA0000);
        }
      },
    );

    test('cleanup with concurrent setColor on the same expired broadcaster '
        'never deadlocks', () async {
      // Regression guard: an earlier draft wrapped the entire cleanup in
      // _withIndexLock which deadlocks against setColor's _addToIndex
      // (per-broadcaster lock -> index lock vs index lock -> per-broadcaster
      // lock). This test asserts the operation completes within a bound.
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      final File f = File(p.join(tempRoot.path, 'user_attributes', 'b1.json'));
      final Map<String, dynamic> raw =
          json.decode(await f.readAsString()) as Map<String, dynamic>;
      raw['_lastUsedAt'] = DateTime.now()
          .subtract(const Duration(days: 400))
          .millisecondsSinceEpoch;
      await f.writeAsString(json.encode(raw), flush: true);

      await Future.wait(<Future<void>>[
        store.cleanup(),
        store.setColor(
          broadcasterId: 'b1',
          userId: 'u2',
          colorValue: 0xFFAA0000,
        ),
      ]).timeout(const Duration(seconds: 5));
    });
  });

  group('FileUserAttributeStore.isWellFormedTmpSuffix', () {
    // The strict three-all-digit-tokens contract is the *only* guarantee
    // that prevents _sweepTmpOrphans from deleting a legitimate
    // broadcaster file whose ID happens to contain the tmp infix. These
    // unit tests pin that contract independently of the directory walk.

    test('three all-digit dot-separated tokens is accepted', () {
      expect(FileUserAttributeStore.isWellFormedTmpSuffix('123.456.789'), true);
      // The shape produced by _tmpFileFor uses pid / micros / counter.
      expect(
        FileUserAttributeStore.isWellFormedTmpSuffix('1.1700000000000000.0'),
        true,
      );
      // Single-digit tokens are still all-digit and three in count.
      expect(FileUserAttributeStore.isWellFormedTmpSuffix('0.0.0'), true);
    });

    test('empty string is rejected', () {
      expect(FileUserAttributeStore.isWellFormedTmpSuffix(''), false);
    });

    test('leading dot is rejected (produces empty first token)', () {
      expect(FileUserAttributeStore.isWellFormedTmpSuffix('.123.456'), false);
    });

    test('trailing dot is rejected (4 tokens with empty last)', () {
      expect(FileUserAttributeStore.isWellFormedTmpSuffix('123.456.'), false);
    });

    test('double dot in middle is rejected (empty middle token)', () {
      expect(FileUserAttributeStore.isWellFormedTmpSuffix('123..456'), false);
    });

    test('four tokens are rejected', () {
      expect(FileUserAttributeStore.isWellFormedTmpSuffix('1.2.3.4'), false);
    });

    test('two tokens are rejected', () {
      expect(FileUserAttributeStore.isWellFormedTmpSuffix('123.456'), false);
    });

    test('non-digit characters in any token are rejected', () {
      expect(FileUserAttributeStore.isWellFormedTmpSuffix('1a.2.3'), false);
      expect(FileUserAttributeStore.isWellFormedTmpSuffix('1.2b.3'), false);
      expect(FileUserAttributeStore.isWellFormedTmpSuffix('1.2.3c'), false);
      // Unicode digits are not ASCII 0-9 and must be rejected.
      expect(
        FileUserAttributeStore.isWellFormedTmpSuffix('1.2.\u{FF13}'),
        false,
      );
      // Negative sign must be rejected.
      expect(FileUserAttributeStore.isWellFormedTmpSuffix('-1.2.3'), false);
    });

    test('legitimate broadcaster file suffix ".json" is rejected', () {
      // A bare broadcaster file name minus the infix portion will look
      // nothing like a tmp suffix; this guards the negative case that
      // motivated the tightening (the regression in the comment above
      // the broadcaster-ID-vs-tmp-infix collision group).
      expect(FileUserAttributeStore.isWellFormedTmpSuffix('json'), false);
      expect(FileUserAttributeStore.isWellFormedTmpSuffix('123.json'), false);
      expect(
        FileUserAttributeStore.isWellFormedTmpSuffix('123.456.json'),
        false,
      );
    });
  });
}
