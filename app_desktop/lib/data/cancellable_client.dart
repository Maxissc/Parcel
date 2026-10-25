import 'dart:async';

import 'package:http/http.dart' as http;

/// Cliente que aborta los pedidos en curso cuando termina [cancel] (por
/// ejemplo, al salir de la pantalla que los pidió). No cierra el cliente de
/// adentro: es de la app.
class CancellableClient extends http.BaseClient {
  CancellableClient(this._inner, {required this._cancel});

  final http.Client _inner;
  final Future<void> _cancel;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is! http.Request) return _inner.send(request);
    final own = request is http.Abortable
        ? (request as http.Abortable).abortTrigger
        : null;
    final copy = http.AbortableRequest(
      request.method,
      request.url,
      abortTrigger: own == null ? _cancel : Future.any([own, _cancel]),
    );
    copy
      ..headers.addAll(request.headers)
      ..bodyBytes = request.bodyBytes
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;
    return _inner.send(copy);
  }

  @override
  void close() {}
}
