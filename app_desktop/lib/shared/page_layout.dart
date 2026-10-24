import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Qué parte del ancho pueden ocupar, como mucho, las acciones del encabezado.
const double _actionsShare = 0.65;

/// Estructura común de una pantalla: título, subtítulo, acciones arriba a la
/// derecha y contenido centrado con ancho máximo.
class PageLayout extends StatelessWidget {
  const PageLayout({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.child,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.lg,
            Spacing.lg,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: theme.textTheme.headlineMedium,
                              ),
                            ),
                            if (subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(top: Spacing.xs),
                                child: Text(
                                  subtitle!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (actions.isNotEmpty)
                        // Las acciones no pueden comerse todo el ancho: si no
                        // entran, bajan de renglón y el título conserva su lugar.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: _actionsShare * width,
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: Spacing.sm,
                            runSpacing: Spacing.sm,
                            children: actions,
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: Spacing.lg),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
