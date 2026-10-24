import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../data/app_settings.dart';
import '../../shared/urls.dart';
import 'track_labels.dart';
import 'track_preferences.dart';

/// Prioridad de idiomas para un idioma preferido de Ajustes (`latam`, `spa`,
/// `eng`...). `null` si es un idioma que el core no agrupa (por ejemplo
/// portugués) o no hay preferencia.
List<SubtitleLanguage>? subtitlePriorityFor(String? preferred) {
  return switch (preferred) {
    latamSubtitleCode => SubtitleLanguage.defaultPriority,
    'spa' => const [
      SubtitleLanguage.spanish,
      SubtitleLanguage.latam,
      SubtitleLanguage.english,
    ],
    'eng' => const [SubtitleLanguage.english],
    _ => null,
  };
}

/// Una opción del menú de subtítulos: una pista del archivo o un subtítulo de
/// un addon (que se baja y se carga recién cuando el usuario lo elige).
class SubtitleEntry {
  SubtitleEntry._({
    required this.id,
    required this.subtitle,
    required this.language,
    required this.label,
    this.embedded,
    this.external = false,
  });

  /// Único dentro del catálogo.
  final String id;

  /// El subtítulo con el que se ordena (el externo tal cual, o uno armado con
  /// los datos de la pista embebida).
  final Subtitle subtitle;
  final SubtitleLanguage language;
  final String label;

  /// La pista del archivo, si es embebido.
  final SubtitleTrack? embedded;

  /// `true` si viene de un addon.
  final bool external;

  /// Los cues, cuando ya se bajó y analizó (solo externos).
  List<SubtitleCue>? cues;

  /// Si el análisis falló (no se pudo bajar o no tiene cues).
  bool analysisFailed = false;

  bool get isEmbedded => embedded != null;
}

/// Qué le pasa a [SubtitleEntry] según su alineación, en palabras.
String? alignmentLabel(SubtitleAlignment? alignment) => switch (alignment) {
  SubtitleAlignment.likely => 'Probablemente sincronizado',
  SubtitleAlignment.fpsMismatch => 'Otra velocidad (fps)',
  SubtitleAlignment.unlikely => 'Puede estar desfasado',
  _ => null,
};

/// Subtítulos de los addons de un video: los ordena con `rankSubtitles`, los
/// baja y analiza en segundo plano (sin cargarlos al reproductor) y deja
/// elegir el automático.
class SubtitleCatalog extends ChangeNotifier {
  SubtitleCatalog({
    this._fetcher,
    this.priority = SubtitleLanguage.defaultPriority,
    this.analyzePerLanguage = 8,
    this.concurrency = 4,
  });

  /// Con `null` no se baja nada: solo se ordenan y eligen las pistas del
  /// archivo.
  final SubtitleFetcher? _fetcher;
  final List<SubtitleLanguage> priority;

  /// Cuántos de cada idioma de [priority] se bajan para analizarlos.
  final int analyzePerLanguage;
  final int concurrency;

  final List<SubtitleEntry> _external = [];
  Duration? _videoDuration;
  bool _disposed = false;

  /// Termina cuando se analizaron los externos que se iban a analizar.
  Future<void> analysisDone = Future.value();

  /// Los externos, ya ordenados.
  List<SubtitleEntry> get externals => List.unmodifiable(_external);

  /// Duración del video, para estimar la alineación. Cambiarla recalcula.
  Duration? get videoDuration => _videoDuration;
  set videoDuration(Duration? value) {
    if (value == _videoDuration) return;
    _videoDuration = value;
    _notify();
  }

  /// La alineación de [entry]: `null` mientras no se analizó.
  SubtitleAlignment? alignmentOf(SubtitleEntry entry) {
    final cues = entry.cues;
    if (cues == null) return null;
    return SubtitleAlignment.estimate(cues, _videoDuration);
  }

  /// Carga la lista de subtítulos de los addons y empieza el análisis.
  void setExternal(List<Subtitle> subtitles) {
    final seen = <String>{};
    final usable = [
      for (final s in subtitles)
        if (isHttpUrl(s.url) && seen.add(s.url)) s,
    ];
    final ranked = rankSubtitles(usable, priority: priority);
    final names = <String, int>{};
    final counts = <String, int>{};
    String baseName(Subtitle s) =>
        s.label ?? _languageText(SubtitleLanguage.detect(s), s.lang);
    for (final s in ranked) {
      counts.update(baseName(s), (n) => n + 1, ifAbsent: () => 1);
    }
    _external
      ..clear()
      ..addAll([
        for (final s in ranked)
          () {
            final base = baseName(s);
            final n = names.update(base, (n) => n + 1, ifAbsent: () => 1);
            return SubtitleEntry._(
              id: 'ext:${s.id}',
              subtitle: s,
              language: SubtitleLanguage.detect(s),
              label: counts[base]! > 1 ? '$base $n' : base,
              external: true,
            );
          }(),
      ]);
    analysisDone = _analyze();
    _notify();
  }

