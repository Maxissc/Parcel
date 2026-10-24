/// Una línea de subtítulo: aparece en [start] y se va en [end].
class SubtitleCue {
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;

  /// Texto sin etiquetas; varias líneas se separan con `\n`.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SubtitleCue &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);

  @override
  String toString() => 'SubtitleCue($start --> $end)';
}

/// Lee subtítulos SRT y WebVTT.
///
/// Es tolerante: acepta BOM, saltos de línea CRLF o CR, tiempos con coma o
/// punto, horas opcionales, índices faltantes y cues sin línea en blanco entre
/// ellos. Lo que no entiende lo descarta. No soporta ASS/SSA.
abstract final class SubtitleParser {
  /// Cues de [source], ordenados por inicio. Una lista vacía si no hay ninguno.
  static List<SubtitleCue> parse(String source) {
    var text = source;
    if (text.startsWith('﻿')) text = text.substring(1);
    final lines = text.split(_lineBreak);

    final cues = <SubtitleCue>[];
    Duration? start;
    Duration? end;
    var body = <String>[];

    void finish() {
      final s = start;
      final e = end;
      if (s != null && e != null && e >= s) {
        final cueText = _clean(body);
        if (cueText.isNotEmpty) {
          cues.add(SubtitleCue(start: s, end: e, text: cueText));
        }
      }
      start = null;
      end = null;
      body = <String>[];
    }

    for (final line in lines) {
      final timing = _timing.firstMatch(line);
      if (timing != null) {
        // Sin línea en blanco, el índice del cue siguiente quedó al final del
        // texto del anterior.
        if (start != null && body.isNotEmpty && _digits.hasMatch(body.last)) {
          body.removeLast();
        }
        finish();
        start = _parseTime(timing.group(1)!);
        end = _parseTime(timing.group(2)!);
      } else if (start != null) {
        if (line.trim().isEmpty) {
          finish();
        } else {
          body.add(line);
        }
      }
    }
    finish();
    // `sort` de Dart no es estable: se desempata por posición.
    final indexed = [for (var i = 0; i < cues.length; i++) (i, cues[i])]
      ..sort((a, b) {
        final c = a.$2.start.compareTo(b.$2.start);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return List.unmodifiable([for (final e in indexed) e.$2]);
  }
}

final RegExp _lineBreak = RegExp(r'\r\n|\r|\n');
// Línea de tiempo completa: `HH:MM:SS,mmm --> HH:MM:SS,mmm`, con horas
// opcionales (VTT) y settings opcionales al final. Una línea de texto que solo
// contiene `-->` no calza.
const String _stamp = r'(?:\d+:)?\d{1,2}:\d{1,2}(?:[,.]\d{1,3})?';
final RegExp _timing = RegExp(
  '^\\s*($_stamp)\\s*-->\\s*($_stamp)(?:\\s+\\S.*)?\\s*\$',
);
final RegExp _digits = RegExp(r'^\s*\d+\s*$');
final RegExp _time = RegExp(
  r'^(?:(\d+):)?(\d{1,2}):(\d{1,2})(?:[,.](\d{1,3}))?$',
);
final RegExp _tags = RegExp(r'<[^>]*>|\{\\[^}]*\}');

Duration? _parseTime(String token) {
  final m = _time.firstMatch(token);
  if (m == null) return null;
  final hours = int.parse(m.group(1) ?? '0');
  final minutes = int.parse(m.group(2)!);
  final seconds = int.parse(m.group(3)!);
  final fraction = m.group(4);
  // «,5» es medio segundo, no 5 ms.
  final millis = fraction == null ? 0 : int.parse(fraction.padRight(3, '0'));
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: millis,
  );
}

String _clean(List<String> lines) {
  final cleaned = <String>[];
  for (final line in lines) {
    final text = line
        .replaceAll(_tags, '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .trim();
    if (text.isNotEmpty) cleaned.add(text);
  }
  return cleaned.join('\n');
}
