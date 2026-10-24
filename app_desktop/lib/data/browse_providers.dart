import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import 'providers.dart';

/// Un catálogo a pedir; [search] lleva el texto cuando es una búsqueda.
typedef CatalogKey = ({CatalogRef catalog, String? search});

/// Items de un catálogo. Los de la home se quedan en memoria mientras corre la
/// app (volver al inicio no recarga); los de una búsqueda se sueltan al salir.
final catalogItemsProvider = FutureProvider.autoDispose
    .family<AddonResult<List<Meta>>, CatalogKey>((ref, key) {
      if (key.search == null) ref.keepAlive();
      final search = key.search;
      return ref
          .watch(addonAggregatorProvider)
          .fetchCatalog(
            key.catalog,
            extra: search == null ? const {} : {'search': search},
          );
    });

/// Qué meta pedir.
typedef MetaKey = ({String type, String id});

/// Meta completa del primer addon que la tenga; `null` si ninguno la ofrece.
final metaProvider = FutureProvider.autoDispose
    .family<AddonResult<Meta>?, MetaKey>(
      (ref, key) => ref.watch(addonAggregatorProvider).meta(key.type, key.id),
    );

/// Qué video pedirle a los addons de streams (el id del episodio, o el de la
/// película).
typedef StreamsKey = ({String type, String videoId});

/// Los streams de un addon, o lo que falta para tenerlos.
class StreamGroup {
  const StreamGroup(this.addon, [this.result]);

  final InstalledAddon addon;

  /// `null` mientras el addon todavía no respondió.
  final AddonResult<List<AddonStream>>? result;

  bool get loading => result == null;
}

/// Los grupos de streams, uno por addon que soporta el video, en el orden de
/// los addons.
class StreamsState {
  const StreamsState(this.groups);

  final List<StreamGroup> groups;

  bool get loading => groups.any((g) => g.loading);
}

/// Pide los streams a cada addon por separado y va emitiendo a medida que
/// responden, así la lista se llena sin esperar al más lento.
final streamsProvider = StreamProvider.autoDispose
    .family<StreamsState, StreamsKey>((ref, key) {
      final client = ref.watch(addonClientProvider);
      final addons = [
        for (final addon in ref.read(addonRepositoryProvider).addons)
          if (addon.manifest.supports('stream', key.type, key.videoId)) addon,
      ];
      final controller = StreamController<StreamsState>();
      ref.onDispose(controller.close);

      final groups = [for (final addon in addons) StreamGroup(addon)];
      controller.add(StreamsState(List.unmodifiable(groups)));
      var pending = addons.length;
      if (pending == 0) unawaited(controller.close());

      for (var i = 0; i < addons.length; i++) {
        // Un agregador de un solo addon reusa el timeout y el manejo de fallas.
        final single = AddonAggregator(
          client: client,
          addons: () => [addons[i]],
        );
        unawaited(
          single.streams(key.type, key.videoId).then((results) {
            if (controller.isClosed) return;
            groups[i] = StreamGroup(addons[i], results.first);
            controller.add(StreamsState(List.unmodifiable(groups)));
            if (--pending == 0) unawaited(controller.close());
          }),
        );
      }
      return controller.stream;
    });
