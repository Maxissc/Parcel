import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/json_helpers.dart';
import 'account_exception.dart';
import 'account_http.dart';
import '../protocol/redact.dart';

const String _service = 'Stremio';
const String _linkBase = 'https://link.stremio.com';
const String _apiBase = 'https://api.strem.io';

/// Código de vinculación de Stremio: el usuario abre [link] (o escanea el QR) y
/// aprueba la vinculación desde su cuenta.
class LinkCode {
  const LinkCode({
    required this.code,
    required this.link,
    required this.qrcodeUrl,
  });

  final String code;
  final String link;

  /// URL de una imagen con el QR de [link].
  final String qrcodeUrl;

  @override
  String toString() => 'LinkCode($code)';
}

/// Un addon de la colección de una cuenta de Stremio.
class StremioAddonEntry {
  const StremioAddonEntry({
    required this.transportUrl,
    this.manifest,
    this.official = false,
    this.isProtected = false,
  });

  /// URL del manifest, tal como la guarda Stremio. Puede traer tokens del
  /// usuario: no se muestra ni se loguea completa.
  final String transportUrl;

  /// Manifest embebido, si vino.
  final Map<String, dynamic>? manifest;

  /// Addon oficial de Stremio (`flags.official`).
  final bool official;

  /// Addon que Stremio no deja desinstalar (`flags.protected`).
  final bool isProtected;

  @override
  String toString() =>
      'StremioAddonEntry(${redactAddonUrl(transportUrl, name: asNonEmptyString(manifest?['name']))})';
}

/// Cliente de la cuenta de Stremio: código de vinculación, login con email y
/// lectura de la colección de addons.
///
/// No guarda estado: contraseñas y `authKey` solo viajan en cada llamada. Todas
/// las fallas salen como [AccountException] con mensajes para la UI.
class StremioAccountClient {
  StremioAccountClient(
    http.Client httpClient, {
    this.requestTimeout = accountRequestTimeout,
  }) : _http = httpClient;

  final http.Client _http;

  /// Plazo de cada pedido.
  final Duration requestTimeout;

  /// Pide un código de vinculación nuevo.
  Future<LinkCode> createLinkCode() async {
    final response = await sendAccountRequest(
      () => _http.get(Uri.parse('$_linkBase/api/v2/create?type=Create')),
      service: _service,
      timeout: requestTimeout,
    );
    final body = asMap(decodeAccountBody(response));
    final result = asMap(body?['result']);
    final code = asNonEmptyString(result?['code']);
    final link = asNonEmptyString(result?['link']);
    final qr = asNonEmptyString(result?['qrcode']);
    if (code == null || link == null || qr == null) {
      throw body?['error'] != null
          ? _rejected()
          : unexpectedAccountResponse(response, service: _service);
    }
    return LinkCode(code: code, link: link, qrcodeUrl: qr);
  }

