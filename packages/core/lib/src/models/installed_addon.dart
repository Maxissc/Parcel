import '../protocol/manifest_url.dart';
import '../protocol/redact.dart';
import 'addon_manifest.dart';
import 'json_helpers.dart';

/// Un addon instalado: su manifest y la URL desde donde se instaló.
class InstalledAddon {
  const InstalledAddon({required this.transportUrl, required this.manifest});

  /// URL normalizada del manifest (ver `normalizeManifestUrl`).
  final String transportUrl;
  final AddonManifest manifest;

  /// Base de las rutas de recursos: [transportUrl] sin `/manifest.json` ni
  /// query (la query va al final de cada recurso).
  String get baseUrl => transportBaseUrl(transportUrl);

  /// Lanza [FormatException] si falta `transportUrl` o el manifest es inválido.
  factory InstalledAddon.fromJson(Map<String, dynamic> json) {
    final url = asNonEmptyString(json['transportUrl']);
    final manifest = asMap(json['manifest']);
    if (url == null || manifest == null) {
      throw FormatException('Addon instalado inválido', json);
    }
    return InstalledAddon(
      transportUrl: url,
      manifest: AddonManifest.fromJson(manifest),
    );
  }

  Map<String, dynamic> toJson() => {
    'transportUrl': transportUrl,
    'manifest': manifest.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is InstalledAddon &&
      other.transportUrl == transportUrl &&
      other.manifest == manifest;

  @override
  int get hashCode => Object.hash(transportUrl, manifest);

  @override
  String toString() =>
      'InstalledAddon(${redactAddonUrl(transportUrl, name: manifest.name)})';
}
