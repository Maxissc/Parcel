import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/platform.dart';
import '../../shared/state_views.dart';
import 'account_form.dart';
import 'onboarding_controller.dart';
import 'stremio_link_controller.dart';
import 'wizard_scaffold.dart';

/// Paso 2: traer los addons de Stremio, con un código (recomendado) o con
/// email y contraseña.
class StremioStep extends ConsumerStatefulWidget {
  const StremioStep({super.key});

  @override
  ConsumerState<StremioStep> createState() => _StremioStepState();
}

class _StremioStepState extends ConsumerState<StremioStep>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final FocusNode _emailFocus = FocusNode(debugLabel: 'stremio-email');
  int _lastIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTab);
    // El controlador del código vive mientras dure este paso (y no mientras la
    // pestaña esté en pantalla), y pide un código al entrar a la pestaña.
    ref.listenManual(stremioLinkProvider, (_, _) {});
    Future.microtask(() {
      if (mounted) unawaited(ref.read(stremioLinkProvider.notifier).start());
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  /// El código solo corre mientras se ve su pestaña.
  void _onTab() {
    if (_tabs.indexIsChanging || _tabs.index == _lastIndex) return;
    _lastIndex = _tabs.index;
    final link = ref.read(stremioLinkProvider.notifier);
    if (_lastIndex == 0) {
      unawaited(link.start());
    } else {
      link.cancel();
      // Ya con la pestaña a la vista, el cursor va al email.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabs.index == 1) _emailFocus.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(onboardingProvider.notifier);
    return WizardScaffold(
      title: 'Traé tus addons de Stremio',
      subtitle: 'Elegí cómo querés entrar a tu cuenta.',
      onBack: controller.back,
      scrollable: false,
      child: Column(
        children: [
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Con código'),
              Tab(text: 'Con email'),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                const _CodeTab(),
                SingleChildScrollView(
                  child: AccountForm(
                    submitLabel: 'Traer addons',
                    autofocus: false,
                    emailFocus: _emailFocus,
                    note:
                        'Si entrás a Stremio con Google o Facebook, usá el '
                        'código.',
                    onSubmit: controller.fetchStremioWithPassword,
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

class _CodeTab extends ConsumerWidget {
  const _CodeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(stremioLinkProvider);
    final controller = ref.read(stremioLinkProvider.notifier);
    switch (link.phase) {
      case LinkPhase.creating:
        return const LoadingState(label: 'Pidiendo un código a Stremio…');
      case LinkPhase.fetching:
        return const LoadingState(label: 'Trayendo tus addons…');
      case LinkPhase.expired:
        return EmptyState(
          icon: Icons.timer_off_outlined,
          title: 'El código venció',
          message: 'Generá uno nuevo para seguir.',
          actions: [
            FilledButton.icon(
              autofocus: true,
              onPressed: controller.start,
              icon: const Icon(Icons.refresh),
              label: const Text('Generar otro'),
            ),
          ],
        );
      case LinkPhase.fetchFailed:
        return ErrorState(
          title: 'No pudimos traer tus addons',
          message: '${link.message ?? 'Probá de nuevo.'} Generá un código '
              'nuevo para reintentar.',
          onRetry: controller.start,
        );
      case LinkPhase.error:
        return ErrorState(
          title: 'No pudimos conseguir el código',
          message: link.message ?? 'Probá de nuevo.',
          onRetry: controller.start,
        );
      case LinkPhase.waiting:
        return _WaitingView(link: link);
    }
  }
}

class _WaitingView extends ConsumerWidget {
  const _WaitingView({required this.link});

  final LinkState link;

  static String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final code = link.code!;
    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tu código', style: theme.textTheme.labelLarge),
                const SizedBox(height: Spacing.xs),
                SelectableText(
                  code.code,
                  key: const Key('link-code'),
                  style: theme.textTheme.displayMedium?.copyWith(
                    letterSpacing: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  'Entrá con tu cuenta de Stremio en el navegador y aprobá el '
                  'código.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: Spacing.lg),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    FilledButton.icon(
                      autofocus: true,
                      onPressed: () => _open(context, ref, code.link),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Abrir en el navegador'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _copy(context, code.link),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar link'),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.lg),
                Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Flexible(
                      child: Text(
                        'Esperando aprobación…  El código vence en '
                        '${_format(link.remaining)}',
                        key: const Key('link-waiting'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.sm),
                TextButton(
                  onPressed: ref.read(onboardingProvider.notifier).back,
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.lg),
          _Qr(url: code.qrcodeUrl),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, String link) async {
    final opened = await ref.read(urlOpenerProvider)(Uri.parse(link));
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos abrir el navegador. Copiá el link y abrilo a mano.',
          ),
        ),
      );
    }
  }

  Future<void> _copy(BuildContext context, String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Link copiado.')));
  }
}

class _Qr extends StatelessWidget {
  const _Qr({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Código QR para vincular Stremio',
      child: Container(
        width: 200,
        height: 200,
        padding: const EdgeInsets.all(Spacing.sm),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Image.network(
          url,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Center(child: CircularProgressIndicator()),
          errorBuilder: (context, error, stack) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.qr_code_2, size: 48, color: scheme.outline),
                const SizedBox(height: Spacing.xs),
                Text(
                  'No se pudo cargar el QR. Usá el código o el link.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.outline, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
