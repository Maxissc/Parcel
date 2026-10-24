import 'package:flutter/material.dart';

import '../../shared/state_views.dart';

/// Asistente de migración (marcador de lugar mientras se arma).
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: EmptyState(icon: Icons.auto_fix_high, title: 'Traé tus addons'),
    );
  }
}
