import 'package:flutter/material.dart';

import '../../shared/state_views.dart';

/// Inicio: todavía un marcador de lugar (lo llena la siguiente entrega).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.home_outlined,
      title: 'Próximamente',
      message:
          'Acá vas a ver lo que estás mirando y los catálogos de tus addons.',
    );
  }
}
