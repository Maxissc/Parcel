import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/features/player/subtitle_catalog.dart';

/// Un SRT con un cue cada 10 s hasta [endSeconds].
String srt(int endSeconds) {
  final b = StringBuffer();
  var n = 1;
  String ts(int s) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(s ~/ 3600)}:${two(s % 3600 ~/ 60)}:${two(s % 60)},000';
  }

  for (var t = 5; t + 3 <= endSeconds; t += 10) {
    b.writeln(n++);
    b.writeln('${ts(t)} --> ${ts(t + 3)}');
    b.writeln('Linea $n');
    b.writeln();
  }
  return b.toString();
}

Subtitle sub(String id, String lang, {String? label}) => Subtitle(
  id: id,
  url: 'http://subs.example.com/$id.srt',
  lang: lang,
  label: label,
);

SubtitleCatalog catalog(Map<String, String> bodies, {int analyze = 8}) {
  final client = MockClient((request) async {
    final id = request.url.pathSegments.last.replaceAll('.srt', '');
    final body = bodies[id];
    return body == null
        ? http.Response('x', 404)
        : http.Response(body, 200, headers: {'content-type': 'text/plain'});
  });
  return SubtitleCatalog(
    fetcher: SubtitleFetcher(client),
    analyzePerLanguage: analyze,
  );
}

