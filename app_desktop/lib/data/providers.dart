import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:parcel_core/parcel_core.dart';

import 'app_data.dart';
import 'app_settings.dart';
import 'home_layout.dart';

// --- Red ---------------------------------------------------------------------

/// Único cliente HTTP de la app. Se cierra cuando se destruye el contenedor
/// (o al salir, ver `ParcelApp`).
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final addonClientProvider = Provider<AddonClient>(
  (ref) => AddonClient(ref.watch(httpClientProvider)),
);

final stremioAccountClientProvider = Provider<StremioAccountClient>(
  (ref) => StremioAccountClient(ref.watch(httpClientProvider)),
);

final nuvioAccountClientProvider = Provider<NuvioAccountClient>(
  (ref) => NuvioAccountClient(ref.watch(httpClientProvider)),
);

// --- Datos en disco ----------------------------------------------------------

/// Carpeta de datos (ver [resolveDataDirectory]).
final dataDirectoryProvider = FutureProvider<Directory>(
  (ref) => resolveDataDirectory(),
);

/// Repositorios y ajustes abiertos. La app no muestra nada más que una pantalla
/// de carga hasta que esto termina.
final appDataProvider = FutureProvider<AppData>((ref) async {
  final directory = await ref.watch(dataDirectoryProvider.future);
  final data = await AppData.open(
    directory,
    client: ref.watch(addonClientProvider),
  );
  ref.onDispose(() => unawaited(data.dispose()));
  return data;
});

// Los que siguen solo se leen con la app ya cargada (después de [appDataProvider]).

final addonRepositoryProvider = Provider<AddonRepository>(
  (ref) => ref.watch(appDataProvider).requireValue.addons,
);

final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) => ref.watch(appDataProvider).requireValue.progress,
);

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => ref.watch(appDataProvider).requireValue.settings,
);

/// Agregador sobre los addons instalados (lo usan Inicio y Buscar).
final addonAggregatorProvider = Provider<AddonAggregator>((ref) {
  final repository = ref.watch(addonRepositoryProvider);
  return AddonAggregator(
    client: ref.watch(addonClientProvider),
    addons: () => repository.addons,
  );
});

final migrationServiceProvider = Provider<MigrationService>(
  (ref) => MigrationService(ref.watch(addonRepositoryProvider)),
);

// --- Estado observable -------------------------------------------------------

/// Addons instalados, en orden de prioridad. Se actualiza solo cuando el
/// repositorio cambia.
final installedAddonsProvider =
    NotifierProvider<InstalledAddonsNotifier, List<InstalledAddon>>(
      InstalledAddonsNotifier.new,
    );

class InstalledAddonsNotifier extends Notifier<List<InstalledAddon>> {
  AddonRepository get _repository => ref.read(addonRepositoryProvider);

  @override
  List<InstalledAddon> build() {
    final repository = ref.watch(addonRepositoryProvider);
    final sub = repository.changes.listen((addons) => state = addons);
    ref.onDispose(sub.cancel);
    return repository.addons;
  }

  /// El repositorio avisa por su stream, que llega un instante después de que
  /// termina la operación: se copia la lista al volver para que quien espera
  /// la operación ya vea el estado nuevo.
  void _sync() {
    if (ref.mounted) state = _repository.addons;
  }

  /// Instala el addon de [url] al final de la lista.
  Future<InstallResult> installUrl(String url) async {
    final result = await _repository.install(url);
    _sync();
    return result;
  }

  /// Quita [addon]. Devuelve la posición que tenía, para poder deshacer.
  Future<int> remove(InstalledAddon addon) async {
    final index = state.indexOf(addon);
    await _repository.remove(addon.transportUrl);
    _sync();
    return index;
  }

  /// Vuelve a poner [addon] en [index], sin bajar su manifest de nuevo.
  Future<void> restore(InstalledAddon addon, int index) async {
    final result = await _repository.installManifest(
      addon.transportUrl,
      addon.manifest.toJson(),
    );
    if (result is! Installed) return;
    final last = _repository.addons.length - 1;
    final target = index.clamp(0, last);
    if (target != last) await _repository.reorder(last, target);
    _sync();
  }

  /// Mueve el addon de [oldIndex] a [newIndex] (la posición final).
  Future<void> move(int oldIndex, int newIndex) async {
    await _repository.reorder(oldIndex, newIndex);
    _sync();
  }
}

/// Ajustes de la app (idiomas, asistente completado).
final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

class AppSettingsNotifier extends Notifier<AppSettings> {
  SettingsStore get _store => ref.read(settingsStoreProvider);

  @override
  AppSettings build() => ref.watch(settingsStoreProvider).value;

  /// Cambia los ajustes en memoria y los guarda. Si no se puede guardar, vuelve
  /// a los anteriores (para que la pantalla no muestre algo que no quedó) y
  /// lanza el error.
  Future<void> _update(AppSettings next) async {
    final previous = state;
    final store = _store;
    state = next;
    try {
      await store.save(next);
    } on Object {
      store.value = previous;
      if (ref.mounted) state = previous;
      rethrow;
    }
  }

  Future<void> completeOnboarding() =>
      _update(state.copyWith(onboardingCompleted: true));

  Future<void> resetOnboarding() =>
      _update(state.copyWith(onboardingCompleted: false));

  /// `null` es «sin preferencia».
  Future<void> setAudioLanguage(String? code) =>
      _update(state.copyWith(audioLanguage: code));

  Future<void> setSubtitleLanguage(String? code) =>
      _update(state.copyWith(subtitleLanguage: code));

  Future<void> setAutoSelectSource(bool value) =>
      _update(state.copyWith(autoSelectSource: value));

  Future<void> setQuality(QualityPreference value) =>
      _update(state.copyWith(quality: value));

  Future<void> setOpenFullScreen(bool value) =>
      _update(state.copyWith(openFullScreen: value));

  Future<void> setAutoPlayNext(bool value) =>
      _update(state.copyWith(autoPlayNext: value));

  Future<void> setHomeLayout(HomeLayout layout) =>
      _update(state.copyWith(homeLayout: layout));

  /// Una key vacía la quita.
  Future<void> setTmdbApiKey(String? key) {
    final trimmed = key?.trim();
    return _update(
      state.copyWith(
        tmdbApiKey: trimmed == null || trimmed.isEmpty ? null : trimmed,
      ),
    );
  }
}

/// Borra todos los datos y vuelve a abrir la app como la primera vez.
final dataResetProvider = Provider<DataReset>(DataReset.new);

class DataReset {
  DataReset(this._ref);

  final Ref _ref;

  /// Borra los archivos y recarga todo desde cero. La app vuelve a mostrar la
  /// pantalla de carga y después el asistente.
  Future<void> wipe() async {
    final data = await _ref.read(appDataProvider.future);
    // Lo que se está guardando termina antes; si no, podría reaparecer un
    // archivo recién borrado.
    await data.flush();
    await data.deleteFiles();
    _ref.invalidate(appDataProvider);
  }
}
