import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:parcel_desktop/data/cancellable_client.dart';

/// Un cliente que se queda esperando hasta que lo abortan, como un pedido que
/// no termina.
class _HangingClient extends http.BaseClient {
  final aborted = Completer<void>();
  http.BaseRequest? last;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    last = request;
    final trigger = request is http.Abortable ? request.abortTrigger : null;
    if (trigger != null) {
      unawaited(trigger.then((_) => aborted.complete()));
    }
    return Completer<http.StreamedResponse>().future;
  }
}

void main() {
  test('al cancelar se abortan los pedidos en curso', () async {
    final inner = _HangingClient();
    final cancel = Completer<void>();
    final client = CancellableClient(inner, cancel: cancel.future);
    unawaited(client.get(Uri.parse('http://x.example.com/a')));
    await Future<void>.delayed(Duration.zero);
    expect(inner.aborted.isCompleted, isFalse);

    cancel.complete();
    await inner.aborted.future.timeout(const Duration(seconds: 1));
    expect(inner.aborted.isCompleted, isTrue);
  });

  test('respeta el abort propio del pedido y conserva método, headers y '
      'cuerpo', () async {
    final inner = _HangingClient();
    final own = Completer<void>();
    final client = CancellableClient(inner, cancel: Completer<void>().future);
    final request =
        http.AbortableRequest(
            'POST',
            Uri.parse('http://x.example.com/b'),
            abortTrigger: own.future,
          )
          ..headers['x-prueba'] = '1'
          ..body = 'hola';
    unawaited(client.send(request));
    await Future<void>.delayed(Duration.zero);

    final sent = inner.last! as http.Request;
    expect(sent.method, 'POST');
    expect(sent.headers['x-prueba'], '1');
    expect(sent.body, 'hola');

    own.complete();
    await inner.aborted.future.timeout(const Duration(seconds: 1));
  });
}
