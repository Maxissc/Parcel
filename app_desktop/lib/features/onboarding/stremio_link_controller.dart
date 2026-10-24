import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../data/providers.dart';
import 'onboarding_controller.dart';

/// Tiempo que dura un código de vinculación de Stremio.
const Duration linkCodeLifetime = Duration(minutes: 5);

enum LinkPhase {
  /// Pidiendo el código a Stremio.
  creating,

  /// Mostrando el código, esperando que el usuario lo apruebe.
  waiting,

  /// Aprobado: bajando los addons.
  fetching,

  /// El código venció.
  expired,

  /// Se aprobó el código pero no se pudieron leer los addons.
  fetchFailed,

  /// Algo falló; [LinkState.message] dice qué.
  error,
}

class LinkState {
  const LinkState({
    this.phase = LinkPhase.creating,
    this.code,
    this.remaining = linkCodeLifetime,
    this.message,
  });

  final LinkPhase phase;
  final LinkCode? code;

  /// Cuánto falta para que venza el código.
  final Duration remaining;
  final String? message;
}

/// Vinculación de Stremio por código: pide el código, espera la aprobación,
/// trae los addons y los pasa al asistente. Se frena al salir del paso.
final stremioLinkProvider =
    NotifierProvider.autoDispose<StremioLinkController, LinkState>(
      StremioLinkController.new,
    );

class StremioLinkController extends Notifier<LinkState> {
  StreamSubscription<String>? _poll;
  Timer? _countdown;

  /// Se suma cada vez que se empieza o se cancela, para ignorar respuestas
  /// que llegan tarde de un intento anterior.
  int _attempt = 0;

  /// No arranca solo: quien muestra la pestaña llama a [start] al entrar, así
  /// que hay un único pedido de código por entrada.
  @override
  LinkState build() {
    ref.onDispose(_stop);
    return const LinkState();
  }

  void _stop() {
    _attempt++;
    unawaited(_poll?.cancel());
    _poll = null;
    _countdown?.cancel();
    _countdown = null;
  }

  /// Frena la espera (por ejemplo, al pasar a la pestaña de email).
  void cancel() {
    _stop();
    ref.read(onboardingProvider.notifier).cancelFetch();
    if (ref.mounted) state = const LinkState();
  }

  /// Pide un código nuevo y empieza a esperar.
  Future<void> start() async {
    _stop();
    final attempt = _attempt;
    state = const LinkState();
    final client = ref.read(stremioAccountClientProvider);
    final LinkCode code;
    try {
      code = await client.createLinkCode();
    } on AccountException catch (e) {
      if (attempt == _attempt && ref.mounted) {
        state = LinkState(phase: LinkPhase.error, message: e.message);
      }
      return;
    }
    if (attempt != _attempt || !ref.mounted) return;
    state = LinkState(phase: LinkPhase.waiting, code: code);
    _countdown = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tick(attempt),
    );
    _poll = client
        .pollLinkCode(code.code, timeout: linkCodeLifetime)
        .listen(
          (authKey) => unawaited(_approved(attempt, client, authKey)),
          onError: (Object error) => _failed(attempt, error),
        );
  }

  void _tick(int attempt) {
    if (attempt != _attempt || state.phase != LinkPhase.waiting) return;
    final remaining = state.remaining - const Duration(seconds: 1);
    if (remaining <= Duration.zero) {
      _expire(attempt);
      return;
    }
    state = LinkState(
      phase: LinkPhase.waiting,
      code: state.code,
      remaining: remaining,
    );
  }

  void _expire(int attempt) {
    if (attempt != _attempt) return;
    final code = state.code;
    _stop();
    state = LinkState(
      phase: LinkPhase.expired,
      code: code,
      remaining: Duration.zero,
    );
  }

  void _failed(int attempt, Object error) {
    if (attempt != _attempt || !ref.mounted) return;
    if (error is LinkCodeExpired) {
      _expire(attempt);
      return;
    }
    _stop();
    state = LinkState(
      phase: LinkPhase.error,
      message: error is AccountException
          ? error.message
          : 'No pudimos hablar con Stremio. Probá de nuevo.',
    );
  }

  Future<void> _approved(
    int attempt,
    StremioAccountClient client,
    String authKey,
  ) async {
    if (attempt != _attempt || !ref.mounted) {
      // Se canceló justo cuando se aprobaba: la sesión no se deja abierta.
      await client.logout(authKey);
      return;
    }
    _countdown?.cancel();
    state = LinkState(phase: LinkPhase.fetching, code: state.code);
    try {
      await ref
          .read(onboardingProvider.notifier)
          .fetchStremioWithAuthKey(authKey);
    } on AccountException catch (e) {
      _fetchFailed(attempt, e.message);
    } on Object {
      _fetchFailed(attempt, 'No pudimos leer tus addons. Probá de nuevo.');
    }
  }

  void _fetchFailed(int attempt, String message) {
    if (attempt == _attempt && ref.mounted) {
      state = LinkState(phase: LinkPhase.fetchFailed, message: message);
    }
  }
}
