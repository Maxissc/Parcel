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
  return ProgressSaver(repository, revision.bump);
});

class ProgressSaver {
  ProgressSaver(this._repository, this._changed);

  final ProgressRepository _repository;
  final void Function() _changed;

  /// Guarda [progress]. La memoria se actualiza al instante; el archivo, un
  /// rato después (el futuro devuelto espera a la escritura).
  Future<void> save(PlaybackProgress progress) {
    final written = _repository.save(progress);
    // Se avisa fuera del ciclo de vida de los widgets: guardar suele pasar al
    // cerrar el reproductor y Riverpod no deja tocar proveedores ahí.
    scheduleMicrotask(_changed);
    return written;
  }
}