  /// Consulta cada [interval] si el usuario aprobó el código [code].
  ///
  /// El stream emite el `authKey` una vez y se cierra. Mientras el servidor
  /// contesta el error 101 (todavía sin aprobar) sigue esperando; si pasa
  /// [timeout] sin aprobación, termina con [LinkCodeExpired]; cualquier otra
  /// falla termina con una [AccountException]. Cancelar la suscripción frena
  /// las consultas.
  Stream<String> pollLinkCode(
    String code, {
    Duration interval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 5),
  }) {
    late final StreamController<String> controller;
    Timer? waiting;
    Completer<void>? wake;
    var cancelled = false;

    Future<void> run() async {
      final clock = Stopwatch()..start();
      try {
        while (!cancelled) {
          final authKey = await _readLink(code);
          if (cancelled) return;
          if (authKey != null) {
            controller.add(authKey);
            return;
          }
          if (clock.elapsed >= timeout) throw const LinkCodeExpired();
          wake = Completer<void>();
          waiting = Timer(interval, wake!.complete);
          await wake!.future;
        }
      } on AccountException catch (e) {
        if (!cancelled) controller.addError(e);
      } finally {
        if (!controller.isClosed) await controller.close();
      }
    }

    controller = StreamController<String>(
      onListen: () => unawaited(run()),
      onCancel: () {
        cancelled = true;
        waiting?.cancel();
        final pending = wake;
        if (pending != null && !pending.isCompleted) pending.complete();
      },
    );
    return controller.stream;
  }

  /// Inicia sesión con email y contraseña y devuelve el `authKey`.
  Future<String> login(String email, String password) async {
    final body = await _post('login', {
      'type': 'Login',
      'email': email,
      'password': password,
      'facebook': false,
    });
    final error = asMap(body['error']);
    if (error != null) {
      final code = asInt(error['code']);
      if (code == 2 || asBool(error['wrongEmail']) == true) {
        throw const AccountException(
          AccountFailureReason.accountNotFound,
          'No encontramos una cuenta de Stremio con ese email.',
        );
      }
      if (code == 3 || asBool(error['wrongPassphrase']) == true) {
        throw const AccountException(
          AccountFailureReason.wrongPassword,
          'La contraseña es incorrecta.',
        );
      }
      throw _rejected();
    }
    return _authKey(body);
  }

  /// Addons de la cuenta, en el orden de Stremio. Descarta las entradas sin
  /// `transportUrl`.
  Future<List<StremioAddonEntry>> getAddonCollection(String authKey) async {
    final body = await _post('addonCollectionGet', {
      'type': 'AddonCollectionGet',
      'authKey': authKey,
      'update': true,
    });
    final error = asMap(body['error']);
    if (error != null) {
      if (asInt(error['code']) == 1) {
        throw const AccountException(
          AccountFailureReason.sessionExpired,
          'La sesión de Stremio venció. Volvé a iniciar sesión.',
        );
      }
      throw _rejected();
    }
    final raw = asMap(body['result'])?['addons'];
    if (raw is! List) {
      throw const AccountException(
        AccountFailureReason.parse,
        'Stremio respondió algo inesperado.',
      );
    }
    final entries = <StremioAddonEntry>[];
    for (final item in raw) {
      final map = asMap(item);
      final url = map == null ? null : asNonEmptyString(map['transportUrl']);
      if (map == null || url == null) continue;
      final flags = asMap(map['flags']);
      entries.add(
        StremioAddonEntry(
          transportUrl: url,
          manifest: asMap(map['manifest']),
          official: asBool(flags?['official']) ?? false,
          isProtected: asBool(flags?['protected']) ?? false,
        ),
      );
    }
    return List.unmodifiable(entries);
  }

  /// Cierra la sesión de [authKey] en Stremio. Nunca lanza: si falla, la
  /// sesión queda abierta del lado del servidor y no pasa nada más.
  Future<void> logout(String authKey) async {
    try {
      await _http
          .post(
            Uri.parse('$_apiBase/api/logout'),
            headers: _jsonHeaders,
            body: jsonEncode({'type': 'Logout', 'authKey': authKey}),
          )
          .timeout(requestTimeout);
    } on Object {
      // Falla silenciosa a propósito.
    }
  }

  static const Map<String, String> _jsonHeaders = {
    'content-type': 'application/json',
  };

  /// `authKey` si el usuario ya aprobó; `null` si sigue pendiente (error 101).
  Future<String?> _readLink(String code) async {
    final response = await sendAccountRequest(
      () => _http.get(
        Uri.parse(
          '$_linkBase/api/v2/read?type=Read&code=${Uri.encodeQueryComponent(code)}',
        ),
      ),
      service: _service,
      timeout: requestTimeout,
    );
    final body = asMap(decodeAccountBody(response));
    if (body == null) {
      throw unexpectedAccountResponse(response, service: _service);
    }
    final error = asMap(body['error']);
    if (error != null) {
      if (asInt(error['code']) == 101) return null;
      throw _rejected();
    }
    return _authKey(body);
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, Object?> payload,
  ) async {
    final response = await sendAccountRequest(
      () => _http.post(
        Uri.parse('$_apiBase/api/$endpoint'),
        headers: _jsonHeaders,
        body: jsonEncode(payload),
      ),
      service: _service,
      timeout: requestTimeout,
    );
    final body = asMap(decodeAccountBody(response));
    if (body == null || (body['result'] == null && body['error'] == null)) {
      throw unexpectedAccountResponse(response, service: _service);
    }
    return body;
  }

  String _authKey(Map<String, dynamic> body) {
    final key = asNonEmptyString(asMap(body['result'])?['authKey']);
    if (key == null) {
      throw const AccountException(
        AccountFailureReason.parse,
        'Stremio respondió algo inesperado.',
      );
    }
    return key;
  }

  AccountException _rejected() => const AccountException(
    AccountFailureReason.rejected,
    'Stremio rechazó el pedido. Probá de nuevo.',
  );
}
