import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:path_provider/path_provider.dart';

import 'app_settings.dart';

const String _addonsFile = 'addons.json';
const String _progressFile = 'progress.json';
const String _settingsFile = 'settings.json';

/// Carpeta donde la app guarda sus datos.
///
/// En debug, `PARCEL_DATA_DIR` (si está) manda sobre todo lo demás: sirve para
/// probar con una carpeta vacía sin tocar los datos reales. Si no, es
/// `Parcel` dentro de la carpeta de soporte de la aplicación.
Future<Directory> resolveDataDirectory({
  Map<String, String>? environment,
  Future<Directory> Function() supportDirectory =
      getApplicationSupportDirectory,
  bool? debug,
}) async {
  if (debug ?? kDebugMode) {
    final override = (environment ?? Platform.environment)['PARCEL_DATA_DIR'];
    if (override != null && override.trim().isNotEmpty) {
      return Directory(override.trim());
    }
  }
  final support = await supportDirectory();
  return Directory('${support.path}${Platform.pathSeparator}Parcel');
}

/// Los repositorios y ajustes abiertos sobre una carpeta de datos.
class AppData {
  AppData({
    required this.directory,
    required this.addons,
    required this.progress,
    required this.settings,
  });

  final Directory directory;
  final AddonRepository addons;
  final ProgressRepository progress;
  final SettingsStore settings;

  /// Abre (y crea si falta) la carpeta [directory] con todo lo que guarda la
  /// app.
  static Future<AppData> open(
    Directory directory, {
    required AddonClient client,
  }) async {
    await directory.create(recursive: true);
    String file(String name) =>
        '${directory.path}${Platform.pathSeparator}$name';
    return AppData(
      directory: directory,
      addons: await AddonRepository.open(
        client: client,
        filePath: file(_addonsFile),
      ),
      progress: await ProgressRepository.open(filePath: file(_progressFile)),
      settings: await SettingsStore.open(file(_settingsFile)),
    );
  }

  /// Borra los archivos de datos (con sus copias `.bak` y temporales). Después
  /// hay que volver a abrir [AppData]: lo que está en memoria no cambia.
  Future<void> deleteFiles() async {
    for (final name in [_addonsFile, _progressFile, _settingsFile]) {
      for (final suffix in ['', '.bak', '.tmp']) {
        final f = File(
          '${directory.path}${Platform.pathSeparator}$name$suffix',
        );
        if (await f.exists()) await f.delete();
      }
    }
  }

  Future<void> dispose() => addons.dispose();
}
