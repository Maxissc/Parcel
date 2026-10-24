import 'dart:async';
import 'dart:io';

import '../models/addon_manifest.dart';
import '../models/installed_addon.dart';
import '../models/json_helpers.dart';
import '../protocol/abortable_http.dart';
import '../protocol/addon_client.dart';
import '../protocol/addon_exception.dart';
import '../protocol/manifest_url.dart';
import 'json_file_store.dart';

/// Resultado de instalar un addon.
sealed class InstallResult {
  const InstallResult();
}

/// Se instaló [addon] (queda al final de la lista).
final class Installed extends InstallResult {
  const Installed(this.addon);

  final InstalledAddon addon;
}

/// Ya había un addon con la misma `transportUrl` o el mismo `manifest.id`.
final class AlreadyInstalled extends InstallResult {
  const AlreadyInstalled(this.existing);

  final InstalledAddon existing;
}

/// No se pudo instalar; [error] dice por qué.
final class InstallFailed extends InstallResult {
  const InstallFailed(this.error);

  final AddonException error;
}

/// Qué pasó con una URL de [AddonRepository.installAll].
class InstallReport {
  const InstallReport(this.url, this.result);

  /// La URL tal como se pidió.
  final String url;
  final InstallResult result;
}

/// Addons instalados, en orden de prioridad, persistidos en un archivo JSON.
///
/// Los errores de disco al guardar salen como excepciones de `dart:io`
/// ([install], [remove], [reorder]) o, en [installAll], como
/// [AddonFailureReason.storage]. Si guardar falla, la lista en memoria y el
/// stream de [changes] quedan como estaban.
class AddonRepository {
  AddonRepository._(
    this._client,
    this._store,
    this._installTimeout,
    this._addons,
  );

  final AddonClient _client;
  final JsonFileStore _store;
  final Duration _installTimeout;
  final List<InstalledAddon> _addons;
  final StreamController<List<InstalledAddon>> _changes =
      StreamController.broadcast();
  Future<void> _lastChange = Future.value();

  /// Abre el repositorio leyendo [filePath]. Si el archivo no existe arranca
  /// vacío; si está corrupto arranca vacío y lo deja como `<filePath>.bak`.
  /// [installTimeout] limita la bajada de cada manifest.
  static Future<AddonRepository> open({
    required AddonClient client,
    required String filePath,
    Duration installTimeout = const Duration(seconds: 15),
  }) async {
    final store = JsonFileStore(filePath);
    final json = await store.readObject();
    final addons = <InstalledAddon>[];
    if (json != null) {
      final raw = json['addons'];
      if (raw is List) {
        addons.addAll(parseList(raw, InstalledAddon.fromJson));
      } else {
        await store.backupCorrupt();
      }
    }
    return AddonRepository._(client, store, installTimeout, addons);
  }

  /// Addons instalados, en orden. La lista no se puede modificar.
  List<InstalledAddon> get addons => List.unmodifiable(_addons);

  /// Emite la lista completa cada vez que cambia (instalar, quitar, reordenar).
  Stream<List<InstalledAddon>> get changes => _changes.stream;

  /// Instala el addon de [url]: baja el manifest y lo agrega al final.
  Future<InstallResult> install(String url) async {
    final String transportUrl;
    try {
      transportUrl = normalizeManifestUrl(url);
    } on FormatException catch (e) {
      return InstallFailed(
        AddonException(AddonFailureReason.invalidUrl, e.message, url: url),
      );
    }
    final known = _findByUrl(transportUrl);
    if (known != null) return AlreadyInstalled(known);

    final InstalledAddon fetched;
    try {
      fetched = await runWithTimeoutAbort(
        _installTimeout,
        (abort) => _client.fetchManifest(transportUrl, abortTrigger: abort),
      );
    } on AddonException catch (e) {
      return InstallFailed(e);
    } on TimeoutException {
      return InstallFailed(
        AddonException(
          AddonFailureReason.timeout,
          'Sin respuesta en ${_installTimeout.inMilliseconds} ms',
          url: transportUrl,
        ),
      );
    }
    return _add(fetched);
  }

