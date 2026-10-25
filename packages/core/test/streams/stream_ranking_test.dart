import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

AddonStream _s(
  String name, {
  String? title,
  String? description,
  String? url,
  Map<String, Object?>? hints,
}) => AddonStream.fromJson({
  'name': name,
  'title': ?title,
  'description': ?description,
  'url': url ?? 'https://cdn.example.com/${name.hashCode}.mkv',
  'behaviorHints': ?hints,
});

List<String?> _names(List<AddonStream> streams) => [
  for (final s in streams) s.name,
];

void main() {
  group('StreamSignals: resolución', () {
    int? res(String text) => StreamSignals.fromText(text).resolution;

    test('lee 2160p, 1080p, 720p y 480p', () {
      expect(res('Torrentio\n[RD+] 1080p'), 1080);
      expect(res('Movie.2160p.UHD.BluRay'), 2160);
      expect(res('Movie 720P WEB'), 720);
      expect(res('Movie.480p.DVDRip'), 480);
    });

    test('4k y UHD cuentan como 2160', () {
      expect(res('Torrentio\n[RD download] 4k'), 2160);
      expect(res('Movie UHD HDR'), 2160);
    });

    test('lee las dimensiones 1920x1080', () {
      expect(res('Movie 1920x1080 x264'), 1080);
    });

    test('lee 1080p60 y 2160p60', () {
      expect(res('Movie.1080p60.WEB'), 1080);
      expect(res('Movie 2160p60 HDR'), 2160);
    });

    test('no confunde números sueltos con una resolución', () {
      expect(res('Movie 2019 x264 1080 minutos'), isNull);
      expect(res('Sin calidad'), isNull);
    });
  });

  group('StreamSignals: cacheado en debrid', () {
    bool? cached(String text) => StreamSignals.fromText(text).cached;

    test('los [XX+] de Torrentio son cacheados', () {
      for (final tag in ['RD', 'AD', 'PM', 'DL', 'TB', 'ED', 'OC', 'PR']) {
        expect(cached('Torrentio\n[$tag+] 1080p'), isTrue, reason: tag);
      }
      expect(cached('[RD+] Torrentio\n1080p'), isTrue);
    });

    test('también ⚡ y «cached»', () {
      expect(cached('⚡ 1080p'), isTrue);
      expect(cached('Movie 1080p Cached'), isTrue);
    });

    test('[XX download], download y ⏳ son no cacheados', () {
      expect(cached('Torrentio\n[RD download] 4k'), isFalse);
      expect(cached('[AD download] Torrentio 1080p'), isFalse);
      expect(cached('⏳ Movie 1080p'), isFalse);
      expect(cached('Movie uncached'), isFalse);
    });

    test('⬇️ y [RD⬇️] son no cacheados', () {
      expect(cached('[RD⬇️] Torrentio\n1080p'), isFalse);
      expect(cached('Torrentio ⬇️ 1080p'), isFalse);
      expect(cached('[AD download] Torrentio 1080p'), isFalse);
    });

    test('«Download» suelto en el nombre del release no dice nada', () {
      expect(cached('Movie 1080p download'), isNull);
      expect(cached('Download.Movie.2023.1080p'), isNull);
    });

    test('sin señales es null (no se sabe)', () {
      expect(cached('Cinemeta 1080p'), isNull);
    });
  });

  group('StreamSignals: HDR, Dolby Vision, CAM', () {
    test('HDR y Dolby Vision', () {
      final hdr = StreamSignals.fromText('Movie.2160p.HDR10.x265');
      expect(hdr.hdr, isTrue);
      expect(hdr.dolbyVision, isFalse);
      final dv = StreamSignals.fromText('Movie 2160p Dolby Vision');
      expect(dv.dolbyVision, isTrue);
      expect(
        StreamSignals.fromText('Movie.2160p.DV.HDR.x265').dolbyVision,
        isTrue,
      );
      final plain = StreamSignals.fromText('Movie 1080p');
      expect(plain.hdr, isFalse);
      expect(plain.dolbyVision, isFalse);
    });

    test('CAM, TS, TELESYNC, HDCAM y SCREENER son isCam', () {
      for (final text in [
        'Movie.2023.CAM.x264',
        'Movie 2023 HDCAM',
        'Movie.2023.TS.x264',
        'Movie 2023 HDTS',
        'Movie.2023.TELESYNC.x264',
        'Movie.2023.SCREENER',
        'Movie.2023.DVDSCR',
      ]) {
        expect(StreamSignals.fromText(text).isCam, isTrue, reason: text);
      }
    });

    test('TS aislado cuenta; el grupo -TS y «TS audio» no', () {
      expect(StreamSignals.fromText('Movie 2023 TS x264').isCam, isTrue);
      expect(StreamSignals.fromText('Movie.2023.BluRay-TS').isCam, isFalse);
      expect(
        StreamSignals.fromText('Movie 2023 1080p TS audio').isCam,
        isFalse,
      );
      expect(
        StreamSignals.fromText('Movie 2023 1080p TS-Group').isCam,
        isFalse,
      );
    });

    test('no marca CAM por una extensión .ts ni por palabras parecidas', () {
      expect(StreamSignals.fromText('Movie.2023.1080p.ts').isCam, isFalse);
      expect(StreamSignals.fromText('Camelot 1967 1080p').isCam, isFalse);
      expect(StreamSignals.fromText('Movie 2023 WEB-DL').isCam, isFalse);
    });
  });

  group('StreamSignals: tamaño y seeders', () {
    test('💾 12.3 GB', () {
      final s = StreamSignals.fromText('Movie\n👤 50 💾 12.3 GB ⚙️ YTS');
      expect(s.sizeBytes, (12.3 * 1024 * 1024 * 1024).round());
      expect(s.seeders, 50);
    });

    test('12.3 GB sin el emoji, y MB', () {
      expect(
        StreamSignals.fromText('Movie 1080p 12.3 GB').sizeBytes,
        (12.3 * 1024 * 1024 * 1024).round(),
      );
      expect(
        StreamSignals.fromText('Movie 700 MB').sizeBytes,
        700 * 1024 * 1024,
      );
    });

    test('acepta coma decimal', () {
      expect(
        StreamSignals.fromText('💾 1,5 GB').sizeBytes,
        (1.5 * 1024 * 1024 * 1024).round(),
      );
    });

    test('coma de miles en MB', () {
      expect(
        StreamSignals.fromText('Movie 1,234 MB').sizeBytes,
        1234 * 1024 * 1024,
      );
      expect(
        StreamSignals.fromText('💾 1,234.5 MB').sizeBytes,
        (1234.5 * 1024 * 1024).round(),
      );
    });

    test('sin datos son null', () {
      final s = StreamSignals.fromText('Movie 1080p');
      expect(s.sizeBytes, isNull);
      expect(s.seeders, isNull);
    });

    test('of(stream) usa name, title, description, filename y videoSize', () {
      final s = StreamSignals.of(
        _s(
          'Torrentio\n[RD+] 4k',
          title: 'Movie.2160p.HDR\n👤 7 💾 20 GB',
          hints: {'filename': 'Movie.2160p.DV.mkv'},
        ),
      );
      expect(s.resolution, 2160);
      expect(s.cached, isTrue);
      expect(s.hdr, isTrue);
      expect(s.dolbyVision, isTrue);
      expect(s.seeders, 7);
      expect(s.sizeBytes, 20 * 1024 * 1024 * 1024);
      final fromHints = StreamSignals.of(
        _s('Directo 1080p', hints: {'videoSize': 1500000000}),
      );
      expect(fromHints.sizeBytes, 1500000000);
    });
  });

  group('rankStreams', () {
    test('descarta lo que no es reproducible', () {
      final ranked = rankStreams([
        AddonStream.fromJson({'name': 'torrent', 'infoHash': 'abc'}),
        AddonStream.fromJson({'name': 'yt', 'ytId': 'xyz'}),
        _s('directo 1080p'),
      ]);
      expect(_names(ranked), ['directo 1080p']);
    });

    test('con nombres reales de Torrentio: cacheados primero, no cacheados al final', () {
      final streams = [
        _s('Torrentio\n[RD download] 4k', title: 'M.2160p\n👤 5 💾 40 GB'),
        _s('Torrentio\n[RD+] 720p', title: 'M.720p\n👤 80 💾 1.2 GB'),
        _s('Torrentio\n[RD download] 1080p', title: 'M.1080p\n👤 9 💾 8 GB'),
        _s('Torrentio\n[RD+] 1080p', title: 'M.1080p\n👤 120 💾 4.3 GB'),
        _s('Torrentio\n[RD+] 4k HDR', title: 'M.2160p.HDR\n👤 30 💾 22 GB'),
      ];
      expect(_names(rankStreams(streams)), [
        'Torrentio\n[RD+] 1080p',
        'Torrentio\n[RD+] 4k HDR',
        'Torrentio\n[RD+] 720p',
        'Torrentio\n[RD download] 1080p',
        'Torrentio\n[RD download] 4k',
      ]);
    });

    test(
      'un stream sin señal de debrid va entre los cacheados y los no cacheados',
      () {
        final ranked = rankStreams([
          _s('[RD download] 1080p'),
          _s('Otro addon 1080p'),
          _s('[RD+] 720p'),
        ]);
        expect(_names(ranked), [
          '[RD+] 720p',
          'Otro addon 1080p',
          '[RD download] 1080p',
        ]);
      },
    );

    test('con p1080: 1080p > 2160p > 720p > resto', () {
      final ranked = rankStreams([
        _s('sin calidad'),
        _s('a 720p'),
        _s('b 2160p'),
        _s('c 480p'),
        _s('d 1080p'),
      ]);
      expect(_names(ranked), [
        'd 1080p',
        'b 2160p',
        'a 720p',
        'sin calidad',
        'c 480p',
      ]);
    });

    test('con p2160: 2160p > 1080p > 720p', () {
      final ranked = rankStreams([
        _s('a 720p'),
        _s('b 1080p'),
        _s('c 2160p'),
      ], quality: QualityPreference.p2160);
      expect(_names(ranked), ['c 2160p', 'b 1080p', 'a 720p']);
    });

    test('con p720: 720p > 1080p > 2160p', () {
      final ranked = rankStreams([
        _s('c 2160p'),
        _s('b 1080p'),
        _s('a 720p'),
      ], quality: QualityPreference.p720);
      expect(_names(ranked), ['a 720p', 'b 1080p', 'c 2160p']);
    });

    test('un CAM va después de las versiones buenas de su grupo', () {
      final ranked = rankStreams([
        _s('Movie.2023.1080p.CAM'),
        _s('Movie.2023.720p.WEB-DL'),
        _s('Movie.2023.1080p.HDTS'),
        _s('Movie.2023.1080p.BluRay'),
      ]);
      expect(_names(ranked), [
        'Movie.2023.1080p.BluRay',
        'Movie.2023.720p.WEB-DL',
        'Movie.2023.1080p.CAM',
        'Movie.2023.1080p.HDTS',
      ]);
    });

    test('a igualdad respeta el orden original (y el de los addons)', () {
      final ranked = rankStreams([
        _s('addon A 1080p', url: 'https://a.example.com/1'),
        _s('addon B 1080p', url: 'https://b.example.com/1'),
        _s('addon A 1080p bis', url: 'https://a.example.com/2'),
      ]);
      expect(_names(ranked), [
        'addon A 1080p',
        'addon B 1080p',
        'addon A 1080p bis',
      ]);
    });

    test('no modifica la lista de entrada', () {
      final input = [_s('a 720p'), _s('b 1080p')];
      rankStreams(input);
      expect(_names(input), ['a 720p', 'b 1080p']);
    });

    test('lista vacía', () {
      expect(rankStreams(const []), isEmpty);
    });
  });
}
