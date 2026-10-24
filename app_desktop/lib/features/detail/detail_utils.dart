import 'package:parcel_core/parcel_core.dart' hide Video;
import 'package:parcel_core/parcel_core.dart' as core show Video;

/// `true` si [meta] se muestra como serie: trae episodios y no es una película.
bool hasEpisodes(Meta meta) => meta.type != 'movie' && meta.videos.isNotEmpty;

/// Temporada de un episodio; los que no la traen cuentan como la 1.
int seasonOf(core.Video video) => video.season ?? 1;

/// Las temporadas de [meta] en orden, con la 0 (especiales) al final.
List<int> seasonsOf(Meta meta) {
  final seasons = {for (final v in meta.videos) seasonOf(v)}.toList()
    ..sort((a, b) {
      if (a == 0) return b == 0 ? 0 : 1;
      if (b == 0) return -1;
      return a.compareTo(b);
    });
  return seasons;
}

/// Nombre de una temporada para mostrar.
String seasonName(int season) =>
    season == 0 ? 'Especiales' : 'Temporada $season';

/// Los episodios de [season], por número.
List<core.Video> episodesOf(Meta meta, int season) => [
  for (final v in meta.videos)
    if (seasonOf(v) == season) v,
]..sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));

/// De qué temporada abrir la lista: la del último episodio visto; si no hay,
/// la primera que no sea de especiales; si solo hay especiales, la 0. `null`
/// si no hay episodios.
int? defaultSeason(Meta meta, PlaybackProgress? lastWatched) {
  final seasons = seasonsOf(meta);
  if (seasons.isEmpty) return null;
  if (lastWatched != null) {
    for (final v in meta.videos) {
      if (v.id == lastWatched.videoId) return seasonOf(v);
    }
  }
  return seasons.firstWhere((s) => s != 0, orElse: () => seasons.first);
}

/// El progreso más reciente entre los episodios de [meta] (aunque ya esté
/// terminado), o `null` si no se vio ninguno.
PlaybackProgress? lastWatched(
  Meta meta,
  PlaybackProgress? Function(String videoId) progressOf,
) {
  PlaybackProgress? best;
  for (final v in meta.videos) {
    final p = progressOf(v.id);
    if (p != null && (best == null || p.updatedAt.isAfter(best.updatedAt))) {
      best = p;
    }
  }
  return best;
}

/// «24/10/2026».
String formatDate(DateTime date) {
  final d = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}
