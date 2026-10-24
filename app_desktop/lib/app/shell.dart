import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:parcel_core/parcel_core.dart';

import 'theme.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination('Inicio', Icons.home_outlined, Icons.home),
  _Destination('Buscar', Icons.search, Icons.search),
  _Destination('Addons', Icons.extension_outlined, Icons.extension),
  _Destination('Ajustes', Icons.settings_outlined, Icons.settings),
];

const _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
];

/// Estructura de la app: barra lateral con las cuatro secciones y, al lado, la
/// sección activa. Ctrl+1 a Ctrl+4 cambian de sección.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _select(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        for (var i = 0; i < _destinations.length; i++)
          SingleActivator(_digitKeys[i], control: true): () => _select(i),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  // Con ventana ancha, la barra muestra los nombres al costado.
                  final wide = MediaQuery.sizeOf(context).width >= 1200;
                  return NavigationRail(
                    extended: wide,
                    minExtendedWidth: 200,
                    selectedIndex: navigationShell.currentIndex,
                    onDestinationSelected: _select,
                    labelType: wide
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                      child: Text(
                        appName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    destinations: [
                      for (var i = 0; i < _destinations.length; i++)
                        NavigationRailDestination(
                          icon: Tooltip(
                            message:
                                '${_destinations[i].label} (Ctrl+${i + 1})',
                            child: Icon(_destinations[i].icon),
                          ),
                          selectedIcon: Icon(_destinations[i].selectedIcon),
                          label: Text(_destinations[i].label),
                        ),
                    ],
                  );
                },
              ),
              const VerticalDivider(width: 1),
              Expanded(child: navigationShell),
            ],
          ),
        ),
      ),
    );
  }
}
