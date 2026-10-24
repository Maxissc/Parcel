import '../models/installed_addon.dart';
import '../models/json_helpers.dart';
import '../protocol/manifest_url.dart';
import 'nuvio_account_client.dart';
import 'pasted_addons_parser.dart';
import 'redact.dart';
import 'stremio_account_client.dart';

/// De dónde viene un candidato de migración.
enum MigrationSource { stremio, nuvio, pasted }

const String _alreadyInstalledNote = 'Ya instalado';
const String _localOnlyNote = 'Solo funciona dentro de Stremio';
const String _disabledNote = 'Desactivado en Nuvio';
const String _invalidUrlNote = 'La dirección no es válida';
const String _stremioLocalId = 'org.stremio.local';

/// Un addon que se puede traer desde otra cuenta o desde texto pegado.
class MigrationCandidate {
  const MigrationCandidate({
    required this.transportUrl,
    required this.displayName,
    required this.source,
    this.manifest,
    this.selectedByDefault = false,
    this.note,
    this.alreadyInstalled = false,
    this.profileId,
  });

  /// URL normalizada del manifest (o la original si no era válida y el
  /// candidato está descartado). Puede traer tokens: no se muestra completa.
  final String transportUrl;

  /// Nombre para la lista: el del manifest o del servicio, o el host.
  final String displayName;
  final MigrationSource source;

  /// Manifest embebido, si la fuente lo trajo (Stremio).
  final Map<String, dynamic>? manifest;

  /// Si la UI lo tiene que mostrar tildado al principio.
  final bool selectedByDefault;

  /// Aviso para mostrar junto al candidato («Ya instalado», «Desactivado en
  /// Nuvio»...).
  final String? note;

  /// Ya hay un addon igual en Parcel.
  final bool alreadyInstalled;

  /// Perfil de Nuvio al que pertenece; `null` en las otras fuentes.
  final int? profileId;

  @override
  String toString() =>
      'MigrationCandidate(${redactAddonUrl(transportUrl, name: displayName)})';
}

/// Lo que se puede migrar desde una fuente, listo para que la UI lo muestre y
/// el usuario confirme. Se aplica con `MigrationService.apply`.
class MigrationPlan {
  MigrationPlan._({
    required this.source,
    required List<MigrationCandidate> candidates,
    required List<MigrationCandidate> discarded,
    required List<int> profileIds,
  }) : candidates = List.unmodifiable(candidates),
       discarded = List.unmodifiable(discarded),
       profileIds = List.unmodifiable(profileIds);

  final MigrationSource source;

  /// Candidatos en el orden en que se instalan.
  final List<MigrationCandidate> candidates;

  /// Los que no se pueden migrar, con su [MigrationCandidate.note] para
  /// explicar por qué. No se instalan.
  final List<MigrationCandidate> discarded;

  /// Perfiles de Nuvio con addons, de menor a mayor. Vacío en las otras
  /// fuentes.
  final List<int> profileIds;

  /// Perfil preseleccionado: el 1 si existe, si no el menor. `null` fuera de
  /// Nuvio.
  int? get defaultProfileId {
    if (profileIds.isEmpty) return null;
    return profileIds.contains(1) ? 1 : profileIds.first;
  }

  /// Candidatos de [profileId]. Con `null` devuelve todos.
  List<MigrationCandidate> candidatesForProfile(int? profileId) =>
      profileId == null
      ? candidates
      : List.unmodifiable(candidates.where((c) => c.profileId == profileId));

  /// Candidatos que la UI muestra tildados al principio. En Nuvio, los del
  /// [profileId] elegido (por defecto, [defaultProfileId]).
  List<MigrationCandidate> defaultSelection({int? profileId}) =>
      List.unmodifiable(
        candidatesForProfile(profileId ?? defaultProfileId)
            .where((c) => c.selectedByDefault),
      );

  /// Plan desde la colección de addons de una cuenta de Stremio. Conserva su
  /// orden; deja aparte Local Files y cualquier addon de la máquina local.
  /// [installed] son los addons que ya tiene Parcel.
  factory MigrationPlan.fromStremio(
    Iterable<StremioAddonEntry> entries, {
    Iterable<InstalledAddon> installed = const [],
  }) {
    final index = _InstalledIndex(installed);
    final candidates = <MigrationCandidate>[];
    final discarded = <MigrationCandidate>[];
    final seen = <String>{};
    for (final entry in entries) {
      final manifestName = asNonEmptyString(entry.manifest?['name']);
      final url = _tryNormalize(entry.transportUrl);
      if (url == null) {
        discarded.add(
          MigrationCandidate(
            transportUrl: entry.transportUrl,
            displayName: manifestName ?? redactAddonUrl(entry.transportUrl),
            source: MigrationSource.stremio,
            manifest: entry.manifest,
            note: _invalidUrlNote,
          ),
        );
        continue;
      }
      final name = manifestName ?? redactAddonUrl(url);
      if (_isLocal(url, asNonEmptyString(entry.manifest?['id']))) {
        discarded.add(
          MigrationCandidate(
            transportUrl: url,
            displayName: name,
            source: MigrationSource.stremio,
            manifest: entry.manifest,
            note: _localOnlyNote,
          ),
        );
        continue;
      }
      if (!seen.add(url)) continue;
      final already = index.contains(
        url,
        asNonEmptyString(entry.manifest?['id']),
      );
      candidates.add(
        MigrationCandidate(
          transportUrl: url,
          displayName: name,
          source: MigrationSource.stremio,
          manifest: entry.manifest,
          selectedByDefault: !already,
          note: already ? _alreadyInstalledNote : null,
          alreadyInstalled: already,
        ),
      );
    }
    return MigrationPlan._(
      source: MigrationSource.stremio,
      candidates: candidates,
      discarded: discarded,
      profileIds: const [],
    );
  }

