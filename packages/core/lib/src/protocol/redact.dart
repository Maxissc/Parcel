/// Versión de [url] segura para mostrar o loguear: solo el host (con puerto si
/// lo tiene), precedido por [name] si se conoce.
///
/// Las URLs de addons pueden llevar tokens o configuración del usuario en la
/// ruta o en la query; este helper las descarta. Si [url] no se puede leer,
/// devuelve `URL inválida` y nunca el texto original.
String redactAddonUrl(String url, {String? name}) {
  final uri = Uri.tryParse(url.trim());
  final validScheme =
      uri != null &&
      (uri.scheme == 'http' ||
          uri.scheme == 'https' ||
          uri.scheme == 'stremio');
  final host = validScheme && uri.host.isNotEmpty
      ? (uri.hasPort ? '${uri.host}:${uri.port}' : uri.host)
      : null;
  final cleanName = name?.trim();
  if (host == null) {
    return cleanName == null || cleanName.isEmpty
        ? 'URL inválida'
        : '$cleanName (URL inválida)';
  }
  return cleanName == null || cleanName.isEmpty ? host : '$cleanName ($host)';
}
