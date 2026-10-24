import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/theme.dart';
import '../../shared/addon_logo.dart';
import '../../shared/redacted_url.dart';
import '../../shared/state_views.dart';
import 'onboarding_controller.dart';
import 'wizard_scaffold.dart';

/// Paso 5: revisar qué addons se traen y tildar los que se quieren.
class ReviewStep extends ConsumerWidget {
  const ReviewStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final controller = ref.read(onboardingProvider.notifier);
    final candidates = state.candidates;
    final discarded = state.discarded;
    final selectedCount = state.selectedCandidates.length;

    if (candidates.isEmpty && discarded.isEmpty) {
      return WizardScaffold(
        title: 'Revisá tus addons',
        onBack: controller.back,
        scrollable: false,
        child: const EmptyState(
          icon: Icons.inbox_outlined,
          title: 'No encontramos addons para traer',
          message: 'Volvé y probá con otra fuente.',
        ),
      );
    }

    return WizardScaffold(
      title: 'Revisá tus addons',
      subtitle: candidates.isEmpty
          ? 'No hay addons que se puedan traer de esta fuente.'
          : 'Tildá los que querés traer. Se instalan en este orden.',
      onBack: controller.back,
      scrollable: false,
      actions: [
        FilledButton.icon(
          key: const Key('import-button'),
          autofocus: candidates.isNotEmpty,
          onPressed: selectedCount == 0 ? null : controller.importSelected,
          icon: const Icon(Icons.download),
          label: Text(
            selectedCount == 1
                ? 'Importar 1 addon'
                : 'Importar $selectedCount addons',
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (candidates.isNotEmpty)
            Row(
              children: [
                Text(
                  '${candidates.length} '
                  '${candidates.length == 1 ? 'addon encontrado' : 'addons encontrados'}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                TextButton(
                  key: const Key('select-all'),
                  onPressed: controller.selectAll,
                  child: const Text('Seleccionar todo'),
                ),
                TextButton(
                  key: const Key('select-none'),
                  onPressed: controller.selectNone,
                  child: const Text('Ninguno'),
                ),
              ],
            ),
          Expanded(
            child: ListView(
              children: [
                for (final c in candidates)
                  _CandidateTile(
                    candidate: c,
                    checked: state.selected.contains(c.transportUrl),
                    onChanged: c.alreadyInstalled
                        ? null
                        : (_) => controller.toggle(c),
                  ),
                if (discarded.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      top: Spacing.md,
                      bottom: Spacing.xs,
                    ),
                    child: Text(
                      'No se pueden traer',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  for (final c in discarded)
                    _CandidateTile(
                      candidate: c,
                      checked: false,
                      onChanged: null,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.checked,
    required this.onChanged,
  });

  final MigrationCandidate candidate;
  final bool checked;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logo = candidate.manifest?['logo'];
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: CheckboxListTile(
          key: Key('candidate-${candidate.displayName}'),
          value: checked,
          onChanged: onChanged,
          controlAffinity: ListTileControlAffinity.leading,
          secondary: AddonLogo(logo is String ? logo : null, size: 40),
          title: Text(
            candidate.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sin nombre propio, el título ya es el host: no se repite.
              if (candidate.displayName !=
                  redactAddonUrl(candidate.transportUrl))
                RedactedUrl(candidate.transportUrl),
              if (candidate.note != null)
                Text(
                  candidate.note!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
