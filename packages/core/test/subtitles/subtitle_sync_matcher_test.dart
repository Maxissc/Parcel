import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

Duration _s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

SubtitleCue _cue(num start, [num length = 1.5]) =>
    SubtitleCue(start: _s(start), end: _s(start + length), text: 'x');

SyncCandidate _cand(String id, List<SubtitleCue> cues, {String lang = 'spa'}) =>
    SyncCandidate(
      Subtitle(id: id, url: 'https://subs.example.com/$id', lang: lang),
      cues,
    );

List<String> _ids(List<SyncMatch> matches) => [
  for (final m in matches) m.subtitle.id,
];

void main() {
  group('una marca', () {
    // El usuario marca t = 100 s: ahí empieza a hablar alguien.
    final marks = [_s(100)];

    test('coincide con un cue que arranca en [t-0,6 s, t+1,2 s]', () {
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('justo', [_cue(100.5)]),
          _cand('borde-antes', [_cue(99.4)]),
          _cand('borde-despues', [_cue(101.2)]),
          _cand('muy-antes', [_cue(99.3, 0.5)]),
          _cand('muy-despues', [_cue(101.3)]),
        ],
        marks: marks,
      );
      expect(_ids(result.matches), ['justo', 'borde-antes', 'borde-despues']);
      expect(_ids(result.discarded), ['muy-antes', 'muy-despues']);
    });

    test('coincide con un cue activo en t aunque haya empezado antes', () {
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('activo', [_cue(97, 5)]),
          _cand('ya-termino', [_cue(97, 2.9)]),
        ],
        marks: marks,
      );
      expect(_ids(result.matches), ['activo']);
      expect(_ids(result.discarded), ['ya-termino']);
    });

    test('guarda cuántas marcas coinciden', () {
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('ok', [_cue(100)]),
        ],
        marks: marks,
      );
      expect(result.matches.single.matchedMarks, 1);
      expect(result.matches.single.totalMarks, 1);
    });
  });

  group('dos marcas', () {
    test('tiene que coincidir con las dos', () {
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('las-dos', [_cue(100.2), _cue(500.4)]),
          _cand('una', [_cue(100.2), _cue(520)]),
        ],
        marks: [_s(100), _s(500)],
      );
      expect(_ids(result.matches), ['las-dos']);
      expect(_ids(result.discarded), ['una']);
      expect(result.discarded.single.matchedMarks, 1);
    });
  });

  group('tres o más marcas: al menos el 60 %', () {
    final marks3 = [_s(100), _s(500), _s(900)];

    test('con 3 marcas alcanzan 2 (67 %) y no 1', () {
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('tres', [_cue(100), _cue(500), _cue(900)]),
          _cand('dos', [_cue(100), _cue(500), _cue(950)]),
          _cand('una', [_cue(100), _cue(550), _cue(950)]),
        ],
        marks: marks3,
      );
      expect(_ids(result.matches), ['tres', 'dos']);
      expect(_ids(result.discarded), ['una']);
    });

    test('con 4 marcas alcanzan 3 (75 %) y no 2 (50 %)', () {
      final marks4 = [_s(100), _s(500), _s(900), _s(1300)];
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('tres-de-cuatro', [_cue(100), _cue(500), _cue(900)]),
          _cand('dos-de-cuatro', [_cue(100), _cue(500)]),
        ],
        marks: marks4,
      );
      expect(_ids(result.matches), ['tres-de-cuatro']);
      expect(_ids(result.discarded), ['dos-de-cuatro']);
    });

    test('con 10 marcas alcanzan 6 y no 5', () {
      final marks = [for (var i = 1; i <= 10; i++) _s(i * 100)];
      List<SubtitleCue> first(int n) => [
        for (var i = 1; i <= n; i++) _cue(i * 100),
      ];
      final result = SubtitleSyncMatcher.match(
        candidates: [_cand('seis', first(6)), _cand('cinco', first(5))],
        marks: marks,
      );
      expect(_ids(result.matches), ['seis']);
      expect(_ids(result.discarded), ['cinco']);
    });
  });

  group('retraso sugerido', () {
    test('un subtítulo corrido 2,0 s hacia adelante sugiere +2,0 s', () {
      // El habla real arranca en 100, 500 y 900, pero el subtítulo la muestra
      // 2 s antes (cues cortos: no están activos en t).
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('corrido', [_cue(98), _cue(498), _cue(898)]),
        ],
        marks: [_s(100), _s(500), _s(900)],
      );
      expect(result.matches, isEmpty);
      final shifted = result.discarded.single;
      expect(shifted.suggestedDelay, _s(2.0));
    });

    test('un subtítulo que llega tarde sugiere un retraso negativo', () {
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('tarde', [_cue(101.5), _cue(501.5)]),
        ],
        marks: [_s(100), _s(500)],
      );
      expect(result.discarded.single.suggestedDelay, _s(-1.5));
    });

    test('un subtítulo bien sincronizado sugiere casi cero', () {
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('ok', [_cue(100.2), _cue(500.2)]),
        ],
        marks: [_s(100), _s(500)],
      );
      expect(result.matches.single.suggestedDelay, _s(-0.2));
    });

    test('es la mediana: un valor raro no la mueve', () {
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('mediana', [_cue(98), _cue(498), _cue(895), _cue(1298)]),
        ],
        marks: [_s(100), _s(500), _s(900), _s(1300)],
      );
      // retrasos: 2, 2, 5, 2 -> mediana 2
      expect(result.discarded.single.suggestedDelay, _s(2.0));
    });

    test('con cantidad par de retrasos promedia los dos del medio', () {
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('par', [_cue(98), _cue(497)]),
        ],
        marks: [_s(100), _s(500)],
      );
      // retrasos: 2 y 3 -> 2,5
      expect(result.discarded.single.suggestedDelay, _s(2.5));
    });

    test('toma el cue más cercano y no mira más allá de ±8 s', () {
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('cercano', [_cue(99, 0.5), _cue(103, 0.5)]),
          _cand('lejos', [_cue(90), _cue(120)]),
        ],
        marks: [_s(100)],
      );
      final byId = {for (final m in result.discarded) m.subtitle.id: m};
      expect(byId['cercano']!.suggestedDelay, _s(1.0));
      expect(byId['lejos']!.suggestedDelay, isNull);
    });

    test('también se calcula para los que coinciden', () {
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('ok', [_cue(100.5)]),
        ],
        marks: [_s(100)],
      );
      expect(result.matches.single.suggestedDelay, _s(-0.5));
    });
  });

  group('orden', () {
    test('primero por idioma (LatAm > español > inglés > resto)', () {
      final cues = [_cue(100), _cue(500)];
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('fr', cues, lang: 'fre'),
          _cand('en', cues, lang: 'eng'),
          _cand('es', cues, lang: 'spa'),
          _cand('la', cues, lang: 'spl'),
        ],
        marks: [_s(100), _s(500)],
      );
      expect(_ids(result.matches), ['la', 'es', 'en', 'fr']);
    });

    test('con otra prioridad de idiomas', () {
      final cues = [_cue(100)];
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('es', cues, lang: 'spa'),
          _cand('en', cues, lang: 'eng'),
        ],
        marks: [_s(100)],
        priority: [SubtitleLanguage.english],
      );
      expect(_ids(result.matches), ['en', 'es']);
    });

    test('después por coincidencias', () {
      final marks = [for (var i = 1; i <= 5; i++) _s(i * 100)];
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('cuatro', [for (var i = 1; i <= 4; i++) _cue(i * 100)]),
          _cand('cinco', [for (var i = 1; i <= 5; i++) _cue(i * 100)]),
        ],
        marks: marks,
      );
      expect(_ids(result.matches), ['cinco', 'cuatro']);
    });

    test('después por alineación con la duración del video', () {
      final cues = [_cue(100), _cue(7000)];
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('corto', [_cue(100), _cue(3000)]),
          _cand('largo', cues),
        ],
        marks: [_s(100)],
        videoDuration: const Duration(seconds: 7200),
      );
      expect(_ids(result.matches), ['largo', 'corto']);
      expect(result.matches.first.alignment, SubtitleAlignment.likely);
      expect(result.matches.last.alignment, SubtitleAlignment.unlikely);
    });

    test('a igualdad respeta el orden de los candidatos', () {
      final cues = [_cue(100)];
      final result = SubtitleSyncMatcher.match(
        candidates: [_cand('b', cues), _cand('a', cues), _cand('c', cues)],
        marks: [_s(100)],
      );
      expect(_ids(result.matches), ['b', 'a', 'c']);
    });

    test('los descartados también salen ordenados por idioma', () {
      final cues = [_cue(300)];
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('en', cues, lang: 'eng'),
          _cand('la', cues, lang: 'spl'),
        ],
        marks: [_s(100)],
      );
      expect(result.matches, isEmpty);
      expect(_ids(result.discarded), ['la', 'en']);
    });
  });

  group('casos borde', () {
    test('sin marcas no filtra nada', () {
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('a', [_cue(1)]),
          _cand('b', [_cue(2)], lang: 'eng'),
        ],
        marks: const [],
      );
      expect(_ids(result.matches), ['a', 'b']);
      expect(result.discarded, isEmpty);
    });

    test('un candidato sin cues se descarta', () {
      final result = SubtitleSyncMatcher.match(
        candidates: [_cand('vacio', const [])],
        marks: [_s(100)],
      );
      expect(_ids(result.discarded), ['vacio']);
      expect(result.discarded.single.suggestedDelay, isNull);
    });

    test('sin candidatos', () {
      final result = SubtitleSyncMatcher.match(
        candidates: const [],
        marks: [_s(100)],
      );
      expect(result.matches, isEmpty);
      expect(result.discarded, isEmpty);
    });

    test('toString no muestra el id ni la URL del subtítulo', () {
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('https://subs.example.com/token-secreto/es.srt', [_cue(100)]),
        ],
        marks: [_s(100)],
      );
      expect(result.matches.single.toString(), isNot(contains('secreto')));
    });

    test('marcas repetidas cuentan por separado', () {
      final result = SubtitleSyncMatcher.match(
        candidates: [
          _cand('a', [_cue(100)]),
        ],
        marks: [_s(100), _s(100)],
      );
      expect(result.matches.single.matchedMarks, 2);
    });
  });
}
