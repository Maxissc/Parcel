import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

import '../support.dart';

Subtitle _sub(String lang, {String? label, String? id}) => Subtitle(
  id: id ?? '$lang-${label ?? ''}',
  url: 'https://subs.example.com/$lang',
  lang: lang,
  label: label,
);

SubtitleLanguage _detect(String lang, {String? label, String? title}) =>
    SubtitleLanguage.detect(_sub(lang, label: label), title: title);

void main() {
  group('detección', () {
    test('con los códigos reales de OpenSubtitles v3 (verificados con curl)', () {
      // `lang` que devolvió https://opensubtitles-v3.strem.io/subtitles/movie/
      // tt1160419.json (Dune, 2021) el 2026-10-24. El español de Latinoamérica
      // viene como `spl`; el resto del español, como `spa`. No hay un código
      // `es-419` ni parecido en esa respuesta.
      final subs = parseSubtitles(
        fixture('opensubtitles_subtitles_movie_tt1160419.json')['subtitles'],
      );
      final byLang = {for (final s in subs) s.lang: SubtitleLanguage.detect(s)};
      expect(byLang['spl'], SubtitleLanguage.latam);
      expect(byLang['spa'], SubtitleLanguage.spanish);
      expect(byLang['eng'], SubtitleLanguage.english);
      expect(byLang['pob'], SubtitleLanguage.other);
      expect(byLang['srp'], SubtitleLanguage.other);
      expect(byLang['fre'], SubtitleLanguage.other);
    });

    test('spl es LatAm', () {
      expect(_detect('spl'), SubtitleLanguage.latam);
      expect(_detect('SPL'), SubtitleLanguage.latam);
    });

    test('códigos BCP 47 de Latinoamérica', () {
      for (final code in [
        'es-419',
        'es_419',
        'es-MX',
        'es-ar',
        'es-LA',
        'es-CO',
        'es-CL',
        'es-PE',
        'es-UY',
        'es-VE',
      ]) {
        expect(_detect(code), SubtitleLanguage.latam, reason: code);
      }
    });

    test('español de España y genérico', () {
      for (final code in ['spa', 'es', 'es-ES', 'es_es', 'ES']) {
        expect(_detect(code), SubtitleLanguage.spanish, reason: code);
      }
    });

    test('el label lo pasa a LatAm', () {
      expect(_detect('spa', label: 'Español Latino'), SubtitleLanguage.latam);
      expect(_detect('es', label: 'Spanish (LatAm)'), SubtitleLanguage.latam);
      expect(
        _detect('spa', label: 'Español Latinoamérica'),
        SubtitleLanguage.latam,
      );
      expect(_detect('spa', label: 'Spanish (LA)'), SubtitleLanguage.latam);
      expect(
        _detect('spa', label: 'Español - América Latina'),
        SubtitleLanguage.latam,
      );
    });

    test('el título también', () {
      expect(
        _detect('spa', title: 'Película.2023.1080p.LATINO.srt'),
        SubtitleLanguage.latam,
      );
    });

    test('sin marcas de Latinoamérica sigue siendo español', () {
      expect(_detect('spa', label: 'Español'), SubtitleLanguage.spanish);
      expect(_detect('spa', label: 'Castellano'), SubtitleLanguage.spanish);
    });

    test('«LA» solo cuenta si el subtítulo es en español', () {
      expect(_detect('eng', label: 'English (LA)'), SubtitleLanguage.english);
      expect(
        _detect('eng', label: 'Los Angeles Cut'),
        SubtitleLanguage.english,
      );
    });

    test('«latin» (el idioma) y el alfabeto latino no son LatAm', () {
      expect(_detect('srp', label: 'Serbian Latin'), SubtitleLanguage.other);
      expect(_detect('lat'), SubtitleLanguage.other);
    });

    test('inglés', () {
      for (final code in ['eng', 'en', 'en-US', 'en_GB', 'EN']) {
        expect(_detect(code), SubtitleLanguage.english, reason: code);
      }
      expect(_detect('en', label: 'English'), SubtitleLanguage.english);
    });

    test('un label de español detecta el idioma si el código es raro', () {
      expect(_detect('xx', label: 'Español'), SubtitleLanguage.spanish);
      expect(_detect('xx', label: 'English'), SubtitleLanguage.english);
    });

    test('otros idiomas', () {
      for (final code in ['por', 'pob', 'fre', 'ger', 'ita', 'jpn', 'zht']) {
        expect(_detect(code), SubtitleLanguage.other, reason: code);
      }
    });
  });

  group('rankSubtitles', () {
    final all = [
      _sub('eng', id: 'en1'),
      _sub('fre', id: 'fr1'),
      _sub('spa', id: 'es1'),
      _sub('spl', id: 'la1'),
      _sub('spa', id: 'es2'),
      _sub('eng', id: 'en2'),
      _sub('spl', id: 'la2'),
    ];

    List<String> ids(List<Subtitle> subs) => [for (final s in subs) s.id];

    test('por defecto: LatAm > español > inglés > resto', () {
      expect(ids(rankSubtitles(all)), [
        'la1',
        'la2',
        'es1',
        'es2',
        'en1',
        'en2',
        'fr1',
      ]);
    });

    test('mantiene el orden de los addons a igualdad', () {
      final ranked = rankSubtitles([
        _sub('spa', id: 'b'),
        _sub('spa', id: 'a'),
        _sub('spa', id: 'c'),
      ]);
      expect(ids(ranked), ['b', 'a', 'c']);
    });

    test('con otra prioridad', () {
      final ranked = rankSubtitles(
        all,
        priority: [SubtitleLanguage.english, SubtitleLanguage.latam],
      );
      expect(ids(ranked), ['en1', 'en2', 'la1', 'la2', 'fr1', 'es1', 'es2']);
    });

    test('con prioridad vacía no reordena', () {
      expect(ids(rankSubtitles(all, priority: const [])), ids(all));
    });

    test('no modifica la lista de entrada', () {
      final copy = [...all];
      rankSubtitles(all);
      expect(all, copy);
    });

    test('el label cuenta para el ranking', () {
      final ranked = rankSubtitles([
        _sub('spa', id: 'es'),
        _sub('spa', id: 'latino', label: 'Latino'),
      ]);
      expect(ids(ranked), ['latino', 'es']);
    });
  });
}