  /// Plan desde la lista de addons de una cuenta de Nuvio. Agrupa por perfil
  /// y conserva `sort_order` dentro de cada uno; los desactivados entran sin
  /// seleccionar.
  factory MigrationPlan.fromNuvio(
    Iterable<NuvioAddon> rows, {
    Iterable<InstalledAddon> installed = const [],
  }) {
    final index = _InstalledIndex(installed);
    final sorted = rows.toList()
      ..sort((a, b) {
        final byProfile = a.profileId.compareTo(b.profileId);
        return byProfile != 0 ? byProfile : a.sortOrder.compareTo(b.sortOrder);
      });
    final candidates = <MigrationCandidate>[];
    final discarded = <MigrationCandidate>[];
    final seen = <String>{};
    final profiles = <int>{};
    for (final row in sorted) {
      final url = _tryNormalize(row.url);
      if (url == null) {
        discarded.add(
          MigrationCandidate(
            transportUrl: row.url,
            displayName: row.name ?? redactAddonUrl(row.url),
            source: MigrationSource.nuvio,
            note: _invalidUrlNote,
            profileId: row.profileId,
          ),
        );
        continue;
      }
      if (!seen.add('${row.profileId}|$url')) continue;
      profiles.add(row.profileId);
      final already = index.contains(url, null);
      candidates.add(
        MigrationCandidate(
          transportUrl: url,
          displayName: row.name ?? redactAddonUrl(url),
          source: MigrationSource.nuvio,
          selectedByDefault: row.enabled && !already,
          note: already
              ? _alreadyInstalledNote
              : (row.enabled ? null : _disabledNote),
          alreadyInstalled: already,
          profileId: row.profileId,
        ),
      );
    }
    return MigrationPlan._(
      source: MigrationSource.nuvio,
      candidates: candidates,
      discarded: discarded,
      profileIds: profiles.toList()..sort(),
    );
  }

  /// Plan desde URLs ya normalizadas (por ejemplo, de `PastedAddonsParser`).
  /// Todas entran seleccionadas, salvo las que ya están instaladas.
  factory MigrationPlan.fromPasted(
    Iterable<String> urls, {
    Iterable<InstalledAddon> installed = const [],
  }) {
    final index = _InstalledIndex(installed);
    final candidates = <MigrationCandidate>[];
    final seen = <String>{};
    for (final raw in urls) {
      final url = _tryNormalize(raw);
      if (url == null || !seen.add(url)) continue;
      final already = index.contains(url, null);
      candidates.add(
        MigrationCandidate(
          transportUrl: url,
          displayName: redactAddonUrl(url),
          source: MigrationSource.pasted,
          selectedByDefault: !already,
          note: already ? _alreadyInstalledNote : null,
          alreadyInstalled: already,
        ),
      );
    }
    return MigrationPlan._(
      source: MigrationSource.pasted,
      candidates: candidates,
      discarded: const [],
      profileIds: const [],
    );
  }

  /// Plan desde un texto pegado: lo lee con `PastedAddonsParser`.
  factory MigrationPlan.fromPastedText(
    String text, {
    Iterable<InstalledAddon> installed = const [],
  }) => MigrationPlan.fromPasted(
    PastedAddonsParser.parse(text),
    installed: installed,
  );
}

String? _tryNormalize(String url) {
  try {
    return normalizeManifestUrl(url);
  } on FormatException {
    return null;
  }
}

bool _isLocal(String normalizedUrl, String? manifestId) {
  if (manifestId == _stremioLocalId) return true;
  final host = Uri.parse(normalizedUrl).host.toLowerCase();
  return host == '127.0.0.1' || host == 'localhost' || host == '::1';
}

/// Addons que Parcel ya tiene, para marcar los candidatos repetidos con el
/// mismo criterio que el repositorio: misma `transportUrl` o mismo id.
class _InstalledIndex {
  _InstalledIndex(Iterable<InstalledAddon> installed)
    : _urls = {for (final a in installed) a.transportUrl},
      _ids = {for (final a in installed) a.manifest.id};

  final Set<String> _urls;
  final Set<String> _ids;

  bool contains(String url, String? manifestId) =>
      _urls.contains(url) || (manifestId != null && _ids.contains(manifestId));
}
