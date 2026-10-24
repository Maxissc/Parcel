import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_env.dart';

/// Qué pasó con cada pedido a Stremio o Nuvio, para chequear lo que la app
/// mandó (sin guardar contraseñas).
class AccountCalls {
  final List<String> paths = [];
  int count(String fragment) => paths.where((p) => p.contains(fragment)).length;
}

const stremioLinkUrl = 'https://link.stremio.com/ABCD';

Map<String, dynamic> stremioEntry(
  String url,
  String id,
  String name, {
  String? logo,
}) => {
  'transportUrl': url,
  'manifest': manifestJson(id, name, logo: logo),
  'flags': {'official': false},
};

/// Mundo falso de Stremio: código de vinculación, login por email y colección
/// de addons. [pendingReads] es cuántas veces responde «todavía no» antes de
/// aprobar el código (`-1` = nunca).
MockClient stremioWorld({
  required AccountCalls calls,
  required List<Map<String, dynamic>> addons,
  int pendingReads = 0,
  Object? loginError,
  ManifestRoutes? routes,
  Future<void>? loginGate,
  Future<void>? collectionGate,
  bool collectionFails = false,
}) {
  var reads = 0;
  final base = mockWorld(routes ?? defaultRoutes());
  return MockClient((request) async {
    final url = request.url;
    calls.paths.add('${request.method} ${url.host}${url.path}');
    if (url.host == 'link.stremio.com' && url.path == '/api/v2/create') {
      return jsonResponse({
        'result': {
          'success': true,
          'code': 'ABCD',
          'link': stremioLinkUrl,
          'qrcode': 'https://link.stremio.com/qr?data=x',
        },
      });
    }
    if (url.host == 'link.stremio.com' && url.path == '/api/v2/read') {
      reads++;
      if (pendingReads < 0 || reads <= pendingReads) {
        return jsonResponse({
          'error': {'code': 101, 'message': 'Invalid or expired token'},
        });
      }
      return jsonResponse({
        'result': {'authKey': 'fake-auth-key'},
      });
    }
    if (url.host == 'api.strem.io') {
      switch (url.path) {
        case '/api/login':
          await loginGate;
          return loginError != null
              ? jsonResponse({'error': loginError})
              : jsonResponse({
                  'result': {'authKey': 'fake-auth-key'},
                });
        case '/api/addonCollectionGet':
          await collectionGate;
          if (collectionFails) return http.Response('error', 500);
          return jsonResponse({
            'result': {'addons': addons},
          });
        case '/api/logout':
          return jsonResponse({
            'result': {'success': true},
          });
      }
    }
    return base.send(request).then(http.Response.fromStream);
  });
}

/// Mundo falso de Nuvio con [rows] como tabla de addons.
MockClient nuvioWorld({
  required AccountCalls calls,
  required List<Map<String, dynamic>> rows,
  bool badCredentials = false,
  ManifestRoutes? routes,
  Future<void>? loginGate,
  bool addonsFail = false,
}) {
  final base = mockWorld(routes ?? defaultRoutes());
  return MockClient((request) async {
    final url = request.url;
    calls.paths.add('${request.method} ${url.host}${url.path}');
    if (url.host == 'api.nuvio.tv') {
      switch (url.path) {
        case '/.well-known/nuvio':
          return jsonResponse({
            'version': 1,
            'service': 'nuvio',
            'backend_url': 'https://api.nuvio.tv',
            'publishable_key': 'fake-publishable-key',
          });
        case '/auth/v1/token':
          await loginGate;
          return badCredentials
              ? jsonResponse({
                  'code': 400,
                  'error_code': 'invalid_credentials',
                  'msg': 'Invalid login credentials',
                }, 400)
              : jsonResponse({
                  'access_token': 'fake-access-token',
                  'refresh_token': 'fake-refresh-token',
                });
        case '/rest/v1/addons':
          if (addonsFail) return http.Response('error', 500);
          return jsonResponse(rows);
        case '/auth/v1/logout':
          return http.Response('', 204);
      }
    }
    return base.send(request).then(http.Response.fromStream);
  });
}
