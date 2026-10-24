import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

import '../support.dart';

Future<List<StremioAddonEntry>> _stremioEntries() => StremioAccountClient(
  MockClient(
    (_) async => http.Response(
      fixtureText('migration/stremio_addon_collection.json'),
      200,
    ),
  ),
).getAddonCollection('fake-auth-key');

List<NuvioAddon> _nuvioRows() => [
  for (final row
      in jsonDecode(fixtureText('migration/nuvio_addons.json')) as List)
    if ((row as Map)['url'] != null)
      NuvioAddon(
        url: row['url'] as String,
        name: row['name'] as String?,
        enabled: row['enabled'] as bool,
        sortOrder: row['sort_order'] as int,
        profileId: row['profile_id'] as int,
      ),
];

InstalledAddon _installed(String url, String id) => InstalledAddon(
  transportUrl: url,
  manifest: AddonManifest.fromJson({
    'id': id,
    'name': 'Instalado $id',
    'version': '1.0.0',
    'resources': ['stream'],
    'types': ['movie'],
  }),
);

void main() {
  group('plan de Stremio', () {
    late MigrationPlan plan;

    setUp(() async {
      plan = MigrationPlan.fromStremio(await _stremioEntries());
    });

    test('conserva el orden de Stremio y descarta Local Files', () {
      expect(plan.source, MigrationSource.stremio);
      expect(plan.candidates.map((c) => c.displayName), [
        'Cinemeta',
        'OpenSubtitles v3',
        'Addon Comunitario',
      ]);
    });

    test('Local Files queda aparte con su nota', () {
      expect(plan.discarded, hasLength(1));
      final local = plan.discarded.single;
      expect(local.displayName, 'Local Files');
      expect(local.note, 'Solo funciona dentro de Stremio');
      expect(local.selectedByDefault, isFalse);
    });

    test(
      'descarta cualquier addon a localhost o 127.0.0.1, aunque tenga otro id',
      () {
        final plan = MigrationPlan.fromStremio([
          const StremioAddonEntry(
            transportUrl: 'http://localhost:7000/manifest.json',
          ),
          const StremioAddonEntry(
            transportUrl: 'http://127.0.0.1:1/x/manifest.json',
          ),
          const StremioAddonEntry(
            transportUrl: 'https://ok.example.com/manifest.json',
          ),
        ]);
        expect(plan.candidates.map((c) => redactAddonUrl(c.transportUrl)), [
          'ok.example.com',
        ]);
        expect(plan.discarded, hasLength(2));
      },
    );

    test('los oficiales entran seleccionados, con manifest embebido', () {
      final cinemeta = plan.candidates[0];
      expect(cinemeta.selectedByDefault, isTrue);
      expect(cinemeta.manifest!['id'], 'com.linvo.cinemeta');
      expect(cinemeta.source, MigrationSource.stremio);
      expect(plan.candidates[1].selectedByDefault, isTrue);
    });

    test('los de la comunidad también entran seleccionados', () {
      expect(plan.candidates[2].selectedByDefault, isTrue);
      expect(plan.candidates[2].note, isNull);
    });

    test('los ya instalados se marcan y no se seleccionan', () async {
      final plan = MigrationPlan.fromStremio(
        await _stremioEntries(),
        installed: [
          _installed('https://v3-cinemeta.strem.io/manifest.json', 'x.otro'),
        ],
      );
      final cinemeta = plan.candidates[0];
      expect(cinemeta.alreadyInstalled, isTrue);
      expect(cinemeta.note, 'Ya instalado');
      expect(cinemeta.selectedByDefault, isFalse);
      expect(plan.candidates[1].alreadyInstalled, isFalse);
    });

    test(
      'también cuenta como instalado si coincide el id del manifest',
      () async {
        final plan = MigrationPlan.fromStremio(
          await _stremioEntries(),
          installed: [
            _installed(
              'https://otro.example.com/manifest.json',
              'test.comunidad',
            ),
          ],
        );
        expect(plan.candidates[2].alreadyInstalled, isTrue);
        expect(plan.candidates[2].selectedByDefault, isFalse);
      },
    );

    test(
      'defaultSelection devuelve los seleccionados por defecto en orden',
      () {
        expect(plan.defaultSelection().map((c) => c.displayName), [
          'Cinemeta',
          'OpenSubtitles v3',
          'Addon Comunitario',
        ]);
      },
    );

    test('una URL inválida va a descartados', () {
      final plan = MigrationPlan.fromStremio([
        const StremioAddonEntry(transportUrl: 'esto no es una url'),
      ]);
      expect(plan.candidates, isEmpty);
      expect(plan.discarded.single.note, 'La dirección no es válida');
    });

    test('toString del candidato no incluye la URL completa', () {
      final text = '${plan.candidates[2]}';
      expect(text, isNot(contains('fake-user-token')));
      expect(text, contains('comunidad.example.com'));
    });
  });

  group('plan de Nuvio', () {
    late MigrationPlan plan;

    setUp(() => plan = MigrationPlan.fromNuvio(_nuvioRows()));

    test('expone los perfiles y elige el 1 por defecto', () {
      expect(plan.source, MigrationSource.nuvio);
      expect(plan.profileIds, [1, 2]);
      expect(plan.defaultProfileId, 1);
    });

    test('agrupa por perfil conservando sort_order', () {
      expect(plan.candidatesForProfile(1).map((c) => c.displayName), [
        'Cinemeta',
        'Torrent',
      ]);
      expect(plan.candidatesForProfile(2).map((c) => c.transportUrl), [
        'https://opensubtitles-v3.strem.io/manifest.json',
      ]);
    });

    test('ordena por sort_order aunque lleguen desordenadas', () {
      final plan = MigrationPlan.fromNuvio([
        const NuvioAddon(url: 'https://b.example.com', sortOrder: 5),
        const NuvioAddon(url: 'https://a.example.com', sortOrder: 2),
      ]);
      expect(plan.candidates.map((c) => c.displayName), [
        'a.example.com',
        'b.example.com',
      ]);
    });

    test('enabled=false entra sin seleccionar y con nota', () {
      final torrent = plan.candidatesForProfile(1)[1];
      expect(torrent.selectedByDefault, isFalse);
      expect(torrent.note, 'Desactivado en Nuvio');
      expect(plan.candidatesForProfile(1)[0].selectedByDefault, isTrue);
    });

    test('defaultSelection respeta el perfil elegido', () {
      expect(plan.defaultSelection().map((c) => c.displayName), ['Cinemeta']);
      expect(plan.defaultSelection(profileId: 2), hasLength(1));
    });

    test('si no hay perfil 1, el default es el menor', () {
      final plan = MigrationPlan.fromNuvio([
        const NuvioAddon(url: 'https://a.example.com', profileId: 3),
        const NuvioAddon(url: 'https://b.example.com', profileId: 2),
      ]);
      expect(plan.profileIds, [2, 3]);
      expect(plan.defaultProfileId, 2);
    });

    test('con un solo perfil, profileIds tiene uno', () {
      final plan = MigrationPlan.fromNuvio([
        const NuvioAddon(url: 'https://a.example.com'),
      ]);
      expect(plan.profileIds, [1]);
    });

    test('normaliza las URLs sin manifest.json y marca los instalados', () {
      final plan = MigrationPlan.fromNuvio(
        _nuvioRows(),
        installed: [
          _installed('https://opensubtitles-v3.strem.io/manifest.json', 'a.b'),
        ],
      );
      final os = plan.candidatesForProfile(2).single;
      expect(os.alreadyInstalled, isTrue);
      expect(os.note, 'Ya instalado');
      expect(os.selectedByDefault, isFalse);
    });

    test('una URL repetida dentro del mismo perfil aparece una sola vez', () {
      final plan = MigrationPlan.fromNuvio([
        const NuvioAddon(url: 'https://a.example.com', sortOrder: 0),
        const NuvioAddon(
          url: 'https://a.example.com/manifest.json',
          sortOrder: 1,
        ),
      ]);
      expect(plan.candidates, hasLength(1));
    });
  });

  group('plan de texto pegado', () {
    test('todos seleccionados, con el host como nombre', () {
      final plan = MigrationPlan.fromPastedText(
        'https://a.example.com/tok/manifest.json\nstremio://b.example.com',
      );
      expect(plan.source, MigrationSource.pasted);
      expect(plan.candidates.map((c) => c.displayName), [
        'a.example.com',
        'b.example.com',
      ]);
      expect(plan.candidates.every((c) => c.selectedByDefault), isTrue);
      expect(plan.candidates.every((c) => c.manifest == null), isTrue);
    });

    test('marca los ya instalados y no los selecciona', () {
      final plan = MigrationPlan.fromPastedText(
        'https://a.example.com/manifest.json https://b.example.com/manifest.json',
        installed: [_installed('https://a.example.com/manifest.json', 'a.a')],
      );
      expect(plan.candidates[0].alreadyInstalled, isTrue);
      expect(plan.candidates[0].selectedByDefault, isFalse);
      expect(plan.candidates[1].selectedByDefault, isTrue);
    });

    test('sin URLs, el plan queda vacío', () {
      expect(MigrationPlan.fromPastedText('hola').candidates, isEmpty);
    });
  });
}
