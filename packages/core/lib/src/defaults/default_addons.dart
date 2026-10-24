/// Manifest de Cinemeta, el addon oficial de catálogos y metadatos.
const String cinemetaManifestUrl = 'https://v3-cinemeta.strem.io/manifest.json';

/// Manifest de OpenSubtitles v3, el addon de subtítulos.
const String openSubtitlesManifestUrl =
    'https://opensubtitles-v3.strem.io/manifest.json';

/// Addons que la app sugiere instalar. El core no los instala solo.
const List<String> defaultAddonUrls = [
  cinemetaManifestUrl,
  openSubtitlesManifestUrl,
];
