import 'dart:io';

import 'package:comerune/data/user/file_user_attribute_store.dart';
import 'package:comerune/data/user/user_attribute_store_migrator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  late Directory tempRoot;
  late FileUserAttributeStore fileStore;
  late InMemorySharedPreferences prefs;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('migrator_test_');
    fileStore = FileUserAttributeStore(
      root: Directory(p.join(tempRoot.path, 'user_attributes')),
    );
    prefs = InMemorySharedPreferences();
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test(
    'copies legacy SharedPreferences entries to FileUserAttributeStore',
    () async {
      await prefs.setString('usercolor._index', '["b1", "b2"]');
      await prefs.setString(
        'usercolor.b1',
        '{"u1": 4293212469, "_lastUsedAt": 1}',
      );
      await prefs.setString(
        'usercolor.b2',
        '{"u2": {"c": 4293212469, "n": "コテ"}, "_lastUsedAt": 2}',
      );

      final int migrated = await UserAttributeStoreMigrator(
        prefs: prefs,
        fileStore: fileStore,
      ).run();

      expect(migrated, 2);
      expect((await fileStore.loadColors('b1'))['u1'], 4293212469);
      expect((await fileStore.loadColors('b2'))['u2'], 4293212469);
      expect((await fileStore.loadNicknames('b2'))['u2'], 'コテ');
    },
  );

  test('is idempotent: second run does nothing', () async {
    await prefs.setString('usercolor._index', '["b1"]');
    await prefs.setString('usercolor.b1', '{"u1": 1, "_lastUsedAt": 1}');

    final int first = await UserAttributeStoreMigrator(
      prefs: prefs,
      fileStore: fileStore,
    ).run();
    expect(first, 1);

    // Mutate the file store to verify the second run is a true no-op.
    await fileStore.setColor(
      broadcasterId: 'b1',
      userId: 'u1',
      colorValue: 0xDEADBEEF,
    );

    final int second = await UserAttributeStoreMigrator(
      prefs: prefs,
      fileStore: fileStore,
    ).run();
    expect(second, 0, reason: 'migration marker must prevent re-run');
    expect(
      (await fileStore.loadColors('b1'))['u1'],
      0xDEADBEEF,
      reason: 'second run must not overwrite in-file data',
    );
  });

  test('handles missing legacy index gracefully', () async {
    final int migrated = await UserAttributeStoreMigrator(
      prefs: prefs,
      fileStore: fileStore,
    ).run();
    expect(migrated, 0);
    expect(prefs.getBool('usercolor.migratedToFile'), isTrue);
  });

  test('skips broadcasters whose raw JSON is missing or empty', () async {
    await prefs.setString('usercolor._index', '["b1", "b2"]');
    await prefs.setString('usercolor.b1', '{"u1": 1, "_lastUsedAt": 1}');
    // b2 has no corresponding value entry.

    final int migrated = await UserAttributeStoreMigrator(
      prefs: prefs,
      fileStore: fileStore,
    ).run();
    expect(migrated, 1);
    expect((await fileStore.loadColors('b1'))['u1'], 1);
    expect(await fileStore.loadColors('b2'), isEmpty);
  });

  test('continues migration when one entry fails to decode', () async {
    await prefs.setString('usercolor._index', '["b1", "b-corrupt", "b2"]');
    await prefs.setString('usercolor.b1', '{"u1": 1, "_lastUsedAt": 1}');
    await prefs.setString('usercolor.b-corrupt', '{not json');
    await prefs.setString('usercolor.b2', '{"u2": 2, "_lastUsedAt": 2}');

    final int migrated = await UserAttributeStoreMigrator(
      prefs: prefs,
      fileStore: fileStore,
    ).run();
    expect(migrated, 2);
    expect((await fileStore.loadColors('b1'))['u1'], 1);
    expect((await fileStore.loadColors('b2'))['u2'], 2);
    expect(await fileStore.loadColors('b-corrupt'), isEmpty);
  });

  test('handles malformed legacy index gracefully', () async {
    await prefs.setString('usercolor._index', 'not a json list');
    final int migrated = await UserAttributeStoreMigrator(
      prefs: prefs,
      fileStore: fileStore,
    ).run();
    expect(migrated, 0);
    expect(prefs.getBool('usercolor.migratedToFile'), isTrue);
  });

  test('resumes migration from scratch if marker was never set '
      '(simulates crash during partial migration)', () async {
    // Seed legacy data for 3 broadcasters.
    await prefs.setString('usercolor._index', '["b1", "b2", "b3"]');
    await prefs.setString('usercolor.b1', '{"u1": 1, "_lastUsedAt": 1}');
    await prefs.setString('usercolor.b2', '{"u1": 2, "_lastUsedAt": 2}');
    await prefs.setString('usercolor.b3', '{"u1": 3, "_lastUsedAt": 3}');

    // Simulate partial migration: pre-seed file store with b1 only.
    // The marker key is NOT set, simulating a crash before completion.
    await fileStore.importRawJson('b1', '{"u1": 1, "_lastUsedAt": 1}');
    expect(prefs.getBool('usercolor.migratedToFile'), isNull);

    // Run migration again from scratch.
    final int migrated = await UserAttributeStoreMigrator(
      prefs: prefs,
      fileStore: fileStore,
    ).run();

    // All 3 broadcasters are migrated. b1 is re-written (idempotent).
    expect(migrated, 3);
    expect((await fileStore.loadColors('b1'))['u1'], 1);
    expect((await fileStore.loadColors('b2'))['u1'], 2);
    expect((await fileStore.loadColors('b3'))['u1'], 3);
    expect(prefs.getBool('usercolor.migratedToFile'), isTrue);
  });
}
