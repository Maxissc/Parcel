/// Arma la URL de un recurso del protocolo de addons.
///
/// `{baseUrl}/{resource}/{type}/{id}.json`, o con extras
/// `{baseUrl}/{resource}/{type}/{id}/{k=v&k2=v2}.json`. `type`, `id` y los
/// extras van URL-encoded como hace Stremio (por ejemplo, `tt1:1:2` queda
/// `tt1%3A1%3A2`). [baseUrl] es la base de transporte, sin `/manifest.json`.
String buildResourceUrl({
  required String baseUrl,
  required String resource,
  required String type,
  required String id,
  Map<String, String> extra = const {},
}) {
  final path =
      '$baseUrl/$resource/${Uri.encodeComponent(type)}/${Uri.encodeComponent(id)}';
  if (extra.isEmpty) return '$path.json';
  final query = extra.entries
      .map(
        (e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
      )
      .join('&');
  return '$path/$query.json';
}
