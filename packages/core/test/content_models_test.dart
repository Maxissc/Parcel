import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('Meta', () {
    test('parsea el catálogo real de Cinemeta', () {
      final json = fixture('cinemeta_catalog_movie_top.json');
      final metas = parseMetas(json['metas']);
      expect(metas, hasLength(4));
      final first = metas.first;
      expect(first.id, startsWith('tt'));
      expect(first.type, 'movie');
      expect(first.name, isNotEmpty);
      expect(first.poster, startsWith('http'));
      expect(first.genres, isNotEmpty);
      expect(first.videos, isEmpty);
    });

    test('parsea la meta real de una serie con sus videos', () {
      final json = fixture('cinemeta_meta_series_tt0903747.json');
      final meta = Meta.fromJson(json['meta'] as Map<String, dynamic>);
      expect(meta.id, 'tt0903747');
      expect(meta.type, 'series');
      expect(meta.name, 'Breaking Bad');
      expect(meta.cast, contains('Bryan Cranston'));
      expect(meta.videos, hasLength(5));
      final v = meta.videos.first;
      expect(v.id, 'tt0903747:1:1');
      expect(v.title, 'Pilot');
      expect(v.season, 1);
      expect(v.episode, 1);
      expect(v.thumbnail, startsWith('http'));
      expect(v.released, DateTime.utc(2008, 1, 21, 5));
      expect(v.overview, startsWith('When an unassuming'));
    });

    test('descarta metas inválidas y sigue con el resto', () {
      final metas = parseMetas([
        {'id': 'tt1', 'type': 'movie', 'name': 'Buena'},
        {'id': 'tt2', 'type': 'movie'},
        {'type': 'movie', 'name': 'Sin id'},
        {'id': 7, 'type': 'movie', 'name': 'Id numérico'},
        'basura',
        null,
        {'id': 'tt3', 'type': 'series', 'name': 'Otra', 'poster': 5},
      ]);
      expect(metas.map((m) => m.id), ['tt1', 'tt3']);
      expect(metas.last.poster, isNull);
    });

    test('tolera campos opcionales de tipo raro y videos inválidos', () {
      final meta = Meta.fromJson({
        'id': 'x1',
        'type': 'series',
        'name': 'X',
        'genres': 'Drama',
        'cast': [1, 'Ana'],
        'director': null,
        'released': 'no es fecha',
        'imdbRating': 8.5,
        'behaviorHints': 'raro',
        'videos': [
          {'id': 'x1:1:1', 'title': 'Uno', 'season': '1', 'episode': 1},
          {'title': 'Sin id'},
          {'id': 'x1:1:3', 'name': 'Tres', 'number': 3, 'released': 4},
        ],
      });
      expect(meta.genres, ['Drama']);
      expect(meta.cast, ['Ana']);
      expect(meta.directors, isEmpty);
      expect(meta.released, isNull);
      expect(meta.imdbRating, isNull);
      expect(meta.defaultVideoId, isNull);
      expect(meta.videos.map((v) => v.id), ['x1:1:1', 'x1:1:3']);
      expect(meta.videos[0].season, 1);
      expect(meta.videos[1].title, 'Tres');
      expect(meta.videos[1].episode, 3);
      expect(meta.videos[1].released, isNull);
    });

    test('lee defaultVideoId de behaviorHints', () {
      final meta = Meta.fromJson({
        'id': 'a',
        'type': 'movie',
        'name': 'A',
        'behaviorHints': {'defaultVideoId': 'a'},
      });
      expect(meta.defaultVideoId, 'a');
    });
  });

  group('AddonStream', () {
    final streams = parseStreams(
      fixture('stream_http_synthetic.json')['streams'],
    );

    test('descarta los inválidos y conserva el resto', () {
      expect(streams.map((s) => s.name), [
        'Sintético 1080p',
        'Sintético torrent',
        'Tráiler',
        'Web',
        'FTP',
      ]);
    });

    test('parsea un stream HTTP con behaviorHints', () {
      final s = streams[0];
      expect(s.url, 'https://cdn.example.com/video/pelicula.mkv');
      expect(s.description, startsWith('Película.1080p'));
      expect(s.isPlayable, isTrue);
      expect(s.subtitles.single.lang, 'spa');
      expect(s.subtitles.single.label, 'Español');
      final h = s.behaviorHints;
      expect(h.notWebReady, isTrue);
      expect(h.bingeGroup, 'sintetico-1080p');
      expect(h.countryWhitelist, ['arg', 'usa']);
      expect(h.videoHash, '8e245d9679d31e12');
      expect(h.videoSize, 2254857830);
      expect(h.filename, 'Pelicula.1080p.WEB-DL.mkv');
      expect(h.proxyRequestHeaders, {
        'User-Agent': 'Parcel',
        'Referer': 'https://example.com/',
      });
      expect(h.proxyResponseHeaders, {'Content-Type': 'video/mp4'});
    });

    test('un stream sin behaviorHints tiene valores por defecto', () {
      final h = streams[2].behaviorHints;
      expect(h.notWebReady, isFalse);
      expect(h.bingeGroup, isNull);
      expect(h.proxyRequestHeaders, isEmpty);
    });

    test('los torrents se parsean pero no son reproducibles en v1', () {
      final t = streams[1];
      expect(t.infoHash, '6366e0a6d44d49c8fa09c04669375c024e42bf7e');
      expect(t.fileIdx, 3);
      expect(t.sources, hasLength(2));
      expect(t.title, startsWith('Película 720p'));
      expect(t.isPlayable, isFalse);
    });

    test('solo es reproducible una url http o https', () {
      expect(streams[2].isPlayable, isFalse); // ytId
      expect(streams[3].isPlayable, isFalse); // externalUrl
      expect(streams[4].isPlayable, isFalse); // ftp
      expect(
        AddonStream.fromJson({'url': 'http://a.com/v.mp4'}).isPlayable,
        isTrue,
      );
    });

    test('dos streams con la misma fuente y nombre son iguales', () {
      final a = AddonStream.fromJson({'url': 'https://a.com/v', 'name': 'n'});
      final b = AddonStream.fromJson({'url': 'https://a.com/v', 'name': 'n'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('Subtitle', () {
    test('parsea los subtítulos reales de OpenSubtitles', () {
      final json = fixture('opensubtitles_subtitles_movie_tt0111161.json');
      final subs = parseSubtitles(json['subtitles']);
      expect(subs, hasLength(5));
      expect(subs.first.id, '30949');
      expect(subs.first.lang, 'eng');
      expect(subs.first.url, startsWith('https://subs5.strem.io/'));
      expect(subs.first.label, isNull);
    });

    test('descarta los que no tienen url o lang', () {
      final subs = parseSubtitles([
        {'id': '1', 'url': 'https://a/1.srt', 'lang': 'spa'},
        {'id': '2', 'lang': 'spa'},
        {'id': '3', 'url': 'https://a/3.srt'},
        {'url': 'https://a/4.srt', 'lang': 'eng', 'label': 'English [CC]'},
        {'id': 5, 'url': 'https://a/5.srt', 'lang': 5},
      ]);
      expect(subs.map((s) => s.url), ['https://a/1.srt', 'https://a/4.srt']);
      expect(subs.last.id, 'https://a/4.srt'); // sin id, usa la url
      expect(subs.last.label, 'English [CC]');
    });
  });
}
