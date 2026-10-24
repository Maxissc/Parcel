import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/json_helpers.dart';
import 'account_exception.dart';
import 'account_http.dart';
import '../protocol/redact.dart';

const String _service = 'Nuvio';
const String _wellKnownUrl = 'https://api.nuvio.tv/.well-known/nuvio';

/// Dónde vive el backend de Nuvio, según su `/.well-known/nuvio`.
class NuvioService {
  const NuvioService({required this.backendUrl, required this.publishableKey});

  /// URL base del backend, sin barra final.
  final String backendUrl;

  /// Key pública que el servicio publica para sus clientes (no es un secreto
  /// del usuario, pero tampoco se escribe en el código: se lee del servicio).
  final String publishableKey;

  @override
  String toString() => 'NuvioService($backendUrl)';
}

/// Sesión de Nuvio. Vive en memoria mientras dura la migración: no se
/// persiste.
class NuvioSession {
  const NuvioSession({
    required this.accessToken,
    required this.service,
    this.refreshToken,
  });

  final String accessToken;
  final String? refreshToken;
  final NuvioService service;

  @override
  String toString() => 'NuvioSession(${service.backendUrl})';
}

/// Fila de la tabla `addons` de Nuvio.
class NuvioAddon {
  const NuvioAddon({
    required this.url,
    this.name,
    this.enabled = true,
    this.sortOrder = 0,
    this.profileId = 1,
  });

  /// URL del addon tal como la guarda Nuvio. Puede traer tokens del usuario:
  /// no se muestra ni se loguea completa.
  final String url;
  final String? name;
  final bool enabled;
  final int sortOrder;
  final int profileId;

  @override
  String toString() => 'NuvioAddon(${redactAddonUrl(url, name: name)})';
}

/// Cliente de la cuenta de Nuvio: descubre el backend, inicia sesión con email
/// y contraseña y lee la lista de addons.
///
/// Lo único que recuerda es la respuesta de `/.well-known/nuvio` (en memoria).
/// Contraseñas y tokens solo viajan en cada llamada. Todas las fallas salen
/// como [AccountException] con mensajes para la UI.
class NuvioAccountClient {
  NuvioAccountClient(
    http.Client httpClient, {
    this.wellKnownUrl = _wellKnownUrl,
    this.requestTimeout = accountRequestTimeout,
  }) : _http = httpClient;

  final http.Client _http;

  /// Dirección del descubrimiento.
  final String wellKnownUrl;

  /// Plazo de cada pedido.
  final Duration requestTimeout;

  NuvioService? _cached;

  /// Lee `/.well-known/nuvio` y recuerda el resultado en memoria. Con
  /// [refresh] vuelve a pedirlo.
  Future<NuvioService> discover({bool refresh = false}) async {
    final cached = _cached;
    if (cached != null && !refresh) return cached;
    final response = await sendAccountRequest(
      () => _http.get(Uri.parse(wellKnownUrl)),
      service: _service,
      timeout: requestTimeout,
    );
    final body = asMap(decodeAccountBody(response));
    final backend = asNonEmptyString(body?['backend_url']);
    final key = asNonEmptyString(body?['publishable_key']);
    final uri = backend == null ? null : Uri.tryParse(backend);
    final valid =
        response.statusCode >= 200 &&
        response.statusCode < 300 &&
        key != null &&
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (!valid) throw _unavailable();
    var base = backend!;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return _cached = NuvioService(backendUrl: base, publishableKey: key);
  }

  /// Inicia sesión con email y contraseña.
  Future<NuvioSession> login(String email, String password) async {
    final service = await discover();
    final response = await sendAccountRequest(
      () => _http.post(
        Uri.parse('${service.backendUrl}/auth/v1/token?grant_type=password'),
        headers: {
          'content-type': 'application/json',
          'apikey': service.publishableKey,
        },
        body: jsonEncode({'email': email, 'password': password}),
      ),
      service: _service,
      timeout: requestTimeout,
    );
    final body = asMap(decodeAccountBody(response));
    if (response.statusCode >= 500) throw _unavailable();
    if (response.statusCode >= 400) {
      if (asString(body?['error_code']) == 'invalid_credentials') {
        throw const AccountException(
          AccountFailureReason.invalidCredentials,
          'El email o la contraseña no son correctos.',
        );
      }
      throw const AccountException(
        AccountFailureReason.rejected,
        'Nuvio rechazó el pedido. Probá de nuevo.',
      );
    }
    final token = asNonEmptyString(body?['access_token']);
    if (token == null) throw _unavailable();
    return NuvioSession(
      accessToken: token,
      refreshToken: asNonEmptyString(body?['refresh_token']),
      service: service,
    );
  }

  /// Addons de la cuenta, ordenados por perfil y por `sort_order`. Descarta
  /// las filas sin `url`.
  Future<List<NuvioAddon>> getAddons(NuvioSession session) async {
    final service = session.service;
    final response = await sendAccountRequest(
      () => _http.get(
        Uri.parse(
          '${service.backendUrl}/rest/v1/addons'
          '?select=url,name,enabled,sort_order,profile_id'
          '&order=profile_id.asc,sort_order.asc',
        ),
        headers: _authHeaders(session),
      ),
      service: _service,
      timeout: requestTimeout,
    );
    final body = decodeAccountBody(response);
    if (response.statusCode >= 500) throw _unavailable();
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AccountException(
        AccountFailureReason.sessionExpired,
        'La sesión de Nuvio venció. Volvé a iniciar sesión.',
      );
    }
    if (response.statusCode >= 400) {
      throw const AccountException(
        AccountFailureReason.rejected,
        'Nuvio rechazó el pedido. Probá de nuevo.',
      );
    }
    if (body is! List) throw _unavailable();
    final addons = <NuvioAddon>[];
    for (final item in body) {
      final row = asMap(item);
      final url = row == null ? null : asNonEmptyString(row['url']);
      if (row == null || url == null) continue;
      addons.add(
        NuvioAddon(
          url: url,
          name: asNonEmptyString(row['name']),
          enabled: asBool(row['enabled']) ?? true,
          sortOrder: asInt(row['sort_order']) ?? 0,
          profileId: _profileId(row['profile_id']),
        ),
      );
    }
    return List.unmodifiable(addons);
  }

  /// Entero o string numérico tal cual; sin dato, el perfil 1. Un string que
  /// no es numérico se mapea a un id negativo estable (FNV-1a del texto), para
  /// que ese perfil no se mezcle con el 1 ni con otro perfil.
  static int _profileId(Object? raw) {
    final id = asInt(raw);
    if (id != null) return id;
    final text = raw is String ? raw.trim() : '';
    if (text.isEmpty) return 1;
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return -1 - hash;
  }

  /// Cierra la sesión en Nuvio. Nunca lanza: si falla, el token sigue vigente
  /// del lado del servidor hasta que venza.
  Future<void> logout(NuvioSession session) async {
    try {
      await _http
          .post(
            Uri.parse('${session.service.backendUrl}/auth/v1/logout'),
            headers: _authHeaders(session),
          )
          .timeout(requestTimeout);
    } on Object {
      // Falla silenciosa a propósito.
    }
  }

  Map<String, String> _authHeaders(NuvioSession session) => {
    'apikey': session.service.publishableKey,
    'authorization': 'Bearer ${session.accessToken}',
  };

  AccountException _unavailable() => const AccountException(
    AccountFailureReason.serviceUnavailable,
    'Nuvio no está disponible en este momento. Probá de nuevo más tarde.',
  );
}
