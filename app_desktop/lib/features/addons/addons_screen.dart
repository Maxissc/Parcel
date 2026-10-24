import 'package:flutter/material.dart';

import '../../shared/state_views.dart';

/// Addons (marcador de lugar mientras se arma la pantalla).
class AddonsScreen extends StatelessWidget {
  const AddonsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(icon: Icons.extension_outlined, title: 'Addons');
  }
}
