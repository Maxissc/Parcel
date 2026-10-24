import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/theme.dart';
import '../../shared/addon_logo.dart';
import '../../shared/redacted_url.dart';
import 'onboarding_controller.dart';
import 'wizard_scaffold.dart';

/// Paso 6: progreso de la instalación y, al terminar, el informe.
class ProgressStep extends ConsumerWidget {
  const ProgressStep({super.key, required this.onFinish});

  /// «Ir al inicio»: marca el asistente como terminado y sale.
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final controller = ref.read(onboardingProvider.notifier);
    final theme = Theme.of(context);

    if (state.importing) {
      return WizardScaffold(
        title: 'Instalando addons…',
        subtitle: 'Puede tardar unos segundos. No cierres Parcel.',
        scrollable: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              key: const Key('import-progress'),
              value: state.total == 0 ? null : state.done / state.total,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              '${state.done} de ${state.total}'
              '${state.current == null ? '' : ' · ${state.current}'}',
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    final failed = state.failed;
    return WizardScaffold(
      title: failed.isEmpty ? 'Listo' : 'Terminamos, con algunos problemas',
      subtitle: failed.isEmpty
          ? 'Tus addons ya están instalados.'
          : 'Algunos addons no se pudieron instalar. Podés reintentarlos.',
      scrollable: false,
      actions: [
        if (failed.isNotEmpty)
          OutlinedButton.icon(
            key: const Key('retry-failed'),
            onPressed: controller.retryFailed,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar los que fallaron'),
          ),
        FilledButton(
          key: const Key('go-home'),
          autofocus: true,
          onPressed: onFinish,
          child: const Text('Ir al inicio'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              _Stat(
                key: const Key('stat-installed'),
                icon: Icons.check_circle_outline,
                label: state.installedCount == 1
                    ? '1 instalado'
                    : '${state.installedCount} instalados',
              ),
              _Stat(
                key: const Key('stat-already'),
                icon: Icons.inventory_2_outlined,
                label: state.alreadyInstalledCount == 1
                    ? '1 ya estaba'
                    : '${state.alreadyInstalledCount} ya estaban',
              ),
              _Stat(
                key: const Key('stat-failed'),
                icon: Icons.error_outline,
                label: failed.length == 1
                    ? '1 falló'
                    : '${failed.length} fallaron',
                error: failed.isNotEmpty,
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Expanded(
            child: ListView(
              children: [for (final item in state.items) _ItemTile(item: item)],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.icon,
    required this.label,
    this.error = false,
  });

  final IconData icon;
  final String label;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 18, color: error ? scheme.error : null),
      label: Text(label),
      side: BorderSide(color: error ? scheme.error : scheme.outlineVariant),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final MigrationItemReport item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidate = item.candidate;
    final logo = candidate.manifest?['logo'];
    final (icon, color) = switch (item.outcome) {
      MigrationOutcome.installed => (
        Icons.check_circle,
        theme.colorScheme.primary,
      ),
      MigrationOutcome.alreadyInstalled => (
        Icons.inventory_2_outlined,
        theme.colorScheme.onSurfaceVariant,
      ),
      MigrationOutcome.failed => (Icons.error, theme.colorScheme.error),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Card(
        child: ListTile(
          leading: AddonLogo(logo is String ? logo : null, size: 40),
          title: Text(
            candidate.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (candidate.displayName !=
                  redactAddonUrl(candidate.transportUrl))
                RedactedUrl(candidate.transportUrl),
              Text(
                item.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: item.outcome == MigrationOutcome.failed
                      ? theme.colorScheme.error
                      : null,
                ),
              ),
            ],
          ),
          trailing: Icon(icon, color: color),
        ),
      ),
    );
  }
}
