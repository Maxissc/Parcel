import 'dart:async';
import 'dart:math' as math;

import '../models/addon_stream.dart';
import 'stream_prober.dart';
import 'stream_signals.dart';

/// Lo que devolvió [AutoStreamSelector.select].
class AutoSelection {
  const AutoSelection({
    required this.chosen,
    required this.alternatives,
    required this.attempts,
    this.cancelled = false,
    this.unprobed = const [],
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

  /// Los no cacheados (`StreamSignals.cached == false`): nunca se prueban ni se
  /// eligen solos porque pedir su URL encola una descarga en el debrid. Están
  /// al final de [alternatives], para elegirlos a mano.
  final List<AddonStream> unprobed;
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
    this.batchSize = 2,
    this.maxAttempts = 9,
    this.grace = const Duration(milliseconds: 1500),
  }) : assert(batchSize > 0, 'batchSize tiene que ser mayor a 0');

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

    // Los no cacheados no se prueban: pedir su URL agrega el torrent a la
    // cuenta de debrid y encola una descarga.
    final uncached = <int>[];
    final candidates = <int>[];
    for (var i = 0; i < ranked.length; i++) {
      if (StreamSignals.of(ranked[i]).cached == false) {
        uncached.add(i);
      } else {
        candidates.add(i);
      }
    }

    final failed = <int>{};
    var next = 0;
    var attempts = 0;
    int? winner;
    while (!cancelled &&
        winner == null &&
        next < candidates.length &&
        attempts < maxAttempts) {
      final size = math.min(
        batchSize,
        math.min(maxAttempts - attempts, candidates.length - next),
      );
      final indices = candidates.sublist(next, next + size);
      next += size;
      attempts += size;
      winner = await _runBatch(ranked, indices, cancelSignal.future, failed);
    }
    if (cancelled) winner = null;
    return AutoSelection(
      chosen: winner == null ? null : ranked[winner],
      alternatives: [
        for (final i in candidates)
          if (i != winner && !failed.contains(i)) ranked[i],
        for (final i in uncached) ranked[i],
      ],
      attempts: attempts,
      cancelled: cancelled,
      unprobed: [for (final i in uncached) ranked[i]],
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
      prober
          .probe(ranked[i], abortTrigger: abort.future)
          .then(
            (result) {
              results[i] = result;
              // Los que abortamos nosotros no cuentan como falla.
              if (!result.ok && result.failure != ProbeFailure.cancelled) {
                failed.add(i);
              }
              evaluate();
            },
            onError: (Object _) {
              results[i] = const ProbeResult.failure(ProbeFailure.network);
              failed.add(i);
              evaluate();
            },
          );
    }
    return decision.future;
  }
}