  /// Instala un addon cuyo manifest ya se conoce (por ejemplo, el que trae
  /// embebido la colección de Stremio), sin volver a bajarlo.
  Future<InstallResult> installManifest(
    String transportUrl,
    Map<String, dynamic> manifestJson,
  ) async {
    final String url;
    try {
      url = normalizeManifestUrl(transportUrl);
    } on FormatException catch (e) {
      return InstallFailed(
        AddonException(
          AddonFailureReason.invalidUrl,
          e.message,
          url: transportUrl,
        ),
      );
    }
    final AddonManifest manifest;
    try {
      manifest = AddonManifest.fromJson(manifestJson);
    } on FormatException catch (e) {
      return InstallFailed(
        AddonException(
          AddonFailureReason.parse,
          'Manifest inválido: ${e.message}',
          url: url,
        ),
      );
    }
    return _add(InstalledAddon(transportUrl: url, manifest: manifest));
  }

  /// Instala [urls] en orden, sigue ante fallas y devuelve un informe por URL.
  Future<List<InstallReport>> installAll(List<String> urls) async {
    final reports = <InstallReport>[];
    for (final url in urls) {
      InstallResult result;
      try {
        result = await install(url);
      } on FileSystemException {
        result = InstallFailed(
          AddonException(AddonFailureReason.storage, _storageMessage, url: url),
        );
      }
      reports.add(InstallReport(url, result));
    }
    return reports;
  }

  /// Quita el addon de [transportUrl] (se normaliza). `false` si no estaba.
  Future<bool> remove(String transportUrl) => _serialized(() async {
    final addon = _findByUrl(_tryNormalize(transportUrl));
    if (addon == null) return false;
    await _commit([
      for (final a in _addons)
        if (a != addon) a,
    ]);
    return true;
  });

  /// Mueve el addon de [oldIndex] a [newIndex], que es la posición final que
  /// queda en la lista. Lanza [RangeError] si algún índice está fuera de rango.
  Future<void> reorder(int oldIndex, int newIndex) => _serialized(() async {
    RangeError.checkValidIndex(oldIndex, _addons);
    RangeError.checkValidIndex(newIndex, _addons);
    if (oldIndex == newIndex) return;
    final next = [..._addons];
    next.insert(newIndex, next.removeAt(oldIndex));
    await _commit(next);
  });

  /// Cierra el stream de [changes].
  Future<void> dispose() => _changes.close();

  Future<InstallResult> _add(InstalledAddon addon) => _serialized(() async {
    final existing =
        _findByUrl(addon.transportUrl) ?? _findById(addon.manifest.id);
    if (existing != null) return AlreadyInstalled(existing);
    await _commit([..._addons, addon]);
    return Installed(addon);
  });

  /// Corre los cambios de a uno, en el orden en que se piden.
  Future<T> _serialized<T>(Future<T> Function() change) {
    final run = _lastChange.then((_) => change());
    _lastChange = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  InstalledAddon? _findByUrl(String transportUrl) {
    for (final a in _addons) {
      if (a.transportUrl == transportUrl) return a;
    }
    return null;
  }

  InstalledAddon? _findById(String id) {
    for (final a in _addons) {
      if (a.manifest.id == id) return a;
    }
    return null;
  }

  String _tryNormalize(String url) {
    try {
      return normalizeManifestUrl(url);
    } on FormatException {
      return url;
    }
  }

  /// Guarda [next] y recién después lo deja en memoria y avisa. Si guardar
  /// falla, no cambia nada.
  Future<void> _commit(List<InstalledAddon> next) async {
    await _store.write({
      'version': 1,
      'addons': [for (final a in next) a.toJson()],
    });
    _addons
      ..clear()
      ..addAll(next);
    if (!_changes.isClosed) _changes.add(addons);
  }
}

const String _storageMessage = 'No se pudo guardar en disco';
