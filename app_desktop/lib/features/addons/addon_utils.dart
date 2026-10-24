import 'package:parcel_core/parcel_core.dart';

/// `true` si el manifest declara `behaviorHints.configurable`.
bool isConfigurable(InstalledAddon addon) {
  final hints = addon.manifest.toJson()['behaviorHints'];
  return hints is Map && hints['configurable'] == true;
}

/// Página de configuración del addon, que se abre en el navegador. Puede
/// llevar tokens: no se muestra, solo se abre.
Uri configureUri(InstalledAddon addon) =>
    Uri.parse('${addon.baseUrl}/configure');

/// Texto en español para un tipo de contenido del manifest.
String typeLabel(String type) => switch (type) {
  'movie' => 'Películas',
  'series' => 'Series',
  'channel' => 'Canales',
  'tv' => 'TV',
  'anime' => 'Anime',
  _ => type,
};

/// Por qué falló instalar un addon, en español y sin la URL.
String describeInstallFailure(AddonException error) => switch (error.reason) {
  AddonFailureReason.invalidUrl => 'La dirección del addon no es válida.',
  AddonFailureReason.timeout => 'El addon no respondió a tiempo.',
  AddonFailureReason.http =>
    error.statusCode == null
        ? 'El addon respondió con un error.'
        : 'El addon respondió con un error (HTTP ${error.statusCode}).',
  AddonFailureReason.network => 'No se pudo conectar con el addon.',
  AddonFailureReason.parse => 'La dirección no devolvió un manifest válido.',
};
