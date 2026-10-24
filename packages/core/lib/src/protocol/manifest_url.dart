import 'redact.dart';

const String _manifestFile = 'manifest.json';

/// Normaliza la URL de un manifest de addon.
///
/// Convierte `stremio://` en `https://`, tolera espacios y barras finales y
/// completa `/manifest.json` si falta. Lanza [FormatException] si lo que queda
/// no es una URL http(s) con host.
String normalizeManifestUrl(String input) {
  var text = input.trim();
  if (text.toLowerCase().startsWith('stremio://')) {
    text = 'https://${text.substring('stremio://'.length)}';
  }
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty) {
    throw FormatException(
      'No es una URL de addon válida',
      redactAddonUrl(input),
    );
  }
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (!path.toLowerCase().endsWith('/$_manifestFile')) {
    path = '$path/$_manifestFile';
  }
  return uri.replace(path: path).toString();
}

/// Base de transporte de un addon: la URL del manifest sin `/manifest.json`
/// y sin query ni fragmento (la query la devuelve [transportQuery]).
///
/// Las rutas de recursos (`/catalog/...`, `/stream/...`) cuelgan de acá.
String transportBaseUrl(String manifestUrl) {
  var url = manifestUrl.trim();
  final cut = url.indexOf(RegExp('[?#]'));
  if (cut >= 0) url = url.substring(0, cut);
  if (url.toLowerCase().endsWith('/$_manifestFile')) {
    return url.substring(0, url.length - _manifestFile.length - 1);
  }
  return url;
}

/// Query de la URL del manifest, sin el `?` (vacía si no tiene). Va al final
/// de cada URL de recurso.
String transportQuery(String manifestUrl) {
  final url = manifestUrl.trim();
  final start = url.indexOf('?');
  if (start < 0) return '';
  final end = url.indexOf('#', start);
  return url.substring(start + 1, end < 0 ? url.length : end);
}
