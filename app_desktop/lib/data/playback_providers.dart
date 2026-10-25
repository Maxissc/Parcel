import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../app/diagnostics/diag_log.dart';
import 'cancellable_client.dart';
import 'providers.dart';

/// Prueba si un stream responde antes de dárselo al reproductor. En el modo de
/// diagnóstico se puede bajar el tamaño mínimo (`PARCEL_DIAG_MIN_PROBE_BYTES`),
/// para probar con videos de muestra chicos.
final streamProberProvider = Provider<StreamProber>((ref) {
  final min = ref.watch(diagnosticsConfigProvider)?.probeMinBytes;
  final client = ref.watch(httpClientProvider);
  return min == null
      ? StreamProber(client)
      : StreamProber(client, minBytes: min);
});

/// Elige solo el stream que se reproduce.
final autoStreamSelectorProvider = Provider<AutoStreamSelector>(
  (ref) => AutoStreamSelector(ref.watch(streamProberProvider)),
);

/// Arma el que baja los subtítulos de los addons para analizarlos. Cuando
/// termina `cancel` (se salió del contenido) aborta los pedidos en curso.
typedef SubtitleFetcherFactory = SubtitleFetcher Function(Future<void> cancel);

final subtitleFetcherFactoryProvider = Provider<SubtitleFetcherFactory>((ref) {
  final client = ref.watch(httpClientProvider);
  return (cancel) => SubtitleFetcher(CancellableClient(client, cancel: cancel));
});

/// Arma el cliente de TMDB con la key de Ajustes, o `null` si no hay key.
/// Cuando termina `cancel` (se salió de la pantalla que pidió) se abortan los
/// pedidos en curso.
typedef TmdbClientFactory = TmdbClient? Function(Future<void> cancel);

final tmdbClientFactoryProvider = Provider<TmdbClientFactory>((ref) {
  final key = ref.watch(appSettingsProvider.select((s) => s.tmdbApiKey));
  final client = ref.watch(httpClientProvider);
  return (cancel) {
    if (key == null || key.trim().isEmpty) return null;
    return TmdbClient(CancellableClient(client, cancel: cancel), apiKey: key);
  };
});

/// Retraso de subtítulos que el usuario fijó por contenido (`tipo:id del
/// video`), mientras la app esté abierta.
final subtitleDelaysProvider = Provider<Map<String, Duration>>((ref) => {});
