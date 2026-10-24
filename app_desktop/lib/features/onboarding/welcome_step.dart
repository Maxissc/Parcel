import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'onboarding_controller.dart';
import 'wizard_scaffold.dart';

/// Paso 1: elegir de dónde traer los addons.
class WelcomeStep extends ConsumerWidget {
  const WelcomeStep({super.key, this.onLeave});

  /// Sale del asistente (solo si se abrió desde otra pantalla).
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(onboardingProvider.notifier);
    return WizardScaffold(
      title: 'Traé tus addons',
      subtitle:
          'Parcel muestra el contenido de tus addons. Podés traer los que ya '
          'usás en Stremio o en Nuvio, o pegar una lista.',
      onBack: onLeave,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _SourceCard(
                    key: const Key('source-stremio'),
                    autofocus: true,
                    icon: Icons.qr_code_2,
                    title: 'Stremio',
                    description: 'Con un código o con tu email.',
                    onTap: () =>
                        controller.chooseSource(OnboardingStep.stremio),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: _SourceCard(
                    key: const Key('source-nuvio'),
                    icon: Icons.cloud_download_outlined,
                    title: 'Nuvio',
                    description: 'Con tu email y contraseña.',
                    onTap: () => controller.chooseSource(OnboardingStep.nuvio),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: _SourceCard(
                    key: const Key('source-paste'),
                    icon: Icons.content_paste,
                    title: 'Pegar lista',
                    description: 'Las URLs de tus addons, una por línea.',
                    onTap: () => controller.chooseSource(OnboardingStep.paste),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),
          Center(
            child: Column(
              children: [
                TextButton(
                  key: const Key('use-defaults'),
                  onPressed: controller.useDefaults,
                  child: const Text('Empezar con los addons básicos'),
                ),
                Text(
                  'Cinemeta y OpenSubtitles v3: catálogos y subtítulos.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        autofocus: autofocus,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: Spacing.md),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.xs),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
