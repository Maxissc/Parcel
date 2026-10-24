// Ayudas compartidas por los clientes de cuentas. Uso interno del paquete.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'account_exception.dart';

/// Plazo por defecto de cada pedido a una cuenta.
const Duration accountRequestTimeout = Duration(seconds: 20);

/// Corre [send] y traduce cualquier falla de conexión (incluido el plazo) a un
/// [AccountException] de red. El mensaje no incluye detalles del error.
Future<http.Response> sendAccountRequest(
  Future<http.Response> Function() send, {
  required String service,
  Duration timeout = accountRequestTimeout,
}) async {
  try {
    return await send().timeout(timeout);
  } on Exception {
    throw AccountException(
      AccountFailureReason.network,
      'No pudimos conectar con $service. Revisá tu conexión.',
    );
  }
}

/// Cuerpo de [response] como JSON, o `null` si no lo es.
Object? decodeAccountBody(http.Response response) {
  try {
    return jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
  } on FormatException {
    return null;
  }
}

/// Error para una respuesta que no se pudo interpretar: 5xx es servicio caído,
/// lo demás es respuesta inesperada.
AccountException unexpectedAccountResponse(
  http.Response response, {
  required String service,
}) {
  if (response.statusCode >= 500) {
    return AccountException(
      AccountFailureReason.serviceUnavailable,
      '$service no está disponible en este momento. Probá de nuevo más tarde.',
    );
  }
  return AccountException(
    AccountFailureReason.parse,
    '$service respondió algo inesperado.',
  );
}
