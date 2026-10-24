/// `true` si [url] se puede bajar con la red (http o https).
bool isHttpUrl(String? url) {
  final uri = url == null ? null : Uri.tryParse(url);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}
