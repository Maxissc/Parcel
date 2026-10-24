import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../data/browse_providers.dart';
import '../../data/playback_providers.dart';

/// Lo que TMDB suma a una meta: fotos del elenco e idioma original.
class TmdbEnrichment {
  const TmdbEnrichment({required this.cast, this.originalLanguage});

  final List<CastMember> cast;
  final String? originalLanguage;
}

/// Pide a TMDB el elenco y el idioma original de un título de IMDb, en segundo
/// plano. `null` si no hay key, no es un id de IMDb, TMDB no lo conoce o algo
/// falla: el detalle sigue con lo que ya tiene. La key nunca sale de acá.
final tmdbEnrichmentProvider = FutureProvider.autoDispose
    .family<TmdbEnrichment?, MetaKey>((ref, key) async {
      final client = ref.watch(tmdbClientProvider);
      if (client == null || !key.id.startsWith('tt')) return null;
      try {
        final match = await client.findByImdb(key.id);
        if (match == null) return null;
        final cast = await client.credits(match.id, match.type);
        return TmdbEnrichment(
          cast: cast,
          originalLanguage: match.originalLanguage,
        );
      } on Object {
        return null;
      }
    });

/// Mezcla el elenco del addon con el de TMDB: sobre el mismo nombre queda el
/// que tiene foto (gana el del addon si los dos la tienen). Primero van los de
/// TMDB, en su orden, y después los del addon que TMDB no trae.
List<CastMember> mergeCastDetails(
  List<CastMember> fromAddon,
  List<CastMember> fromTmdb,
) {
  String key(String name) => name.trim().toLowerCase();
  final addon = {for (final m in fromAddon) key(m.name): m};
  final result = <CastMember>[];
  final seen = <String>{};
  for (final t in fromTmdb) {
    final k = key(t.name);
    if (!seen.add(k)) continue;
    final a = addon[k];
    result.add(a != null && a.photoUrl != null ? a : t);
  }
  for (final a in fromAddon) {
    if (seen.add(key(a.name))) result.add(a);
  }
  return List.unmodifiable(result);
}