void main() {
  const duration = Duration(minutes: 10);

  test('ordena LatAm, español, inglés y después los otros', () async {
    final c = catalog({});
    c.setExternal([
      sub('fr', 'fre'),
      sub('en', 'eng'),
      sub('es', 'spa'),
      sub('la', 'spl'),
    ]);
    await c.analysisDone;
    final ids = c.menuEntries(const []).map((e) => e.subtitle.id).toList();
    expect(ids, ['la', 'es', 'en', 'fr']);
  });

  test(
    'dentro de cada idioma van primero los probablemente sincronizados',
    () async {
      final c = catalog({
        'es1': srt(300), // termina a los 5 min de 10: desfasado
        'es2': srt(595), // calza
      });
      c.setExternal([sub('es1', 'spa'), sub('es2', 'spa')]);
      c.videoDuration = duration;
      await c.analysisDone;
      final entries = c.menuEntries(const []);
      expect(entries.map((e) => e.subtitle.id), ['es2', 'es1']);
      expect(
        alignmentLabel(c.alignmentOf(entries[0])),
        'Probablemente sincronizado',
      );
      expect(
        alignmentLabel(c.alignmentOf(entries[1])),
        'Puede estar desfasado',
      );
    },
  );

  test('sin duración no hay etiqueta, y un subtítulo que no baja queda sin etiqueta', () async {
    final c = catalog({'es1': srt(595)});
    c.setExternal([sub('es1', 'spa'), sub('es2', 'spa')]);
    await c.analysisDone;
    for (final e in c.menuEntries(const [])) {
      expect(alignmentLabel(c.alignmentOf(e)), isNull);
    }
    expect(c.externals.last.analysisFailed, isTrue);
  });

  test(
    'las pistas embebidas van antes que los externos del mismo idioma',
    () async {
      final c = catalog({});
      c.setExternal([sub('es1', 'spa')]);
      final entries = c.menuEntries(const [
        SubtitleTrack(id: '3', language: 'spa', title: 'Castellano'),
      ]);
      expect(entries.first.isEmbedded, isTrue);
      expect(entries.last.external, isTrue);
    },
  );

  test('descarta duplicados y rutas que no son http', () {
    final c = catalog({});
    c.setExternal([
      sub('a', 'spa'),
      sub('a', 'spa'),
      const Subtitle(id: 'f', url: 'C:/local.srt', lang: 'spa'),
    ]);
    expect(c.externals, hasLength(1));
  });

  test('nombres repetidos se numeran', () {
    final c = catalog({});
    c.setExternal([sub('a', 'spa'), sub('b', 'spa')]);
    expect(c.externals.map((e) => e.label), ['Español 1', 'Español 2']);
  });

  test('la elección automática toma el LatAm sincronizado', () async {
    final c = catalog({'la': srt(595), 'es': srt(595)});
    c.setExternal([sub('es', 'spa'), sub('la', 'spl')]);
    c.videoDuration = duration;
    await c.analysisDone;
    expect(c.pickAutomatic('latam', const [])?.subtitle.id, 'la');
  });

  test('LatAm y español son un mismo grupo: gana el sincronizado', () async {
    final c = catalog({'la': srt(200), 'es': srt(595)});
    c.setExternal([sub('la', 'spl'), sub('es', 'spa')]);
    c.videoDuration = duration;
    await c.analysisDone;
    expect(c.pickAutomatic('latam', const [])?.subtitle.id, 'es');
  });

  test('un embebido en español gana a un externo LatAm no sincronizado '
      'o sin analizar', () async {
    const embedded = [
      SubtitleTrack(id: '2', language: 'spa', title: 'Castellano'),
    ];
    // Desfasado.
    final unlikely = catalog({'la': srt(200)});
    unlikely.setExternal([sub('la', 'spl')]);
    unlikely.videoDuration = duration;
    await unlikely.analysisDone;
    expect(unlikely.pickAutomatic('latam', embedded)?.isEmbedded, isTrue);

    // Sin analizar (no bajó).
    final unanalyzed = catalog({});
    unanalyzed.setExternal([sub('la', 'spl')]);
    unanalyzed.videoDuration = duration;
    await unanalyzed.analysisDone;
    expect(unanalyzed.pickAutomatic('latam', embedded)?.isEmbedded, isTrue);
  });

  test('un externo LatAm probablemente sincronizado gana sobre todo', () async {
    const embedded = [
      SubtitleTrack(id: '2', language: 'spa', title: 'Castellano'),
    ];
    final c = catalog({'la': srt(595)});
    c.setExternal([sub('la', 'spl')]);
    c.videoDuration = duration;
    await c.analysisDone;
    expect(c.pickAutomatic('latam', embedded)?.subtitle.id, 'la');
  });

  test('en el menú, dentro de cada idioma: sincronizados, embebido y el '
      'resto', () async {
    final c = catalog({'es1': srt(300), 'es2': srt(595)});
    c.setExternal([sub('es1', 'spa'), sub('es2', 'spa')]);
    c.videoDuration = duration;
    await c.analysisDone;
    final entries = c.menuEntries(const [
      SubtitleTrack(id: '3', language: 'spa', title: 'Castellano'),
    ]);
    expect(entries.map((e) => e.isEmbedded ? 'emb' : e.subtitle.id), [
      'es2',
      'emb',
      'es1',
    ]);
  });

  test('un análisis encima de otro no baja dos veces lo mismo', () async {
    final requested = <String>[];
    final client = MockClient((request) async {
      requested.add(request.url.path);
      return http.Response(srt(595), 200);
    });
    final c = SubtitleCatalog(fetcher: SubtitleFetcher(client));
    c.setExternal([sub('a', 'spa')]);
    c.setExternal([sub('a', 'spa'), sub('b', 'spa')]);
    expect(c.analyzing, isTrue);
    await c.analysisDone;
    expect(c.analyzing, isFalse);
    expect(requested..sort(), ['/a.srt', '/b.srt']);
    expect(c.externals.where((e) => e.cues != null), hasLength(2));
  });

  test(
    'un pedido nuevo con otros subtítulos suma sin perder lo analizado',
    () async {
      final c = catalog({'a': srt(595), 'b': srt(595)});
      c.setExternal([sub('a', 'spa')]);
      await c.analysisDone;
      final first = c.externals.single;
      c.setExternal([sub('b', 'spa')]);
      await c.analysisDone;
      expect(c.externals, hasLength(2));
      expect(
        c.externals.any((e) => identical(e, first) && e.cues != null),
        isTrue,
      );
    },
  );

  test('los textos de los subtítulos no llevan URLs', () {
    final c = catalog({});
    c.setExternal([
      sub('a', 'spa', label: 'Grupo http://x.example.com/s?k=SECRETO'),
    ]);
    final entries = c.menuEntries(const [
      SubtitleTrack(
        id: '1',
        language: 'eng',
        title: 'Ver https://y.example.com/p?k=SECRETO',
      ),
    ]);
    for (final e in entries) {
      expect(e.label, isNot(contains('SECRETO')));
      expect(e.label, isNot(contains('http')));
    }
  });

  test(
    'si no hay externo sincronizado usa la pista embebida del idioma',
    () async {
      final c = catalog({'la': srt(200)});
      c.setExternal([sub('la', 'spl')]);
      c.videoDuration = duration;
      await c.analysisDone;
      final picked = c.pickAutomatic('latam', const [
        SubtitleTrack(id: '2', language: 'spl', title: 'Latino'),
      ]);
      expect(picked?.isEmbedded, isTrue);
    },
  );

  test('sin nada del idioma devuelve null', () async {
    final c = catalog({});
    c.setExternal([sub('en', 'eng')]);
    expect(c.pickAutomatic('por', const []), isNull);
    expect(c.pickAutomatic(null, const []), isNull);
  });

  test('portugués usa el idioma de la pista', () {
    final c = catalog({});
    c.setExternal([sub('en', 'eng'), sub('pt', 'por')]);
    expect(c.pickAutomatic('por', const [])?.subtitle.id, 'pt');
  });

  test('syncCandidates trae solo los ya analizados', () async {
    final c = catalog({'es1': srt(595)});
    c.setExternal([sub('es1', 'spa'), sub('es2', 'spa')]);
    await c.analysisDone;
    expect(c.syncCandidates().map((e) => e.subtitle.id), ['es1']);
  });
}
