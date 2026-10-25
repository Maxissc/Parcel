import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

Meta _meta({
  String? country,
  String? originalLanguage,
  Map<String, Object?>? extras,
}) => Meta.fromJson({
  'id': 'tt1',
  'type': 'movie',
  'name': 'X',
  'country': ?country,
  'original_language': ?originalLanguage,
  'app_extras': ?extras,
});

void main() {
  group('inferOriginalLanguage', () {
    test('usa original_language si vino, en código de 3 letras', () {
      expect(inferOriginalLanguage(_meta(originalLanguage: 'ja')), 'jpn');
      expect(inferOriginalLanguage(_meta(originalLanguage: 'es')), 'spa');
      expect(inferOriginalLanguage(_meta(originalLanguage: 'en')), 'eng');
      expect(inferOriginalLanguage(_meta(originalLanguage: 'fr')), 'fre');
      expect(inferOriginalLanguage(_meta(originalLanguage: 'de')), 'ger');
      expect(inferOriginalLanguage(_meta(originalLanguage: 'it')), 'ita');
      expect(inferOriginalLanguage(_meta(originalLanguage: 'ko')), 'kor');
      expect(inferOriginalLanguage(_meta(originalLanguage: 'hi')), 'hin');
      expect(inferOriginalLanguage(_meta(originalLanguage: 'pt')), 'por');
      expect(inferOriginalLanguage(_meta(originalLanguage: 'zh')), 'chi');
      expect(inferOriginalLanguage(_meta(originalLanguage: 'ru')), 'rus');
    });

    test('TMDB usa cn para el cantonés', () {
      expect(inferOriginalLanguage(_meta(originalLanguage: 'cn')), 'chi');
    });

    test('un código de 3 letras o desconocido se deja como vino', () {
      expect(inferOriginalLanguage(_meta(originalLanguage: 'JPN')), 'jpn');
      expect(inferOriginalLanguage(_meta(originalLanguage: 'sv')), 'sv');
    });

    test('original_language gana sobre el país', () {
      final meta = _meta(country: 'United States', originalLanguage: 'ja');
      expect(inferOriginalLanguage(meta), 'jpn');
    });

    test('lee original_language de app_extras', () {
      final meta = _meta(extras: {'original_language': 'ko'});
      expect(inferOriginalLanguage(meta), 'kor');
    });

    test('sin original_language, usa el país del mapa', () {
      const expected = {
        'United States': 'eng',
        'UK': 'eng',
        'United Kingdom': 'eng',
        'Canada': 'eng',
        'Australia': 'eng',
        'Ireland': 'eng',
        'New Zealand': 'eng',
        'Spain': 'spa',
        'Mexico': 'spa',
        'Argentina': 'spa',
        'Colombia': 'spa',
        'Chile': 'spa',
        'France': 'fre',
        'Germany': 'ger',
        'Italy': 'ita',
        'Japan': 'jpn',
        'South Korea': 'kor',
        'India': 'hin',
        'Brazil': 'por',
        'Portugal': 'por',
        'China': 'chi',
        'Hong Kong': 'chi',
        'Taiwan': 'chi',
        'Russia': 'rus',
      };
      expected.forEach((country, lang) {
        expect(
          inferOriginalLanguage(_meta(country: country)),
          lang,
          reason: country,
        );
      });
    });

    test('el país no distingue mayúsculas ni espacios', () {
      expect(inferOriginalLanguage(_meta(country: '  japan ')), 'jpn');
      expect(inferOriginalLanguage(_meta(country: 'USA')), 'eng');
    });

    test('con varios países, toma el primero que conoce', () {
      expect(inferOriginalLanguage(_meta(country: 'Argentina, Spain')), 'spa');
      expect(inferOriginalLanguage(_meta(country: 'Narnia, France')), 'fre');
    });

    test('sin datos o con un país que no está en el mapa, null', () {
      expect(inferOriginalLanguage(_meta()), isNull);
      expect(inferOriginalLanguage(_meta(country: 'Narnia')), isNull);
    });
  });

  group('pickOriginalAudio', () {
    const eng = AudioTrack(id: '1', language: 'eng', title: 'English 5.1');
    const spaDub = AudioTrack(
      id: '2',
      language: 'spa',
      title: 'Español Latino',
    );
    const engCommentary = AudioTrack(
      id: '3',
      language: 'eng',
      title: 'Director Commentary',
    );
    const jpn = AudioTrack(id: '4', language: 'jpn', title: 'Japanese');
    const jpnDub = AudioTrack(
      id: '5',
      language: 'ja',
      title: 'Japanese (dubbed)',
    );

    test('elige la pista del idioma original', () {
      expect(pickOriginalAudio([spaDub, eng], 'eng'), eng);
      expect(pickOriginalAudio([eng, spaDub, jpn], 'jpn'), jpn);
    });

    test('reconoce códigos de 2 y 3 letras', () {
      expect(pickOriginalAudio([spaDub, jpnDub, jpn], 'ja'), jpn);
      expect(pickOriginalAudio([eng], 'en'), eng);
    });

    test('se salta los comentarios', () {
      expect(pickOriginalAudio([engCommentary, eng], 'eng'), eng);
      for (final title in [
        'Comentario del director',
        'Commentary',
        'comments',
      ]) {
        final t = AudioTrack(id: 'c', language: 'eng', title: title);
        expect(pickOriginalAudio([t, eng], 'eng'), eng, reason: title);
      }
    });

    test('se salta el doblaje marcado', () {
      for (final title in [
        'Japanese (dubbed)',
        'Doblaje',
        'English Dub',
        'Doblado',
      ]) {
        final t = AudioTrack(id: 'd', language: 'ja', title: title);
        expect(pickOriginalAudio([t, jpn], 'jpn'), jpn, reason: title);
      }
    });

    test('sin pista en ese idioma, la default', () {
      const other = AudioTrack(id: '9', language: 'fre', isDefault: true);
      expect(pickOriginalAudio([spaDub, other, eng], 'jpn'), other);
    });

    test('sin default, la primera', () {
      expect(pickOriginalAudio([spaDub, eng], 'jpn'), spaDub);
    });

    test(
      'si solo hay comentario y doblaje en ese idioma, cae a default o primera',
      () {
        expect(pickOriginalAudio([spaDub, engCommentary], 'eng'), spaDub);
      },
    );

    test('con idioma null elige la default o la primera', () {
      const def = AudioTrack(id: '7', language: 'ger', isDefault: true);
      expect(pickOriginalAudio([eng, def], null), def);
      expect(pickOriginalAudio([eng, def.copyNoDefault()], null), eng);
    });

    test('sin pistas, null', () {
      expect(pickOriginalAudio(const [], 'eng'), isNull);
    });

    test('una pista sin idioma ni título no rompe', () {
      const bare = AudioTrack(id: '1');
      expect(pickOriginalAudio([bare], 'eng'), bare);
    });
  });
}

extension on AudioTrack {
  AudioTrack copyNoDefault() =>
      AudioTrack(id: id, language: language, title: title);
}
