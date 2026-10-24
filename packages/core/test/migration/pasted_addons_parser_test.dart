import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

void main() {
  const a = 'https://a.example.com/manifest.json';
  const b = 'https://b.example.com/tok/manifest.json';

  test('una URL por línea', () {
    expect(PastedAddonsParser.parse('$a\n$b\n'), [a, b]);
  });

  test('separadas por espacios o comas', () {
    expect(PastedAddonsParser.parse('$a $b'), [a, b]);
    expect(PastedAddonsParser.parse('$a, $b'), [a, b]);
    expect(PastedAddonsParser.parse('$a,$b'), [a, b]);
  });

  test('convierte stremio:// y completa manifest.json', () {
    expect(
      PastedAddonsParser.parse(
        'stremio://c.example.com/cfg\nhttp://d.example.com',
      ),
      [
        'https://c.example.com/cfg/manifest.json',
        'http://d.example.com/manifest.json',
      ],
    );
  });

  test('deduplica por URL normalizada y conserva el primer orden', () {
    expect(
      PastedAddonsParser.parse(
        'https://a.example.com\n$b\nstremio://a.example.com/manifest.json\n$a',
      ),
      [a, b],
    );
  });

  test('saca las URLs de texto con prosa y puntuación', () {
    expect(
      PastedAddonsParser.parse('Mis addons: ($a). Y también "$b"; gracias.'),
      [a, b],
    );
  });

  test('ignora lo que no es una URL de addon', () {
    expect(
      PastedAddonsParser.parse('hola ftp://x.com/y mailto:a@b.com'),
      isEmpty,
    );
    expect(PastedAddonsParser.parse(''), isEmpty);
    expect(PastedAddonsParser.parse('   \n  '), isEmpty);
  });

  test('lista JSON de strings', () {
    expect(PastedAddonsParser.parse('["$a", "stremio://b.example.com/tok"]'), [
      a,
      'https://b.example.com/tok/manifest.json',
    ]);
  });

  test('JSON con barras escapadas', () {
    expect(
      PastedAddonsParser.parse(r'["https:\/\/a.example.com\/manifest.json"]'),
      [a],
    );
  });

  test('JSON de addonCollectionGet toma solo los transportUrl', () {
    const json = '''
{"result":{"addons":[
 {"transportUrl":"https://v3-cinemeta.strem.io/manifest.json",
  "manifest":{"id":"x","name":"Cinemeta","logo":"https://img.example.com/logo.png",
              "contactEmail":"a@b.com","background":"https://img.example.com/bg.jpg"},
  "flags":{"official":true}},
 {"transportUrl":"https://torrent.example.com/tok123/manifest.json","manifest":{"id":"y","name":"T"}}
],"lastModified":"2026-01-01T00:00:00Z"}}''';
    expect(PastedAddonsParser.parse(json), [
      'https://v3-cinemeta.strem.io/manifest.json',
      'https://torrent.example.com/tok123/manifest.json',
    ]);
  });

  test('JSON de filas con url (formato de Nuvio)', () {
    const json = '[{"url":"$a","name":"A","sort_order":1},{"url":"$b"}]';
    expect(PastedAddonsParser.parse(json), [a, b]);
  });

  test('JSON truncado cae al barrido de texto', () {
    expect(PastedAddonsParser.parse('["$a", "$b"'), [a, b]);
  });

  group('URLs con comas en la ruta (Torrentio)', () {
    // normalizeManifestUrl codifica la barra vertical como %7C (equivalente).
    String n(String url) => url.replaceAll('|', '%7C');
    const t1 =
        'https://torrentio.strem.fun/providers=yts,eztv|qualityfilter=480p,cam/manifest.json';
    const t2 =
        'https://torrentio.strem.fun/providers=nyaasi,tokyotosho|sort=seeders/manifest.json';

    test('texto suelto separado por coma y espacio, o por salto de línea', () {
      expect(PastedAddonsParser.parse('$t1, $t2'), [n(t1), n(t2)]);
      expect(PastedAddonsParser.parse('$t1\n$t2'), [n(t1), n(t2)]);
    });

    test('una coma pegada a otro esquema sí separa', () {
      expect(PastedAddonsParser.parse('$t1,$a'), [n(t1), a]);
    });

    test('una coma final no forma parte de la URL', () {
      expect(PastedAddonsParser.parse('mirá $t1, y listo'), [n(t1)]);
      expect(PastedAddonsParser.parse('$t1,'), [n(t1)]);
    });

    test('colección JSON con una URL con comas y barra vertical', () {
      const json =
          '{"result":{"addons":[{"transportUrl":"$t1","manifest":{"id":"t","name":"T"}}]}}';
      expect(PastedAddonsParser.parse(json), [n(t1)]);
    });

    test('lista JSON de strings con comas en la ruta', () {
      expect(PastedAddonsParser.parse('["$t1","$t2"]'), [n(t1), n(t2)]);
    });
  });
}
