// Pedidos HTTP que se pueden abortar de verdad. Uso interno del paquete.

import 'dart:async';

import 'package:http/http.dart' as http;

/// `GET` a [url] que se corta si [abortTrigger] se completa: el pedido se
/// aborta (el socket se cierra) en vez de seguir bajando en segundo plano.
///
/// Si se aborta, lanza [http.RequestAbortedException].
Future<http.Response> getAbortable(
  http.Client client,
  Uri url, {
  Map<String, String> headers = const {},
  Future<void>? abortTrigger,
}) async {
  final request = http.AbortableRequest('GET', url, abortTrigger: abortTrigger)
    ..headers.addAll(headers);
  final streamed = await client.send(request);
  return http.Response.fromStream(streamed);
}

/// Corre [run] con un plazo de [timeout]. Al vencer, completa el trigger que
/// recibe [run] (para que aborte el pedido) y falla con [TimeoutException].
Future<T> runWithTimeoutAbort<T>(
  Duration timeout,
  Future<T> Function(Future<void> abortTrigger) run,
) {
  final abort = Completer<void>();
  return run(abort.future).timeout(
    timeout,
    onTimeout: () {
      if (!abort.isCompleted) abort.complete();
      throw TimeoutException(null, timeout);
    },
  );
}
