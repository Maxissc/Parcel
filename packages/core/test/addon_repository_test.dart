import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

import 'support.dart';

Map<String, dynamic> _manifestJson(String id) => {
  'id': id,
  'name': 'Addon $id',
  'version': '1.0.0',
  'description': 'd',
  'resources': ['stream'],
  'types': ['movie'],
};

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late Directory dir;
  late String filePath;
  late List<String> requested;

  /// Los hosts `x.example.com` devuelven un manifest con id `test.x`;
  /// `caido.example.com` devuelve 500; `mismo-id.example.com` repite el id de `a`.
  Future<http.Response> handler(http.Request req) async {
    requested.add(req.url.toString());
    final host = req.url.host;
    if (host == 'caido.example.com') return http.Response('x', 500);
    if (host == 'mismo-id.example.com') return _json(_manifestJson('test.a'));
    return _json(_manifestJson('test.${host.split('.').first}'));
  }

  Future<AddonRepository> open() => AddonRepository.open(
    client: AddonClient(MockClient(handler)),
    filePath: filePath,
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('parcel_repo_test_');
    filePath = '${dir.path}/sub/addons.json';
    requested = [];
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('arranca vacío si no hay archivo', () async {
    final repo = await open();
    expect(repo.addons, isEmpty);
  });

  group('instalar', () {
    test('baja el manifest, lo agrega y avisa el cambio', () async {
      final repo = await open();
      final changes = <List<InstalledAddon>>[];
      repo.changes.listen(changes.add);

      final result = await repo.install('stremio://a.example.com/');

      expect(result, isA<Installed>());
      final addon = (result as Installed).addon;
      expect(addon.transportUrl, 'https://a.example.com/manifest.json');
      expect(requested, ['https://a.example.com/manifest.json']);
      expect(repo.addons, [addon]);
      await pumpEventQueue();
      expect(changes, [
        [addon],
      ]);
    });

    test(
      'persiste en un archivo JSON y se recarga en el mismo orden',
      () async {
        final repo = await open();
        await repo.install('https://a.example.com/manifest.json');
        await repo.install('https://b.example.com/manifest.json');

        final reloaded = await open();
        expect(reloaded.addons.map((a) => a.manifest.id), ['test.a', 'test.b']);
        expect(reloaded.addons.first, repo.addons.first);
        expect(
          jsonDecode(File(filePath).readAsStringSync()),
          isA<Map<String, dynamic>>(),
        );
      },
    );

    test(
      'rechaza un duplicado por transportUrl normalizada sin bajar nada',
      () async {
        final repo = await open();
        await repo.install('https://a.example.com/manifest.json');
        requested.clear();

        for (final again in [
          'stremio://a.example.com/manifest.json',
          ' https://A.example.com ',
          'https://a.example.com/manifest.json/',
        ]) {
          final result = await repo.install(again);
          expect(result, isA<AlreadyInstalled>(), reason: again);
        }
        expect(requested, isEmpty);
        expect(repo.addons, hasLength(1));
      },
    );

    test('rechaza un duplicado por manifest.id aunque cambie la URL', () async {
      final repo = await open();
      await repo.install('https://a.example.com/manifest.json');
      final result = await repo.install(
        'https://mismo-id.example.com/manifest.json',
      );
      expect(result, isA<AlreadyInstalled>());
      expect(
        (result as AlreadyInstalled).existing.transportUrl,
        'https://a.example.com/manifest.json',
      );
      expect(repo.addons, hasLength(1));
    });

    test('devuelve la falla con motivo y no agrega nada', () async {
      final repo = await open();
      final http500 = await repo.install('https://caido.example.com');
      expect(http500, isA<InstallFailed>());
      expect((http500 as InstallFailed).error.reason, AddonFailureReason.http);
      final bad = await repo.install('esto no es una url');
      expect(
        (bad as InstallFailed).error.reason,
        AddonFailureReason.invalidUrl,
      );
      expect(repo.addons, isEmpty);
    });

    test('dos instalaciones concurrentes quedan ambas en el archivo', () async {
      final repo = await open();
      await Future.wait([
        repo.install('https://a.example.com'),
        repo.install('https://b.example.com'),
        repo.install('https://a.example.com'),
      ]);
      expect(repo.addons, hasLength(2));
      expect((await open()).addons, hasLength(2));
    });

    test('un timeout al bajar el manifest es una falla de timeout', () async {
      final repo = await AddonRepository.open(
        client: AddonClient(
          MockClient((_) => Completer<http.Response>().future),
        ),
        filePath: filePath,
        installTimeout: const Duration(milliseconds: 50),
      );
      final result = await repo.install('https://lento.example.com');
      expect(
        (result as InstallFailed).error.reason,
        AddonFailureReason.timeout,
      );
    });
  });

  group('instalar desde un manifest conocido', () {
    test('no baja nada y normaliza la transportUrl', () async {
      final repo = await open();
      final result = await repo.installManifest(
        'stremio://k.example.com/cfg',
        fixture('opensubtitles_manifest.json'),
      );
      expect(requested, isEmpty);
      final addon = (result as Installed).addon;
      expect(addon.transportUrl, 'https://k.example.com/cfg/manifest.json');
      expect(addon.manifest.name, 'OpenSubtitles v3');
      expect((await open()).addons, [addon]);
    });

    test('también rechaza duplicados y manifests inválidos', () async {
      final repo = await open();
      final json = fixture('opensubtitles_manifest.json');
      await repo.installManifest('https://k.example.com', json);
      expect(
        await repo.installManifest('https://otra.example.com', json),
        isA<AlreadyInstalled>(),
      );
      final bad = await repo.installManifest('https://z.example.com', {'x': 1});
      expect((bad as InstallFailed).error.reason, AddonFailureReason.parse);
      final badUrl = await repo.installManifest('nada', json);
      expect(
        (badUrl as InstallFailed).error.reason,
        AddonFailureReason.invalidUrl,
      );
    });
  });

  group('installAll', () {
    test('instala en orden, sigue ante fallas e informa por URL', () async {
      final repo = await open();
      await repo.install('https://b.example.com');
      final urls = [
        'https://a.example.com',
        'https://b.example.com/manifest.json',
        'https://caido.example.com',
        'nada',
        'https://c.example.com',
      ];
      final report = await repo.installAll(urls);

      expect(report.map((r) => r.url), urls);
      expect(report[0].result, isA<Installed>());
      expect(report[1].result, isA<AlreadyInstalled>());
      expect(report[2].result, isA<InstallFailed>());
      expect(report[3].result, isA<InstallFailed>());
      expect(report[4].result, isA<Installed>());
      expect(repo.addons.map((a) => a.manifest.id), [
        'test.b',
        'test.a',
        'test.c',
      ]);
    });
  });

  group('quitar y reordenar', () {
    test('quita por transportUrl y persiste', () async {
      final repo = await open();
      await repo.install('https://a.example.com');
      await repo.install('https://b.example.com');
      expect(await repo.remove('stremio://a.example.com'), isTrue);
      expect(await repo.remove('https://a.example.com'), isFalse);
      expect(repo.addons.map((a) => a.manifest.id), ['test.b']);
      expect((await open()).addons.map((a) => a.manifest.id), ['test.b']);
    });

    test('reordena moviendo al índice final y persiste', () async {
      final repo = await open();
      for (final h in ['a', 'b', 'c']) {
        await repo.install('https://$h.example.com');
      }
      final changes = <List<InstalledAddon>>[];
      repo.changes.listen(changes.add);

      await repo.reorder(2, 0);
      expect(repo.addons.map((a) => a.manifest.id), [
        'test.c',
        'test.a',
        'test.b',
      ]);
      await repo.reorder(0, 1);
      expect(repo.addons.map((a) => a.manifest.id), [
        'test.a',
        'test.c',
        'test.b',
      ]);
      expect((await open()).addons.map((a) => a.manifest.id), [
        'test.a',
        'test.c',
        'test.b',
      ]);
      await pumpEventQueue();
      expect(changes, hasLength(2));
      expect(() => repo.reorder(0, 3), throwsRangeError);
    });

    test('la lista expuesta no se puede modificar desde afuera', () async {
      final repo = await open();
      await repo.install('https://a.example.com');
      expect(() => repo.addons.clear(), throwsUnsupportedError);
    });
  });

  group('archivo en disco', () {
    test('si está corrupto arranca vacío y lo conserva como .bak', () async {
      File(filePath)
        ..createSync(recursive: true)
        ..writeAsStringSync('{esto no es json');
      final repo = await open();
      expect(repo.addons, isEmpty);
      expect(File('$filePath.bak').readAsStringSync(), '{esto no es json');
      expect(File(filePath).existsSync(), isFalse);

      await repo.install('https://a.example.com');
      expect((await open()).addons, hasLength(1));
      expect(File('$filePath.bak').readAsStringSync(), '{esto no es json');
    });

    test('bytes que no son UTF-8 cuentan como corrupto', () async {
      final bytes = [0xff, 0xfe, 0x00, 0x7b, 0xc3];
      File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      final repo = await open();
      expect(repo.addons, isEmpty);
      expect(File('$filePath.bak').readAsBytesSync(), bytes);
    });

    test(
      'un JSON válido con otra forma también se conserva como .bak',
      () async {
        File(filePath)
          ..createSync(recursive: true)
          ..writeAsStringSync('[1, 2, 3]');
        final repo = await open();
        expect(repo.addons, isEmpty);
        expect(File('$filePath.bak').readAsStringSync(), '[1, 2, 3]');
      },
    );

    test('descarta solo las entradas inválidas', () async {
      final repo = await open();
      await repo.install('https://a.example.com');
      final doc =
          jsonDecode(File(filePath).readAsStringSync()) as Map<String, dynamic>;
      (doc['addons'] as List).insert(0, {'transportUrl': 'x'});
      File(filePath).writeAsStringSync(jsonEncode(doc));

      final reloaded = await open();
      expect(reloaded.addons.map((a) => a.manifest.id), ['test.a']);
      expect(File('$filePath.bak').existsSync(), isFalse);
    });

    test('escribe de forma atómica: no deja el archivo temporal', () async {
      final repo = await open();
      File('$filePath.tmp')
        ..createSync(recursive: true)
        ..writeAsStringSync('resto de una escritura cortada');
      await repo.install('https://a.example.com');
      expect(File('$filePath.tmp').existsSync(), isFalse);
      expect(
        () => jsonDecode(File(filePath).readAsStringSync()),
        returnsNormally,
      );
    });
  });

  test('los addons por defecto son Cinemeta y OpenSubtitles v3', () {
    expect(defaultAddonUrls, [
      'https://v3-cinemeta.strem.io/manifest.json',
      'https://opensubtitles-v3.strem.io/manifest.json',
    ]);
    expect(cinemetaManifestUrl, defaultAddonUrls.first);
    expect(openSubtitlesManifestUrl, defaultAddonUrls.last);
  });
}
