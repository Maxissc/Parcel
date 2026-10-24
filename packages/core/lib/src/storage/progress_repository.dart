import '../models/json_helpers.dart';
import '../models/playback_progress.dart';
import 'json_file_store.dart';

typedef _Key = (String type, String metaId, String videoId);

/// Progreso de reproducción («seguir viendo») persistido en un archivo JSON.
class ProgressRepository {
  ProgressRepository._(this._store, this._items);

  final JsonFileStore _store;
  final Map<_Key, PlaybackProgress> _items;

  /// Abre el repositorio leyendo [filePath]. Si no existe arranca vacío; si
  /// está corrupto arranca vacío y lo deja como `<filePath>.bak`.
  static Future<ProgressRepository> open({required String filePath}) async {
    final store = JsonFileStore(filePath);
    final json = await store.readObject();
    final items = <_Key, PlaybackProgress>{};
    if (json != null) {
      final raw = json['items'];
      if (raw is List) {
        for (final p in parseList(raw, PlaybackProgress.fromJson)) {
          items[(p.type, p.metaId, p.videoId)] = p;
        }
      } else {
        await store.backupCorrupt();
      }
    }
    return ProgressRepository._(store, items);
  }

  /// Progreso guardado de un video, o `null`.
  PlaybackProgress? get(String type, String metaId, String videoId) =>
      _items[(type, metaId, videoId)];

  /// Guarda [progress], reemplazando el de la misma `(type, metaId, videoId)`.
  Future<void> save(PlaybackProgress progress) {
    _items[(progress.type, progress.metaId, progress.videoId)] = progress;
    return _store.write({
      'version': 1,
      'items': [for (final p in _items.values) p.toJson()],
    });
  }

  /// Lo que se está viendo, del más reciente al más viejo.
  ///
  /// Primero filtra los videos en curso (3 % a 92 % visto) y después toma el
  /// más reciente de cada meta. Así, ver el episodio 1 al 50 % y abrir el 2
  /// y cerrarlo al 1 % deja la serie con el episodio 1. Si ningún video de la
  /// serie está en curso, no aparece.
  List<PlaybackProgress> inProgress() {
    final latest = <(String, String), PlaybackProgress>{};
    for (final p in _items.values) {
      if (!p.isInProgress) continue;
      final key = (p.type, p.metaId);
      final current = latest[key];
      if (current == null || p.updatedAt.isAfter(current.updatedAt)) {
        latest[key] = p;
      }
    }
    return latest.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
}
