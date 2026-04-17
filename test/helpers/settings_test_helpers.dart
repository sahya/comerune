import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> scrollToKeyInList(
  WidgetTester tester,
  Key listKey,
  Key targetKey,
) async {
  final Finder target = find.byKey(targetKey);
  final Finder scrollable = find
      .descendant(of: find.byKey(listKey), matching: find.byType(Scrollable))
      .first;
  if (target.evaluate().isEmpty) {
    try {
      await tester.scrollUntilVisible(target, -120, scrollable: scrollable);
    } on StateError {
      await tester.scrollUntilVisible(target, 120, scrollable: scrollable);
    }
  }
  await tester.pumpAndSettle();
}

Future<void> focusFieldByKey(
  WidgetTester tester,
  Key listKey,
  Key fieldKey,
) async {
  await scrollToKeyInList(tester, listKey, fieldKey);
  await tester.tap(find.byKey(fieldKey), warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> enterTextByKey(
  WidgetTester tester,
  Key listKey,
  Key fieldKey,
  String text,
) async {
  await focusFieldByKey(tester, listKey, fieldKey);
  await tester.enterText(find.byKey(fieldKey), text);
  await tester.pumpAndSettle();
}

Future<void> toggleSwitchByKey(
  WidgetTester tester,
  Key listKey,
  Key switchKey,
) async {
  await scrollToKeyInList(tester, listKey, switchKey);
  final SwitchListTile tile = tester.widget(
    find.byKey(switchKey, skipOffstage: false),
  );
  tile.onChanged!.call(!tile.value);
  await tester.pumpAndSettle();
}

Future<void> expandExpansionTileByKey(
  WidgetTester tester,
  Key listKey,
  Key tileKey,
) async {
  await scrollToKeyInList(tester, listKey, tileKey);
  await tester.ensureVisible(find.byKey(tileKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(tileKey), warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> toggleFilterChipByKey(
  WidgetTester tester,
  Key listKey,
  Key chipKey,
) async {
  await scrollToKeyInList(tester, listKey, chipKey);
  final FilterChip chip = tester.widget(
    find.byKey(chipKey, skipOffstage: false),
  );
  chip.onSelected!.call(!chip.selected);
  await tester.pumpAndSettle();
}

void toggleSwitchByKeySync(WidgetTester tester, Key switchKey) {
  final SwitchListTile tile = tester.widget(
    find.byKey(switchKey, skipOffstage: false),
  );
  tile.onChanged!.call(!tile.value);
}
