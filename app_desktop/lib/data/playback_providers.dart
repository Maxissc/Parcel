import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../app/diagnostics/diag_log.dart';
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

/// Baja los subtítulos de los addons para analizarlos.
final subtitleFetcherProvider = Provider<SubtitleFetcher>(
  (ref) => SubtitleFetcher(ref.watch(httpClientProvider)),
);

/// Cliente de TMDB con la key de Ajustes, o `null` si no hay key.
final tmdbClientProvider = Provider<TmdbClient?>((ref) {
  final key = ref.watch(appSettingsProvider.select((s) => s.tmdbApiKey));
  if (key == null || key.trim().isEmpty) return null;
  return TmdbClient(ref.watch(httpClientProvider), apiKey: key);
});

/// Retraso de subtítulos que el usuario fijó por contenido (`tipo:id del
/// video`), mientras la app esté abierta.
final subtitleDelaysProvider = Provider<Map<String, Duration>>((ref) => {});
