import 'dart:convert';
import 'dart:io';

import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

PlaybackProgress _p(
  String metaId, {
  String type = 'movie',
  String? videoId,
  int position = 500,
  int duration = 1000,
  String? name,
  String? poster,
  DateTime? at,
}) => PlaybackProgress(
  type: type,
  metaId: metaId,
  videoId: videoId ?? metaId,
  position: Duration(seconds: position),
  duration: Duration(seconds: duration),
  name: name ?? 'Título $metaId',
  poster: poster,
  updatedAt: at ?? DateTime.utc(2026, 10, 1),
);

void main() {
  late Directory dir;
  late String filePath;

  Future<ProgressRepository> open() =>
      ProgressRepository.open(filePath: filePath);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('parcel_progress_test_');
    filePath = '${dir.path}/sub/progress.json';
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('PlaybackProgress', () {
    test('calcula la fracción vista', () {
      expect(_p('a', position: 250, duration: 1000).fraction, 0.25);
      expect(_p('a', position: 10, duration: 0).fraction, 0);
    });

    test('está en curso entre 3 % y 92 % visto, ambos incluidos', () {
      bool inProgress(int position) =>
          _p('a', position: position, duration: 1000).isInProgress;
      expect(inProgress(29), isFalse); // 2,9 %
      expect(inProgress(30), isTrue); // 3 %
      expect(inProgress(500), isTrue);
      expect(inProgress(920), isTrue); // 92 %
      expect(inProgress(921), isFalse); // 92,1 %
      expect(inProgress(1000), isFalse);
      expect(_p('a', position: 0, duration: 0).isInProgress, isFalse);
    });

    test('va y vuelve por JSON', () {
      final p = _p(
        'tt1',
        poster: 'https://x/p.jpg',
        at: DateTime.utc(2026, 10, 5, 3),
      );
      final back = PlaybackProgress.fromJson(
        jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
      );
      expect(back, p);
      expect(back.poster, 'https://x/p.jpg');
      expect(back.updatedAt, DateTime.utc(2026, 10, 5, 3));
      expect(back.position, p.position);
      expect(back.duration, p.duration);
    });
  });

  group('ProgressRepository', () {
    test('arranca vacío', () async {
      final repo = await open();
      expect(repo.get('movie', 'tt1', 'tt1'), isNull);
      expect(repo.inProgress(), isEmpty);
    });

    test('guarda y lee por (type, metaId, videoId), y persiste', () async {
      final repo = await open();
      await repo.save(_p('tt1', name: 'Peli', poster: 'https://x/p.jpg'));
      await repo.save(
        _p('tt2', type: 'series', videoId: 'tt2:1:2', position: 100),
      );

      expect(repo.get('movie', 'tt1', 'tt1')!.name, 'Peli');
      expect(
        repo.get('series', 'tt2', 'tt2:1:2')!.position,
        const Duration(seconds: 100),
      );
      expect(repo.get('series', 'tt2', 'tt2:1:3'), isNull);
      expect(repo.get('movie', 'tt2', 'tt2:1:2'), isNull);

      final reloaded = await open();
      expect(
        reloaded.get('movie', 'tt1', 'tt1'),
        repo.get('movie', 'tt1', 'tt1'),
      );
      expect(
        reloaded.get('series', 'tt2', 'tt2:1:2')!.duration,
        const Duration(seconds: 1000),
      );
    });

    test('guardar la misma clave reemplaza el anterior', () async {
      final repo = await open();
      await repo.save(_p('tt1', position: 100));
      await repo.save(_p('tt1', position: 700, at: DateTime.utc(2026, 10, 2)));
      expect(
        repo.get('movie', 'tt1', 'tt1')!.position,
        const Duration(seconds: 700),
      );
      expect((await open()).inProgress(), hasLength(1));
    });

    test('inProgress lista los en curso, el más reciente primero', () async {
      final repo = await open();
      await repo.save(_p('viejo', at: DateTime.utc(2026, 10, 1)));
      await repo.save(_p('nuevo', at: DateTime.utc(2026, 10, 3)));
      await repo.save(_p('medio', at: DateTime.utc(2026, 10, 2)));
      await repo.save(
        _p('terminado', position: 990, at: DateTime.utc(2026, 10, 4)),
      );
      await repo.save(
        _p('recien-empezado', position: 5, at: DateTime.utc(2026, 10, 5)),
      );
      expect(repo.inProgress().map((p) => p.metaId), [
        'nuevo',
        'medio',
        'viejo',
      ]);
    });

    test(
      'inProgress deja un solo episodio por serie: el último visto',
      () async {
        final repo = await open();
        await repo.save(
          _p(
            'serie',
            type: 'series',
            videoId: 'serie:1:1',
            at: DateTime.utc(2026, 10, 1),
          ),
        );
        await repo.save(
          _p(
            'serie',
            type: 'series',
            videoId: 'serie:1:3',
            at: DateTime.utc(2026, 10, 3),
          ),
        );
        await repo.save(
          _p(
            'serie',
            type: 'series',
            videoId: 'serie:1:2',
            at: DateTime.utc(2026, 10, 2),
          ),
        );
        await repo.save(_p('peli', at: DateTime.utc(2026, 10, 2, 12)));
        final list = repo.inProgress();
        expect(list.map((p) => p.videoId), ['serie:1:3', 'peli']);
      },
    );

    test(
      'si el último episodio ya terminó, queda el más reciente en curso',
      () async {
        final repo = await open();
        await repo.save(
          _p(
            'serie',
            type: 'series',
            videoId: 'serie:1:1',
            position: 500,
            at: DateTime.utc(2026, 10, 1),
          ),
        );
        await repo.save(
          _p(
            'serie',
            type: 'series',
            videoId: 'serie:1:2',
            position: 980,
            at: DateTime.utc(2026, 10, 2),
          ),
        );
        expect(repo.inProgress().map((p) => p.videoId), ['serie:1:1']);
      },
    );

    test(
      'abrir otro episodio y cerrarlo al 1 % no saca la serie de seguir viendo',
      () async {
        final repo = await open();
        await repo.save(
          _p(
            'serie',
            type: 'series',
            videoId: 'serie:1:1',
            position: 500,
            at: DateTime.utc(2026, 10, 1),
          ),
        );
        await repo.save(
          _p(
            'serie',
            type: 'series',
            videoId: 'serie:1:2',
            position: 10,
            at: DateTime.utc(2026, 10, 2),
          ),
        );
        expect(repo.inProgress().map((p) => p.videoId), ['serie:1:1']);
      },
    );

    test('una serie con todos los episodios terminados no aparece', () async {
      final repo = await open();
      await repo.save(
        _p(
          'serie',
          type: 'series',
          videoId: 'serie:1:1',
          position: 990,
          at: DateTime.utc(2026, 10, 1),
        ),
      );
      await repo.save(
        _p(
          'serie',
          type: 'series',
          videoId: 'serie:1:2',
          position: 980,
          at: DateTime.utc(2026, 10, 2),
        ),
      );
      expect(repo.inProgress(), isEmpty);
    });

    test('un archivo corrupto arranca vacío y queda como .bak', () async {
      File(filePath)
        ..createSync(recursive: true)
        ..writeAsStringSync('basura');
      final repo = await open();
      expect(repo.inProgress(), isEmpty);
      expect(File('$filePath.bak').readAsStringSync(), 'basura');
      await repo.save(_p('tt1'));
      expect((await open()).get('movie', 'tt1', 'tt1'), isNotNull);
    });

    test('bytes que no son UTF-8 cuentan como corrupto', () async {
      final bytes = [0xff, 0xfe, 0x00, 0x7b, 0xc3];
      File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      final repo = await open();
      expect(repo.inProgress(), isEmpty);
      expect(File('$filePath.bak').readAsBytesSync(), bytes);
    });

    test('descarta solo las entradas inválidas del archivo', () async {
      final repo = await open();
      await repo.save(_p('tt1'));
      final doc =
          jsonDecode(File(filePath).readAsStringSync()) as Map<String, dynamic>;
      (doc['items'] as List)
        ..add({'type': 'movie'})
        ..add('x');
      File(filePath).writeAsStringSync(jsonEncode(doc));
      final reloaded = await open();
      expect(reloaded.inProgress().map((p) => p.metaId), ['tt1']);
      expect(File('$filePath.bak').existsSync(), isFalse);
    });

    test('guardados seguidos quedan todos en el archivo', () async {
      final repo = await open();
      await Future.wait([
        for (var i = 0; i < 10; i++) repo.save(_p('tt$i', position: 100 + i)),
      ]);
      expect((await open()).inProgress(), hasLength(10));
    });
  });
}
