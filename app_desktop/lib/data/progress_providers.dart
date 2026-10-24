import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import 'providers.dart';

/// Identifica un video dentro del progreso guardado.
typedef VideoKey = ({String type, String metaId, String videoId});

/// Cuenta cuántas veces cambió el progreso. El repositorio no avisa de sus
/// cambios, así que quien guarda sube este número y las pantallas que miran
/// el progreso se redibujan.
final progressRevisionProvider = NotifierProvider<ProgressRevision, int>(
  ProgressRevision.new,
);

class ProgressRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    // El aviso llega en un microtask: la app pudo cerrarse antes.
    if (ref.mounted) state++;
  }
}

/// Lo que se está viendo («Seguir viendo»), del más reciente al más viejo.
final continueWatchingProvider = Provider<List<PlaybackProgress>>((ref) {
  ref.watch(progressRevisionProvider);
  return ref.watch(progressRepositoryProvider).inProgress();
});

/// Progreso guardado de un video, o `null`.
final videoProgressProvider = Provider.family<PlaybackProgress?, VideoKey>((
  ref,
  key,
) {
  ref.watch(progressRevisionProvider);
  return ref
      .watch(progressRepositoryProvider)
      .get(key.type, key.metaId, key.videoId);
});

/// Guarda el progreso y avisa a las pantallas que lo muestran.
final progressSaverProvider = Provider<ProgressSaver>((ref) {
  final repository = ref.watch(progressRepositoryProvider);
  final revision = ref.read(progressRevisionProvider.notifier);
  final data = ref.watch(appDataProvider).requireValue;
  return ProgressSaver(repository, revision.bump, track: data.track);
});

/// El reproductor que está abierto, si hay uno: deja que la app le pida guardar
/// el progreso ahora (por ejemplo, al cerrar la ventana).
final activePlayerProvider = Provider<ActivePlayer>((ref) => ActivePlayer());

class ActivePlayer {
  void Function()? _saveNow;

  void register(void Function() saveNow) => _saveNow = saveNow;

  void unregister(void Function() saveNow) {
    if (_saveNow == saveNow) _saveNow = null;
  }

  /// Guarda la posición actual del reproductor abierto; no hace nada si no hay.
  void saveNow() => _saveNow?.call();
}

class ProgressSaver {
  ProgressSaver(
    this._repository,
    this._changed, {
    Future<void> Function(Future<void>)? track,
  }) : _track = track ?? ((write) => write);

  final ProgressRepository _repository;
  final void Function() _changed;
  final Future<void> Function(Future<void> write) _track;

  /// Guarda [progress]. La memoria se actualiza al instante; el archivo, un
  /// rato después (el futuro devuelto espera a la escritura).
  Future<void> save(PlaybackProgress progress) {
    final written = _track(_repository.save(progress));
    // Se avisa fuera del ciclo de vida de los widgets: guardar suele pasar al
    // cerrar el reproductor y Riverpod no deja tocar proveedores ahí.
    scheduleMicrotask(_changed);
    return written;
  }
}
