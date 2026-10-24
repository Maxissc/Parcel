import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_info.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/app_settings.dart';
import '../../data/providers.dart';
import '../../shared/page_layout.dart';
import '../player/player_route.dart';
import 'try_player_dialog.dart';

/// Ajustes: idiomas preferidos, asistente, datos y «Acerca de».
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    return PageLayout(
      title: 'Ajustes',
      child: ListView(
        padding: const EdgeInsets.only(bottom: Spacing.lg),
        children: [
          _Section(
            title: 'Idiomas',
            description:
                'Al abrir un video, el reproductor elige el audio y los '
                'subtítulos en estos idiomas si los encuentra. Si no hay '
                'subtítulos en el idioma elegido, quedan apagados.',
            children: [
              _LanguageTile(
                fieldKey: const Key('audio-language'),
                title: 'Idioma preferido del audio',
                value: settings.audioLanguage,
                onChanged: (code) => _saveLanguage(
                  context,
                  () => notifier.setAudioLanguage(code),
                ),
              ),
              _LanguageTile(
                fieldKey: const Key('subtitle-language'),
                title: 'Idioma preferido de los subtítulos',
                value: settings.subtitleLanguage,
                onChanged: (code) => _saveLanguage(
                  context,
                  () => notifier.setSubtitleLanguage(code),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          _Section(
            title: 'Asistente',
            children: [
              ListTile(
                leading: const Icon(Icons.auto_fix_high_outlined),
                title: const Text('Volver a correr el asistente'),
                subtitle: const Text(
                  'Traé addons desde Stremio, Nuvio o una lista pegada.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.onboarding),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          _Section(
            title: 'Datos',
            children: [
              ListTile(
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Borrar todos los datos',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                subtitle: const Text(
                  'Quita tus addons, el progreso y los ajustes de este equipo.',
                ),
                onTap: () => _confirmWipe(context, ref),
              ),
            ],
          ),
          if (kDebugMode) ...[
            const SizedBox(height: Spacing.md),
            _Section(
              title: 'Herramientas de desarrollo',
              description: 'Solo aparecen en las versiones de prueba.',
              children: [
                ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: const Text('Probar reproductor'),
                  subtitle: const Text('Reproduce una URL de video directa.'),
                  onTap: () => _tryPlayer(context),
                ),
              ],
            ),
          ],
          const SizedBox(height: Spacing.md),
          const _Section(
            title: 'Acerca de',
            children: [
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Parcel $appVersion'),
                subtitle: Text('Licencia MIT'),
              ),
              ListTile(
                leading: Icon(Icons.shield_outlined),
                title: Text('Parcel no incluye contenido ni addons'),
                subtitle: Text(
                  'Los addons son de terceros: vos elegís cuáles instalar y '
                  'de dónde vienen.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveLanguage(
    BuildContext context,
    Future<void> Function() save,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await save();
    } on Object {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar el cambio. Probá de nuevo.'),
        ),
      );
    }
  }

  Future<void> _tryPlayer(BuildContext context) async {
    final request = await showTryPlayerDialog(context);
    if (request == null || !context.mounted) return;
    unawaited(
      context.push(
        Routes.player,
        extra: PlayerArgs(
          url: request.url,
          subtitleUrl: request.subtitleUrl,
          title: Uri.tryParse(request.url)?.pathSegments.lastOrNull,
        ),
      ),
    );
  }

  Future<void> _confirmWipe(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar todos los datos?'),
        content: const Text(
          'Se borran tus addons, el progreso y los ajustes de este equipo. '
          'Tu cuenta de Stremio o de Nuvio no se toca. No se puede deshacer.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar todo'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(dataResetProvider).wipe();
    } on Object {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudieron borrar los datos. Probá de nuevo.'),
        ),
      );
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    this.description,
    required this.children,
  });

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
              if (description != null)
                Text(
                  description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.fieldKey,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final Key fieldKey;
  final String title;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    // Un código guardado que ya no está en la lista se muestra como «sin
    // preferencia» para que el menú no falle.
    final known = preferredLanguageOptions.any((o) => o.code == value);
    return ListTile(
      title: Text(title),
      trailing: DropdownButton<String>(
        key: fieldKey,
        value: known ? value : '',
        underline: const SizedBox.shrink(),
        onChanged: (code) =>
            onChanged(code == null || code.isEmpty ? null : code),
        items: [
          const DropdownMenuItem(value: '', child: Text('Sin preferencia')),
          for (final option in preferredLanguageOptions)
            DropdownMenuItem(value: option.code, child: Text(option.label)),
        ],
      ),
    );
  }
}