  Future<void> _analyze() async {
    final perLanguage = <SubtitleLanguage, int>{};
    final todo = <SubtitleEntry>[];
    for (final entry in _external) {
      if (!priority.contains(entry.language)) continue;
      final n = perLanguage.update(
        entry.language,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
      if (n <= analyzePerLanguage) todo.add(entry);
    }
    for (var i = 0; i < todo.length && !_disposed; i += concurrency) {
      await Future.wait([
        for (final entry in todo.skip(i).take(concurrency)) _fetchCues(entry),
      ]);
      _notify();
    }
  }

  Future<void> _fetchCues(SubtitleEntry entry) async {
    try {
      final fetcher = _fetcher;
      if (fetcher == null) {
        entry.analysisFailed = true;
        return;
      }
      final cues = await fetcher.fetchCues(entry.subtitle.url);
      if (cues.isEmpty) {
        entry.analysisFailed = true;
      } else {
        entry.cues = cues;
      }
    } on Object {
      // Sin URL en el error: solo se marca. El subtítulo sigue disponible.
      entry.analysisFailed = true;
    }
  }

  /// Las opciones del menú: las pistas [embedded] del archivo y los externos,
  /// ordenadas por idioma. Dentro de un idioma van primero las embebidas y
  /// después los externos «probablemente sincronizados».
  List<SubtitleEntry> menuEntries(List<SubtitleTrack> embedded) {
    final all = <SubtitleEntry>[
      for (var i = 0; i < embedded.length; i++)
        () {
          final t = embedded[i];
          final subtitle = Subtitle(
            id: 'emb:${t.id}',
            url: 'embedded:${t.id}',
            lang: t.language ?? 'und',
            label: t.title,
          );
          return SubtitleEntry._(
            id: 'emb:${t.id}',
            subtitle: subtitle,
            language: SubtitleLanguage.detect(subtitle),
            label: trackLabel(t, i),
            embedded: t,
          );
        }(),
      ..._external,
    ];
    final order = rankSubtitles([
      for (final e in all) e.subtitle,
    ], priority: priority);
    final byId = {for (final e in all) e.subtitle.id: e};
    final ranked = [for (final s in order) byId[s.id]!];
    int languageRank(SubtitleEntry e) {
      final p = priority.indexOf(e.language);
      return p < 0 ? priority.length : p;
    }

    int kind(SubtitleEntry e) {
      if (e.isEmbedded) return 0;
      return alignmentOf(e) == SubtitleAlignment.likely ? 1 : 2;
    }

    final indexed = [for (var i = 0; i < ranked.length; i++) (i, ranked[i])];
    indexed.sort((a, b) {
      final l = languageRank(a.$2).compareTo(languageRank(b.$2));
      if (l != 0) return l;
      final k = kind(a.$2).compareTo(kind(b.$2));
      return k != 0 ? k : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  /// Los externos ya analizados, listos para el asistente de sincronización.
  List<SyncCandidate> syncCandidates() => [
    for (final e in _external)
      if (e.cues != null) SyncCandidate(e.subtitle, e.cues!),
  ];

  /// La entrada del catálogo para un subtítulo externo.
  SubtitleEntry? entryFor(Subtitle subtitle) {
    for (final e in _external) {
      if (e.subtitle == subtitle) return e;
    }
    return null;
  }

  /// Elección automática para [preferred] (código de Ajustes), entre
  /// [embedded] y los externos. Por cada idioma de la prioridad: un externo
  /// «probablemente sincronizado»; si no, la pista embebida de ese idioma; si
  /// no, el mejor externo. `null` si no hay nada del idioma.
  SubtitleEntry? pickAutomatic(
    String? preferred,
    List<SubtitleTrack> embedded, {
    bool includeExternal = true,
  }) {
    if (preferred == null) return null;
    final entries = [
      for (final e in menuEntries(embedded))
        if (includeExternal || e.isEmbedded) e,
    ];
    final languages = subtitlePriorityFor(preferred);
    for (final language in languages ?? const <SubtitleLanguage?>[null]) {
      final group = [
        for (final e in entries)
          if (language != null
              ? e.language == language
              : languagesMatch(e.subtitle.lang, preferred))
            e,
      ];
      final likely = group.where(
        (e) => e.external && alignmentOf(e) == SubtitleAlignment.likely,
      );
      if (likely.isNotEmpty) return likely.first;
      final emb = group.where((e) => e.isEmbedded);
      if (emb.isNotEmpty) return emb.first;
      final ext = group.where((e) => e.external);
      if (ext.isNotEmpty) return ext.first;
    }
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String _languageText(SubtitleLanguage language, String lang) =>
    switch (language) {
      SubtitleLanguage.latam => 'Español (Latinoamérica)',
      SubtitleLanguage.spanish => 'Español',
      SubtitleLanguage.english => 'Inglés',
      SubtitleLanguage.other => languageName(lang),
    };
