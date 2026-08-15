/// The folder identity chip (design-spec §3): one widget, two exact sizes,
/// tint + ink straight from the theme's precomputed [FolderPalette], and a
/// curated icon grid whose names can never drift from the validator's list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/theme.dart';
import 'package:loadout/app/widgets/folder_chip.dart';
import 'package:loadout/core/folder_appearance.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/time.dart';
import 'package:loadout/features/catalog/domain/demand_basis.dart';
import 'package:loadout/features/catalog/domain/folder.dart';

Future<void> pumpChip(WidgetTester tester, Widget chip) => tester.pumpWidget(
  MaterialApp(
    theme: loadoutTheme(Brightness.light),
    home: Scaffold(body: Center(child: chip)),
  ),
);

Folder folder({String name = 'Drinks', FolderHue? hue, String? iconName}) =>
    Folder(
      id: const FolderId('F0000000000000000000000000'),
      name: name,
      position: 2,
      demandBasis: DemandBasis.perPerson,
      hue: hue,
      iconName: iconName,
      createdAt: const Instant(1),
      updatedAt: const Instant(1),
    );

void main() {
  testWidgets('large chip is a 40 dp tinted rounded square with the icon in '
      'folder ink', (tester) async {
    await pumpChip(
      tester,
      const FolderChip(hue: FolderHue.lake, iconName: 'local_drink'),
    );
    final container = tester.widget<Container>(find.byType(Container));
    expect(container.constraints!.maxWidth, 40);
    expect(container.constraints!.maxHeight, 40);
    final decoration = container.decoration! as BoxDecoration;
    final pair = FolderPalette.derive(Brightness.light).pair(FolderHue.lake);
    expect(decoration.color, pair.tint);
    expect(decoration.borderRadius, BorderRadius.circular(Radii.small));
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.local_drink);
    expect(icon.size, 22);
    expect(icon.color, pair.ink);
  });

  testWidgets('small chip is 24 dp, icon 14, radius 8', (tester) async {
    await pumpChip(
      tester,
      const FolderChip(
        hue: FolderHue.clay,
        iconName: 'outdoor_grill',
        size: FolderChipSize.small,
      ),
    );
    final container = tester.widget<Container>(find.byType(Container));
    expect(container.constraints!.maxWidth, 24);
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(8));
    expect(tester.widget<Icon>(find.byType(Icon)).size, 14);
  });

  testWidgets('forFolder renders the folder\'s EFFECTIVE identity', (
    tester,
  ) async {
    // Stored choice wins…
    await pumpChip(
      tester,
      FolderChip.forFolder(folder(hue: FolderHue.plum, iconName: 'liquor')),
    );
    expect(tester.widget<Icon>(find.byType(Icon)).icon, Icons.liquor);

    // …and a bare folder falls back to position hue + starter-name icon.
    await pumpChip(tester, FolderChip.forFolder(folder()));
    final decoration =
        tester.widget<Container>(find.byType(Container)).decoration!
            as BoxDecoration;
    expect(
      decoration.color,
      FolderPalette.derive(Brightness.light).pair(FolderHue.byPosition(2)).tint,
    );
    expect(
      tester.widget<Icon>(find.byType(Icon)).icon,
      Icons.local_drink,
      reason: '"Drinks" is a starter name',
    );
  });

  testWidgets('an unknown stored icon name never crashes a build', (
    tester,
  ) async {
    await pumpChip(
      tester,
      const FolderChip(hue: FolderHue.stone, iconName: 'not_a_glyph'),
    );
    expect(tester.widget<Icon>(find.byType(Icon)).icon, Icons.inventory_2);
  });

  test('the icon grid and the validator\'s name list can never drift', () {
    expect([
      for (final choice in folderIconChoices) choice.name,
    ], folderIconNames);
    expect(folderIconNames.toSet(), hasLength(folderIconNames.length));
    expect(folderIconNames, contains(fallbackFolderIconName));
    for (final appearance in starterFolderAppearance.values) {
      expect(folderIconNames, contains(appearance.iconName));
    }
  });
}
