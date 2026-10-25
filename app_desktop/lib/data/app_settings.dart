import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:parcel_core/parcel_core.dart' show QualityPreference;

import 'home_layout.dart';

/// Código del audio «Original»: el idioma en que se hizo el contenido.
const String originalAudioCode = 'original';

/// Código de los subtítulos «Español (Latinoamérica)».
const String latamSubtitleCode = 'latam';

/// Idiomas que se pueden elegir como preferidos, con el código de 3 letras que
/// entiende `languagesMatch` del core.
const List<({String code, String label})> preferredLanguageOptions = [
  (code: 'spa', label: 'Español'),
  (code: 'eng', label: 'Inglés'),
  (code: 'por', label: 'Portugués'),
];

/// Opciones del idioma del audio: «Original» y los idiomas de siempre.
const List<({String code, String label})> audioLanguageOptions = [
  (code: originalAudioCode, label: 'Original'),
  ...preferredLanguageOptions,
];

/// Opciones del idioma de los subtítulos: español de Latinoamérica primero.
const List<({String code, String label})> subtitleLanguageOptions = [
  (code: latamSubtitleCode, label: 'Español (Latinoamérica)'),
  ...preferredLanguageOptions,
];

/// Versión del formato de `settings.json`. La 2 distingue «sin preferencia»
/// (elegido) de «nunca elegí»: en la 1 los dos eran `null`. La 3 suma el orden
/// de la home y «Pasar solo al siguiente episodio».
const int settingsVersion = 3;

const Object _keep = Object();

/// Ajustes de la app que se guardan en disco.
class AppSettings {
  const AppSettings({
    this.onboardingCompleted = false,
    this.audioLanguage = originalAudioCode,
    this.subtitleLanguage = latamSubtitleCode,
    this.autoSelectSource = true,
    this.quality = QualityPreference.p1080,
    this.openFullScreen = true,
    this.tmdbApiKey,
    this.homeLayout = const HomeLayout(),
    this.autoPlayNext = true,
  });

  /// El usuario ya terminó el asistente de migración.
  final bool onboardingCompleted;

  /// Idioma preferido del audio (`original` o un código); `null` es «sin
  /// preferencia».
  final String? audioLanguage;

  /// Idioma preferido de los subtítulos (`latam` o un código); `null` es «sin
  /// preferencia».
  final String? subtitleLanguage;

  /// Parcel elige sola la fuente al dar play.
  final bool autoSelectSource;

  /// Calidad que prefiere al elegir la fuente.
  final QualityPreference quality;

  /// El reproductor abre en pantalla completa.
  final bool openFullScreen;

  /// Key de TMDB (opcional); `null` si no puso ninguna.
  final String? tmdbApiKey;

  /// Orden de las filas de la home y cuáles están ocultas.
  final HomeLayout homeLayout;

  /// Al terminar un episodio, pasar solo al siguiente (con cuenta regresiva).
  final bool autoPlayNext;

  /// Copia con cambios. Los idiomas y la key aceptan `null` para quitarlos.
  AppSettings copyWith({
    bool? onboardingCompleted,
    Object? audioLanguage = _keep,
    Object? subtitleLanguage = _keep,
    bool? autoSelectSource,
    QualityPreference? quality,
    bool? openFullScreen,
    Object? tmdbApiKey = _keep,
    HomeLayout? homeLayout,
    bool? autoPlayNext,
  }) {
    return AppSettings(
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      audioLanguage: identical(audioLanguage, _keep)
          ? this.audioLanguage
          : audioLanguage as String?,
      subtitleLanguage: identical(subtitleLanguage, _keep)
          ? this.subtitleLanguage
          : subtitleLanguage as String?,
      autoSelectSource: autoSelectSource ?? this.autoSelectSource,
      quality: quality ?? this.quality,
      openFullScreen: openFullScreen ?? this.openFullScreen,
      tmdbApiKey: identical(tmdbApiKey, _keep)
          ? this.tmdbApiKey
          : tmdbApiKey as String?,
      homeLayout: homeLayout ?? this.homeLayout,
      autoPlayNext: autoPlayNext ?? this.autoPlayNext,
    );
  }

