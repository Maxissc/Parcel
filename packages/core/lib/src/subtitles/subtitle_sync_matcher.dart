import '../models/subtitle.dart';
import 'subtitle_alignment.dart';
import 'subtitle_language.dart';
import 'subtitle_parser.dart';

/// Un subtítulo ya bajado y parseado, listo para comparar con las marcas.
class SyncCandidate {
  const SyncCandidate(this.subtitle, this.cues);

  final Subtitle subtitle;
  final List<SubtitleCue> cues;
}

/// Cómo le fue a un candidato contra las marcas del usuario.
class SyncMatch {
  const SyncMatch({
    required this.subtitle,
    required this.cues,
    required this.language,
    required this.matchedMarks,
    required this.totalMarks,
    required this.suggestedDelay,
    required this.alignment,
  });

  final Subtitle subtitle;
  final List<SubtitleCue> cues;
  final SubtitleLanguage language;

  /// En cuántas marcas hay un cue que coincide.
  final int matchedMarks;
  final int totalMarks;

  /// Cuánto hay que **retrasar** el subtítulo para que caiga sobre las marcas
  /// (positivo: el subtítulo aparece antes de tiempo; negativo: llega tarde).
  /// Es la mediana de `marca − inicio del cue más cercano`, mirando cues a
  /// ±8 s de cada marca. `null` si ninguna marca tiene un cue cerca.
  final Duration? suggestedDelay;

  /// Qué tan bien calza con la duración del video (`unknown` sin duración).
  final SubtitleAlignment alignment;

  @override
  String toString() =>
      'SyncMatch(${language.name} $matchedMarks/$totalMarks '
      'delay=$suggestedDelay ${alignment.name})';
}

/// Resultado de [SubtitleSyncMatcher.match].
class SyncMatchResult {
  const SyncMatchResult({required this.matches, required this.discarded});

  /// Los que coinciden con las marcas, ordenados.
  final List<SyncMatch> matches;

  /// Los que no, en el mismo orden, por si el usuario quiere verlos igual (por
  /// ejemplo, uno corrido que se arregla con [SyncMatch.suggestedDelay]).
  final List<SyncMatch> discarded;
}

/// Encuentra, entre varios subtítulos, los que calzan con lo que el usuario
/// marcó en el video: «acá empieza a hablar alguien».
abstract final class SubtitleSyncMatcher {
  /// Cuánto antes de la marca puede arrancar un cue para coincidir.
  static const Duration before = Duration(milliseconds: 600);

  /// Cuánto después de la marca puede arrancar un cue para coincidir.
  static const Duration after = Duration(milliseconds: 1200);

  /// Distancia máxima entre una marca y el cue que se usa para el retraso.
  static const Duration delayWindow = Duration(seconds: 8);

  /// Una marca coincide si el candidato tiene un cue activo en ese instante o
  /// uno que arranca entre `t - before` y `t + after`. Con 1 o 2 marcas tienen
  /// que coincidir todas; con 3 o más, al menos el 70 %.
  ///
  /// El orden es: idioma según [priority], más marcas coincidentes,
  /// alineación con [videoDuration] y, a igualdad, el orden de [candidates].
  static SyncMatchResult match({
    required List<SyncCandidate> candidates,
    required List<Duration> marks,
    Duration? videoDuration,
    List<SubtitleLanguage> priority = SubtitleLanguage.defaultPriority,
  }) {
    final needed = marks.length <= 2 ? marks.length : null;
    final entries = <_Entry>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      var matched = 0;
      for (final mark in marks) {
        if (_coincides(candidate.cues, mark)) matched++;
      }
      final language = SubtitleLanguage.detect(candidate.subtitle);
      final p = priority.indexOf(language);
      final keep = needed != null
          ? matched >= needed
          : matched * 10 >= marks.length * 7;
      final alignment = SubtitleAlignment.estimate(
        candidate.cues,
        videoDuration,
      );
      entries.add(
        _Entry(
          SyncMatch(
            subtitle: candidate.subtitle,
            cues: candidate.cues,
            language: language,
            matchedMarks: matched,
            totalMarks: marks.length,
            suggestedDelay: _suggestedDelay(candidate.cues, marks),
            alignment: alignment,
          ),
          index: i,
          languageRank: p < 0 ? priority.length : p,
          keep: keep,
        ),
      );
    }
    entries.sort();
    return SyncMatchResult(
      matches: [
        for (final e in entries)
          if (e.keep) e.match,
      ],
      discarded: [
        for (final e in entries)
          if (!e.keep) e.match,
      ],
    );
  }
}

bool _coincides(List<SubtitleCue> cues, Duration mark) {
  final from = mark - SubtitleSyncMatcher.before;
  final to = mark + SubtitleSyncMatcher.after;
  for (final cue in cues) {
    if (cue.start <= mark && mark < cue.end) return true;
    if (cue.start >= from && cue.start <= to) return true;
  }
  return false;
}

Duration? _suggestedDelay(List<SubtitleCue> cues, List<Duration> marks) {
  final delays = <int>[];
  for (final mark in marks) {
    Duration? nearest;
    for (final cue in cues) {
      if (nearest == null ||
          (mark - cue.start).abs() < (mark - nearest).abs()) {
        nearest = cue.start;
      }
    }
    if (nearest != null &&
        (mark - nearest).abs() <= SubtitleSyncMatcher.delayWindow) {
      delays.add((mark - nearest).inMicroseconds);
    }
  }
  if (delays.isEmpty) return null;
  delays.sort();
  final mid = delays.length ~/ 2;
  final median = delays.length.isOdd
      ? delays[mid]
      : ((delays[mid - 1] + delays[mid]) / 2).round();
  return Duration(microseconds: median);
}

class _Entry implements Comparable<_Entry> {
  _Entry(
    this.match, {
    required this.index,
    required this.languageRank,
    required this.keep,
  });

  final SyncMatch match;
  final int index;
  final int languageRank;
  final bool keep;

  static int _alignmentRank(SubtitleAlignment a) => switch (a) {
    SubtitleAlignment.likely => 0,
    SubtitleAlignment.unknown => 1,
    SubtitleAlignment.fpsMismatch => 2,
    SubtitleAlignment.unlikely => 3,
  };

  @override
  int compareTo(_Entry other) {
    var c = languageRank.compareTo(other.languageRank);
    if (c != 0) return c;
    c = other.match.matchedMarks.compareTo(match.matchedMarks);
    if (c != 0) return c;
    c = _alignmentRank(match.alignment)
        .compareTo(_alignmentRank(other.match.alignment));
    if (c != 0) return c;
    return index.compareTo(other.index);
  }
}
