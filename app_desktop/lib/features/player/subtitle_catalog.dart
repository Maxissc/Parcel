import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../data/app_settings.dart';
import '../../playback/playback_errors.dart';
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

  /// Texto para el menú, sin URLs. Puede cambiar de número si llegan más
  /// subtítulos con el mismo nombre.
  String label;

  /// La pista del archivo, si es embebido.
  final SubtitleTrack? embedded;

  /// `true` si viene de un addon.
  final bool external;

  /// Los cues, cuando ya se bajó y analizó (solo externos).
  List<SubtitleCue>? cues;

  /// Si el análisis falló (no se pudo bajar o no tiene cues).
  bool analysisFailed = false;

  // Última alineación calculada y con qué datos, para no repetir la cuenta.
  SubtitleAlignment? _alignment;
  List<SubtitleCue>? _alignmentCues;
  Duration? _alignmentDuration;

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
///
/// Es del contenido, no de cada intento de reproducción: [setExternal] suma
/// lo que llega sin repetir lo que ya se bajó.
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

  // Los que están esperando o en camino de ser analizados.
  final Set<SubtitleEntry> _queued = {};
  Duration? _videoDuration;
  bool _disposed = false;

  /// Termina cuando se analizaron los externos que se iban a analizar.
  Future<void> analysisDone = Future.value();

  /// Los externos, ya ordenados.
  List<SubtitleEntry> get externals => List.unmodifiable(_external);

  /// `true` mientras se bajan y analizan subtítulos.
  bool get analyzing => _queued.isNotEmpty;

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
    if (!identical(entry._alignmentCues, cues) ||
        entry._alignmentDuration != _videoDuration) {
      entry
        .._alignment = SubtitleAlignment.estimate(cues, _videoDuration)
        .._alignmentCues = cues
        .._alignmentDuration = _videoDuration;
    }
    return entry._alignment;
  }

  /// Suma [subtitles] a los que ya hay (los repetidos, por URL, se ignoran) y
  /// empieza a analizar los nuevos.
  void setExternal(List<Subtitle> subtitles) {
    final known = {for (final e in _external) e.subtitle.url: e};
    final fresh = <Subtitle>[];
    final seen = {...known.keys};
    for (final s in subtitles) {
      if (isHttpUrl(s.url) && seen.add(s.url)) fresh.add(s);
    }
    if (fresh.isEmpty) return;
    final ranked = rankSubtitles([
      for (final e in _external) e.subtitle,
      ...fresh,
    ], priority: priority);
    final names = <String, int>{};
    final counts = <String, int>{};
    String baseName(Subtitle s) => redactUrlsInText(
      s.label ?? _languageText(SubtitleLanguage.detect(s), s.lang),
    );
    for (final s in ranked) {
      counts.update(baseName(s), (n) => n + 1, ifAbsent: () => 1);
    }
    final entries = <SubtitleEntry>[];
    for (final s in ranked) {
      final base = baseName(s);
      final n = names.update(base, (n) => n + 1, ifAbsent: () => 1);
      final label = counts[base]! > 1 ? '$base $n' : base;
      final existing = known[s.url];
      if (existing != null) {
        existing.label = label;
        entries.add(existing);
      } else {
        entries.add(
          SubtitleEntry._(
            id: 'ext:${s.id}',
            subtitle: s,
            language: SubtitleLanguage.detect(s),
            label: label,
            external: true,
          ),
        );
      }
    }
    _external
      ..clear()
      ..addAll(entries);
    analysisDone = Future.wait([analysisDone, _analyze()]).then((_) {});
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
      final pending =
          entry.cues == null &&
          !entry.analysisFailed &&
          !_queued.contains(entry);
      if (n <= analyzePerLanguage && pending) todo.add(entry);
    }
    _queued.addAll(todo);
    for (var i = 0; i < todo.length; i += concurrency) {
      if (_disposed) break;
      await Future.wait([
        for (final entry in todo.skip(i).take(concurrency)) _fetchCues(entry),
      ]);
      _notify();
    }
    _queued.removeAll(todo);
    _notify();
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
    } finally {
      _queued.remove(entry);
    }
  }

  /// Las opciones del menú: las pistas [embedded] del archivo y los externos,
  /// ordenadas por idioma. Dentro de un idioma van primero los externos
  /// «probablemente sincronizados», después la pista embebida y al final el
  /// resto de los externos.
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
            label: redactUrlsInText(trackLabel(t, i)),
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
      if (e.isEmbedded) return 1;
      return alignmentOf(e) == SubtitleAlignment.likely ? 0 : 2;
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
  /// [embedded] y los externos. Español y Latinoamérica cuentan como un solo
  /// grupo; cada idioma o grupo de la prioridad se agota antes de pasar al
  /// siguiente. En un grupo gana un externo «probablemente sincronizado»; si
  /// no, la pista embebida; si no, el mejor externo. `null` si no hay nada del
  /// idioma.
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
    final groups = <List<SubtitleEntry>>[];
    if (languages == null) {
      groups.add([
        for (final e in entries)
          if (languagesMatch(e.subtitle.lang, preferred)) e,
      ]);
    } else {
      const spanishFamily = {SubtitleLanguage.latam, SubtitleLanguage.spanish};
      final sets = <Set<SubtitleLanguage>>[];
      Set<SubtitleLanguage>? family;
      for (final language in languages) {
        if (spanishFamily.contains(language)) {
          if (family == null) sets.add(family = {});
          family.add(language);
        } else {
          sets.add({language});
        }
      }
      for (final set in sets) {
        groups.add([
          for (final e in entries)
            if (set.contains(e.language)) e,
        ]);
      }
    }
    for (final group in groups) {
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
