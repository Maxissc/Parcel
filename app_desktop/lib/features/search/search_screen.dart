import 'package:flutter/material.dart';

import '../../shared/state_views.dart';

/// Buscar: todavía un marcador de lugar (lo llena la siguiente entrega).
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.search,
      title: 'Próximamente',
      message: 'Acá vas a buscar películas y series en todos tus addons.',
    );
  }
}
