import 'dart:async';
import 'dart:math' as math;

import '../models/addon_stream.dart';
import 'stream_prober.dart';

/// Lo que devolvió [AutoStreamSelector.select].
class AutoSelection {
  const AutoSelection({
    required this.chosen,
    required this.alternatives,
    required this.attempts,
    this.cancelled = false,
  });

  /// El stream que se va a reproducir, o `null` si ninguno sirvió (o se
  /// canceló).
  final AddonStream? chosen;

  /// El resto de los streams, en orden de ranking, para pedir el «siguiente»
  /// si el reproductor falla. No incluye al elegido ni a los que ya fallaron
  /// la prueba.
  final List<AddonStream> alternatives;

  /// Cuántos streams se probaron.
  final int attempts;

  /// `true` si se canceló antes de elegir.
  final bool cancelled;
}

/// Elige solo el stream que va a reproducirse.
///
/// Prueba en paralelo los primeros [batchSize] del ranking. Cuando aparece el
/// primer éxito, espera hasta [grace] más por uno mejor rankeado (si ya
/// respondieron bien o mal todos los que estaban mejor, no espera) y se queda
/// con el mejor rankeado que respondió bien; aborta el resto. Si ninguno de la
/// tanda sirve, sigue con la tanda siguiente, hasta [maxAttempts] pruebas.
class AutoStreamSelector {
  AutoStreamSelector(
    this.prober, {
    this.batchSize = 3,
    this.maxAttempts = 9,
    this.grace = const Duration(milliseconds: 1500),
  });

  final StreamProber prober;
  final int batchSize;
  final int maxAttempts;
  final Duration grace;

  /// Elige entre [ranked] (ya ordenados, por ejemplo con `rankStreams`).
  /// [cancel] aborta todo lo que esté en curso.
  Future<AutoSelection> select(
    List<AddonStream> ranked, {
    Future<void>? cancel,
  }) async {
    var cancelled = false;
    final cancelSignal = Completer<void>();
    cancel?.then((_) {
      cancelled = true;
      if (!cancelSignal.isCompleted) cancelSignal.complete();
    }, onError: (_) {});
    // Deja correr los callbacks pendientes: un `cancel` que ya estaba
    // completado se ve antes de pedir nada.
    await Future<void>.value();

    final failed = <int>{};
    var next = 0;
    var attempts = 0;
    int? winner;
    while (!cancelled &&
        winner == null &&
        next < ranked.length &&
        attempts < maxAttempts) {
      final size = math.min(
        batchSize,
        math.min(maxAttempts - attempts, ranked.length - next),
      );
      final indices = [for (var i = next; i < next + size; i++) i];
      next += size;
      attempts += size;
      winner = await _runBatch(ranked, indices, cancelSignal.future, failed);
    }
    if (cancelled) winner = null;
    return AutoSelection(
      chosen: winner == null ? null : ranked[winner],
      alternatives: [
        for (var i = 0; i < ranked.length; i++)
          if (i != winner && !failed.contains(i)) ranked[i],
      ],
      attempts: attempts,
      cancelled: cancelled,
    );
  }

  /// Prueba [indices] en paralelo. Devuelve el índice elegido o `null`.
  Future<int?> _runBatch(
    List<AddonStream> ranked,
    List<int> indices,
    Future<void> cancel,
    Set<int> failed,
  ) {
    final abort = Completer<void>();
    final decision = Completer<int?>();
    final results = <int, ProbeResult>{};
    Timer? graceTimer;

    int? lowestSuccess() {
      for (final i in indices) {
        if (results[i]?.ok ?? false) return i;
      }
      return null;
    }

    void decide(int? index) {
      graceTimer?.cancel();
      if (!decision.isCompleted) decision.complete(index);
      if (!abort.isCompleted) abort.complete();
    }

    void evaluate() {
      if (decision.isCompleted) return;
      final best = lowestSuccess();
      if (best == null) {
        if (results.length == indices.length) decide(null);
        return;
      }
      final betterPending = indices.any(
        (i) => i < best && !results.containsKey(i),
      );
      if (!betterPending) {
        decide(best);
      } else {
        graceTimer ??= Timer(grace, () => decide(lowestSuccess()));
      }
    }

    cancel.then((_) => decide(null));
    for (final i in indices) {
      prober.probe(ranked[i], abortTrigger: abort.future).then((result) {
        results[i] = result;
        // Los que abortamos nosotros no cuentan como falla.
        if (!result.ok && result.failure != ProbeFailure.cancelled) {
          failed.add(i);
        }
        evaluate();
      });
    }
    return decision.future;
  }
}