  /// Lee los ajustes; lo que falta o no tiene el tipo esperado queda por
  /// defecto.
  ///
  /// Migración: en la versión 1 «sin preferencia» y «nunca elegí» se guardaban
  /// igual (`null`); un `null` de esa versión pasa a los idiomas por defecto
  /// nuevos. Desde la versión 2, `null` es una elección y se respeta.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final version = json['version'] is int ? json['version'] as int : 1;
    String? language(String key, String fallback) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value;
      if (version >= 2 && json.containsKey(key) && value == null) return null;
      return fallback;
    }

    final tmdb = json['tmdbApiKey'];
    final quality = json['quality'];
    List<String> strings(String key) {
      final value = json[key];
      return value is List
          ? [
              for (final e in value)
                if (e is String) e,
            ]
          : const [];
    }

    return AppSettings(
      onboardingCompleted: json['onboardingCompleted'] == true,
      audioLanguage: language('audioLanguage', originalAudioCode),
      subtitleLanguage: language('subtitleLanguage', latamSubtitleCode),
      autoSelectSource: json['autoSelectSource'] != false,
      quality:
          QualityPreference.values.asNameMap()[quality] ??
          QualityPreference.p1080,
      openFullScreen: json['openFullScreen'] != false,
      tmdbApiKey: tmdb is String && tmdb.trim().isNotEmpty ? tmdb.trim() : null,
      homeLayout: HomeLayout(
        order: strings('homeOrder'),
        hidden: strings('homeHidden').toSet(),
      ),
      autoPlayNext: json['autoPlayNext'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': settingsVersion,
    'onboardingCompleted': onboardingCompleted,
    'audioLanguage': audioLanguage,
    'subtitleLanguage': subtitleLanguage,
    'autoSelectSource': autoSelectSource,
    'quality': quality.name,
    'openFullScreen': openFullScreen,
    'tmdbApiKey': tmdbApiKey,
    'homeOrder': homeLayout.order,
    'homeHidden': homeLayout.hidden.toList()..sort(),
    'autoPlayNext': autoPlayNext,
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.onboardingCompleted == onboardingCompleted &&
      other.audioLanguage == audioLanguage &&
      other.subtitleLanguage == subtitleLanguage &&
      other.autoSelectSource == autoSelectSource &&
      other.quality == quality &&
      other.openFullScreen == openFullScreen &&
      other.tmdbApiKey == tmdbApiKey &&
      other.homeLayout == homeLayout &&
      other.autoPlayNext == autoPlayNext;

  @override
  int get hashCode => Object.hash(
    onboardingCompleted,
    audioLanguage,
    subtitleLanguage,
    autoSelectSource,
    quality,
    openFullScreen,
    tmdbApiKey,
    homeLayout,
    autoPlayNext,
  );

  /// No incluye la key de TMDB.
  @override
  String toString() =>
      'AppSettings(audio=$audioLanguage subs=$subtitleLanguage '
      'auto=$autoSelectSource quality=${quality.name} '
      'fullscreen=$openFullScreen tmdb=${tmdbApiKey != null})';
}

/// Guarda [AppSettings] en un archivo JSON con escritura atómica (archivo
/// temporal + rename), una a la vez y en orden.
class SettingsStore {
  SettingsStore._(this.path, this.value);

  final String path;

  /// Últimos ajustes guardados (o leídos al abrir).
  AppSettings value;

  Future<void> _lastWrite = Future.value();

  /// Abre el archivo [path]. Si no existe arranca con los ajustes por defecto;
  /// si está corrupto, lo deja como `<path>.bak` y arranca por defecto.
  static Future<SettingsStore> open(String path) async {
    final file = File(path);
    var settings = const AppSettings();
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          settings = AppSettings.fromJson(decoded);
        } else {
          await file.rename('$path.bak');
        }
      } on FormatException {
        await file.rename('$path.bak');
      }
    }
    return SettingsStore._(path, settings);
  }

  /// Guarda [settings] y los deja como [value].
  Future<void> save(AppSettings settings) {
    value = settings;
    final text = jsonEncode(settings.toJson());
    final run = _lastWrite.then((_) => _write(text));
    _lastWrite = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// Espera a que terminen las escrituras que ya se pidieron.
  Future<void> flush() => _lastWrite;

  Future<void> _write(String text) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temp = File('$path.tmp');
    await temp.writeAsString(text, flush: true);
    await temp.rename(path);
  }
}
