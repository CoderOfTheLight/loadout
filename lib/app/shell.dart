/// Five-tab M3 shell (design §9): Home · Events · Items · Recipes ·
/// Settings over `StatefulShellRoute.indexedStack`.
///
/// **On the tab names.** These were reviewed against the owner's own
/// vocabulary rather than against a style guide. She says "item" ("just add
/// item?", "the new item one", "that should just be the name of the item and
/// how many") — so "Items" is her word and stays; "Stock" would be ours.
/// "Events" is what a market day, a fair and a club match all are, and it is
/// the noun every screen in the app already uses. "Recipes" is literal for a
/// food stall. Nothing here was renamed, which also keeps the tab label and
/// each list screen's own title in agreement.
///
/// The bar itself is flat with a hairline top edge: a drop shadow under the
/// navigation bar is invisible in daylight, a 1 dp line is not.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LoadoutShell extends StatelessWidget {
  const LoadoutShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) => navigationShell.goBranch(
            index,
            // Re-tapping the active tab pops that branch to its root.
            initialLocation: index == navigationShell.currentIndex,
          ),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
              tooltip: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.event_outlined),
              selectedIcon: Icon(Icons.event),
              label: 'Events',
              tooltip: 'Events',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Items',
              tooltip: 'Items',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Recipes',
              tooltip: 'Recipes',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
              tooltip: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
