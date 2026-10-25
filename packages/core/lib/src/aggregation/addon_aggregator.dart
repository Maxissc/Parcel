import 'dart:async';

import '../models/addon_manifest.dart';
import '../models/addon_stream.dart';
import '../models/installed_addon.dart';
import '../models/meta.dart';
import '../models/subtitle.dart';
import '../protocol/abortable_http.dart';
import '../protocol/addon_client.dart';
import '../protocol/addon_exception.dart';
import 'addon_result.dart';

/// Un catálogo de un addon concreto.
class CatalogRef {
  const CatalogRef(this.addon, this.catalog);

  final InstalledAddon addon;
  final AddonCatalog catalog;

  @override
  bool operator ==(Object other) =>
      other is CatalogRef &&
      other.addon == addon &&
      other.catalog.type == catalog.type &&
      other.catalog.id == catalog.id;

  @override
  int get hashCode => Object.hash(addon, catalog.type, catalog.id);
}

/// Junta lo que responden varios addons, con timeout por addon.
///
/// Un addon caído o lento nunca tumba al resto: sale como [AddonFailure].
class AddonAggregator {
  AddonAggregator({
    required this.client,
    required this.addons,
    this.timeout = const Duration(seconds: 15),
  });

  final AddonClient client;

  /// Addons instalados, en orden de prioridad. Se lee en cada pedido.
  final List<InstalledAddon> Function() addons;

  /// Tiempo máximo de espera por cada addon.
  final Duration timeout;

  /// Catálogos de la home: los de todos los addons sin extras obligatorios, en
  /// el orden de los addons.
  List<CatalogRef> homeCatalogs() => _catalogs((c) => !c.hasRequiredExtra);

  /// Catálogos que aceptan el extra `search`.
  List<CatalogRef> searchCatalogs() =>
      _catalogs((c) => c.acceptsExtra('search'));

  List<CatalogRef> _catalogs(bool Function(AddonCatalog) test) => [
    for (final addon in addons())
      for (final catalog in addon.manifest.catalogs)
        if (test(catalog)) CatalogRef(addon, catalog),
  ];

  /// Items de un catálogo. [extra] lleva `search`, `genre`, `skip`...
  Future<AddonResult<List<Meta>>> fetchCatalog(
    CatalogRef ref, {
    Map<String, String> extra = const {},
  }) => _guard(
    ref.addon,
    (abort) => client.catalog(
      ref.addon,
      ref.catalog.type,
      ref.catalog.id,
      extra: extra,
      abortTrigger: abort,
    ),
  );

  /// Meta del primer addon (en orden) que soporte `meta` para [id] y responda
  /// bien. Si ninguno responde bien, devuelve la falla del primero que lo
  /// intentó; si ninguno lo soporta, `null`.
  Future<AddonResult<Meta>?> meta(String type, String id) async {
    AddonResult<Meta>? firstFailure;
    for (final addon in _supporting('meta', type, id)) {
      final result = await _guard(
        addon,
        (abort) => client.meta(addon, type, id, abortTrigger: abort),
      );
      if (result is AddonSuccess<Meta>) return result;
      firstFailure ??= result;
    }
    return firstFailure;
  }

  /// Streams de todos los addons que soportan `stream` para [type] e [id]
  /// (el id del video, por ejemplo `tt123:1:2`). Un resultado por addon, en el
  /// orden de los addons.
  Future<List<AddonResult<List<AddonStream>>>> streams(
    String type,
    String id, {
    Map<String, String> extra = const {},
  }) => _fanOut(
    'stream',
    type,
    id,
    (addon, abort) =>
        client.streams(addon, type, id, extra: extra, abortTrigger: abort),
  );

  /// Subtítulos de todos los addons que soportan `subtitles`. [extra] lleva
  /// `videoHash`, `videoSize` y `filename` cuando se conocen.
  Future<List<AddonResult<List<Subtitle>>>> subtitles(
    String type,
    String id, {
    Map<String, String> extra = const {},
  }) => _fanOut(
    'subtitles',
    type,
    id,
    (addon, abort) =>
        client.subtitles(addon, type, id, extra: extra, abortTrigger: abort),
  );

  List<InstalledAddon> _supporting(String resource, String type, String id) => [
    for (final addon in addons())
      if (addon.manifest.supports(resource, type, id)) addon,
  ];

  Future<List<AddonResult<T>>> _fanOut<T>(
    String resource,
    String type,
    String id,
    Future<T> Function(InstalledAddon, Future<void> abortTrigger) request,
  ) => Future.wait([
    for (final addon in _supporting(resource, type, id))
      _guard(addon, (abort) => request(addon, abort)),
  ]);

  /// Corre [request] con el plazo [timeout]; al vencer, aborta el pedido.
  Future<AddonResult<T>> _guard<T>(
    InstalledAddon addon,
    Future<T> Function(Future<void> abortTrigger) request,
  ) async {
    try {
      return AddonSuccess(addon, await runWithTimeoutAbort(timeout, request));
    } on AddonException catch (e) {
      return AddonFailure(addon, e);
    } on TimeoutException {
      return AddonFailure(
        addon,
        AddonException(
          AddonFailureReason.timeout,
          'Sin respuesta en ${timeout.inMilliseconds} ms',
          url: addon.transportUrl,
        ),
      );
    } catch (_) {
      // Cualquier otra cosa (un TypeError al leer una respuesta rara, por
      // ejemplo) es culpa de ese addon: no tumba a los demás. El texto del
      // error no se copia porque puede traer la URL.
      return AddonFailure(
        addon,
        AddonException(
          AddonFailureReason.parse,
          'Respuesta inesperada del addon',
          url: addon.transportUrl,
        ),
      );
    }
  }
}
