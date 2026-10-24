import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Idiomas que se pueden elegir como preferidos, con el código de 3 letras que
/// entiende `languagesMatch` del core.
const List<({String code, String label})> preferredLanguageOptions = [
  (code: 'spa', label: 'Español'),
  (code: 'eng', label: 'Inglés'),
  (code: 'por', label: 'Portugués'),
];

const Object _keep = Object();

/// Ajustes de la app que se guardan en disco.
class AppSettings {
  const AppSettings({
    this.onboardingCompleted = false,
    this.audioLanguage,
    this.subtitleLanguage,
  });

  /// El usuario ya terminó el asistente de migración.
  final bool onboardingCompleted;

  /// Idioma preferido del audio; `null` es «sin preferencia».
  final String? audioLanguage;

  /// Idioma preferido de los subtítulos; `null` es «sin preferencia».
  final String? subtitleLanguage;

  /// Copia con cambios. Los idiomas aceptan `null` para quitar la preferencia.
  AppSettings copyWith({
    bool? onboardingCompleted,
    Object? audioLanguage = _keep,
    Object? subtitleLanguage = _keep,
  }) {
    return AppSettings(
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      audioLanguage: identical(audioLanguage, _keep)
          ? this.audioLanguage
          : audioLanguage as String?,
      subtitleLanguage: identical(subtitleLanguage, _keep)
          ? this.subtitleLanguage
          : subtitleLanguage as String?,
    );
  }

  /// Lee los ajustes; lo que falta o no tiene el tipo esperado queda por
  /// defecto.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    String? language(Object? value) =>
        value is String && value.trim().isNotEmpty ? value : null;
    return AppSettings(
      onboardingCompleted: json['onboardingCompleted'] == true,
      audioLanguage: language(json['audioLanguage']),
      subtitleLanguage: language(json['subtitleLanguage']),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'onboardingCompleted': onboardingCompleted,
    'audioLanguage': audioLanguage,
    'subtitleLanguage': subtitleLanguage,
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.onboardingCompleted == onboardingCompleted &&
      other.audioLanguage == audioLanguage &&
      other.subtitleLanguage == subtitleLanguage;

  @override
  int get hashCode =>
      Object.hash(onboardingCompleted, audioLanguage, subtitleLanguage);
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

  Future<void> _write(String text) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temp = File('$path.tmp');
    await temp.writeAsString(text, flush: true);
    await temp.rename(path);
  }
}
