import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parcel_core/parcel_core.dart' show QualityPreference;

import '../../app/app_info.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/app_settings.dart';
import '../../data/platform.dart';
import '../../data/providers.dart';
import '../../shared/page_layout.dart';
import '../detail/tmdb_enrichment.dart';
import '../player/player_route.dart';
import 'home_rows_editor.dart';
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
            title: 'Reproducción',
            children: [
              SwitchListTile(
                key: const Key('setting-auto-source'),
                title: const Text('Elegir la fuente automáticamente'),
                subtitle: const Text(
                  'Al dar play, Parcel prueba las mejores fuentes y arranca '
                  'con la que anda. Si la apagás, elegís de una lista.',
                ),
                value: settings.autoSelectSource,
                onChanged: (v) => _saveSetting(
                  context,
                  () => notifier.setAutoSelectSource(v),
                ),
              ),
              SwitchListTile(
                key: const Key('setting-auto-next'),
                title: const Text('Pasar solo al siguiente episodio'),
                subtitle: const Text(
                  'Al terminar, aparece una cuenta regresiva de 10 segundos '
                  'y arranca el que sigue. Podés cancelarla.',
                ),
                value: settings.autoPlayNext,
                onChanged: (v) =>
                    _saveSetting(context, () => notifier.setAutoPlayNext(v)),
              ),
              ListTile(
                title: const Text('Calidad preferida'),
                trailing: DropdownButton<QualityPreference>(
                  key: const Key('setting-quality'),
                  value: settings.quality,
                  underline: const SizedBox.shrink(),
                  onChanged: (q) {
                    if (q != null) {
                      unawaited(
                        _saveSetting(context, () => notifier.setQuality(q)),
                      );
                    }
                  },
                  items: const [
                    DropdownMenuItem(
                      value: QualityPreference.p1080,
                      child: Text('1080p'),
                    ),
                    DropdownMenuItem(
                      value: QualityPreference.p2160,
                      child: Text('4K'),
                    ),
                    DropdownMenuItem(
                      value: QualityPreference.p720,
                      child: Text('720p'),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                key: const Key('setting-fullscreen'),
                title: const Text('Abrir en pantalla completa'),
                value: settings.openFullScreen,
                onChanged: (v) =>
                    _saveSetting(context, () => notifier.setOpenFullScreen(v)),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          const _Section(
            title: 'Inicio',
            description:
                'Ordená las filas de la pantalla de inicio o ocultá las que '
                'no uses. Las ocultas no se piden.',
            children: [HomeRowsEditor()],
          ),
          const SizedBox(height: Spacing.md),
          _Section(
            title: 'Idiomas',
            description:
                'Al abrir un video, el reproductor elige el audio y los '
                'subtítulos en estos idiomas si los encuentra. «Original» '
                'busca el audio en el idioma en que se hizo el contenido. Si '
                'no hay subtítulos en el idioma elegido, quedan apagados.',
            children: [
              _LanguageTile(
                fieldKey: const Key('audio-language'),
                title: 'Idioma preferido del audio',
                options: audioLanguageOptions,
                value: settings.audioLanguage,
                onChanged: (code) => _saveSetting(
                  context,
                  () => notifier.setAudioLanguage(code),
                ),
              ),
              _LanguageTile(
                fieldKey: const Key('subtitle-language'),
                title: 'Idioma preferido de los subtítulos',
                options: subtitleLanguageOptions,
                value: settings.subtitleLanguage,
                onChanged: (code) => _saveSetting(
                  context,
                  () => notifier.setSubtitleLanguage(code),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          _Section(
            title: 'Datos del contenido',
            children: [
              _TmdbKeyTile(
                value: settings.tmdbApiKey,
                invalid: ref.watch(tmdbKeyInvalidProvider),
                onSave: (key) => _saveSetting(
                  context,
                  () => notifier.setTmdbApiKey(key),
                  confirmation: 'Guardado',
                ),
                onOpenSite: () => unawaited(
                  ref.read(urlOpenerProvider)(
                    Uri.parse('https://www.themoviedb.org/settings/api'),
                  ),
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

  /// Guarda un ajuste; si no se puede avisa. Con [confirmation] avisa también
  /// cuando se guardó.
  Future<void> _saveSetting(
    BuildContext context,
    Future<void> Function() save, {
    String? confirmation,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await save();
      if (confirmation != null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(confirmation),
              duration: const Duration(seconds: 2),
            ),
          );
      }
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

/// Campo de la API key de TMDB (opcional). Se muestra enmascarada y se guarda
/// al salir del campo o con Enter. Vacía, se quita.
class _TmdbKeyTile extends StatefulWidget {
  const _TmdbKeyTile({
    required this.value,
    required this.invalid,
    required this.onSave,
    required this.onOpenSite,
  });

  final String? value;

  /// TMDB rechazó la key guardada.
  final bool invalid;
  final ValueChanged<String?> onSave;
  final VoidCallback onOpenSite;

  @override
  State<_TmdbKeyTile> createState() => _TmdbKeyTileState();
}

class _TmdbKeyTileState extends State<_TmdbKeyTile> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value ?? '',
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void didUpdateWidget(_TmdbKeyTile old) {
    super.didUpdateWidget(old);
    // Si la key cambió por otro lado (por ejemplo, se borraron los datos) y no
    // se está escribiendo, el campo la sigue.
    if (old.value != widget.value &&
        !_focus.hasFocus &&
        _controller.text.trim() != (widget.value ?? '')) {
      _controller.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text == (widget.value ?? '')) return;
    widget.onSave(text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('setting-tmdb-key'),
            controller: _controller,
            focusNode: _focus,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'API key de TMDB (opcional)',
              // Sin mostrar la key: solo que no sirvió.
              errorText: widget.invalid && widget.value != null
                  ? 'La key de TMDB no es válida'
                  : null,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Suma fotos del elenco e idioma original. Conseguila gratis en '
            'themoviedb.org.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('setting-tmdb-link'),
              onPressed: widget.onOpenSite,
              child: const Text('Abrir themoviedb.org'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.fieldKey,
    required this.title,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final Key fieldKey;
  final String title;
  final List<({String code, String label})> options;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    // Un código guardado que ya no está en la lista se muestra como «sin
    // preferencia» para que el menú no falle.
    final known = options.any((o) => o.code == value);
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
          for (final option in options)
            DropdownMenuItem(value: option.code, child: Text(option.label)),
        ],
      ),
    );
  }
}
