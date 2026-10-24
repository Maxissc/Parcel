import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Ancho del contenido del asistente.
const double wizardWidth = 720;

/// Marco común de los pasos del asistente: título, subtítulo, contenido que
/// se desplaza y una barra de acciones abajo.
class WizardScaffold extends StatelessWidget {
  const WizardScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.onBack,
    this.actions = const [],
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// «Atrás»; sin esto el botón no se muestra.
  final VoidCallback? onBack;

  /// Acciones principales, a la derecha de la barra de abajo.
  final List<Widget> actions;

  /// Si es `false`, [child] maneja su propio desplazamiento y ocupa todo el
  /// alto disponible.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: wizardWidth),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: theme.textTheme.headlineMedium),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(
                    subtitle!,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: Spacing.lg),
              Expanded(
                child: scrollable
                    ? SingleChildScrollView(
                        primary: false,
                        child: Padding(
                          padding: const EdgeInsets.only(right: Spacing.xs),
                          child: child,
                        ),
                      )
                    : child,
              ),
              if (onBack != null || actions.isNotEmpty) ...[
                const SizedBox(height: Spacing.md),
                Row(
                  children: [
                    if (onBack != null)
                      TextButton.icon(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Atrás'),
                      ),
                    const Spacer(),
                    for (final (i, action) in actions.indexed) ...[
                      if (i > 0) const SizedBox(width: Spacing.sm),
                      action,
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
