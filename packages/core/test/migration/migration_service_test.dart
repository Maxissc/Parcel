import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

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
  late List<String> requested;
  late AddonRepository repo;
  late MigrationService service;

  /// `caido.example.com` devuelve 500, `lento.example.com` corta la conexión,
  /// `roto.example.com` devuelve algo que no es un manifest; el resto
  /// devuelve un manifest con id `test.<subdominio>`.
  Future<http.Response> handler(http.Request req) async {
    requested.add(req.url.host);
    switch (req.url.host) {
      case 'caido.example.com':
        return http.Response('x', 500);
      case 'lento.example.com':
        throw http.ClientException('cortada');
      case 'roto.example.com':
        return http.Response('<html>', 200);
    }
    return _json(_manifestJson('test.${req.url.host.split('.').first}'));
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('parcel_migration_test_');
    requested = [];
    repo = await AddonRepository.open(
      client: AddonClient(MockClient(handler)),
      filePath: '${dir.path}/addons.json',
    );
    service = MigrationService(repo);
  });

  tearDown(() async {
    await repo.dispose();
    dir.deleteSync(recursive: true);
  });

  MigrationPlan pasted(
    List<String> hosts, {
    List<InstalledAddon> installed = const [],
  }) => MigrationPlan.fromPasted(
    hosts.map((h) => 'https://$h/fake-user-token/manifest.json'),
    installed: installed,
  );

  test(
    'instala los seleccionados en el orden del plan, no el de la selección',
    () async {
      final plan = pasted(['a.example.com', 'b.example.com', 'c.example.com']);
      final report = await service.apply(plan, [
        plan.candidates[2],
        plan.candidates[0],
      ]);
      expect(repo.addons.map((a) => a.manifest.id), ['test.a', 'test.c']);
      expect(report.items.map((i) => i.outcome), [
        MigrationOutcome.installed,
        MigrationOutcome.installed,
      ]);
      expect(report.items.map((i) => i.candidate.displayName), [
        'a.example.com',
        'c.example.com',
      ]);
    },
  );

  test('lo que no se selecciona no se instala ni se descarga', () async {
    final plan = pasted(['a.example.com', 'b.example.com']);
    await service.apply(plan, [plan.candidates[1]]);
    expect(requested, ['b.example.com']);
  });

  test('un candidato que no es del plan se ignora', () async {
    final plan = pasted(['a.example.com']);
    final other = pasted(['z.example.com']);
    final report = await service.apply(plan, other.candidates);
    expect(report.items, isEmpty);
    expect(repo.addons, isEmpty);
  });

  test('usa el manifest embebido sin descargar nada', () async {
    final plan = MigrationPlan.fromStremio([
      StremioAddonEntry(
        transportUrl:
            'https://embebido.example.com/fake-user-token/manifest.json',
        manifest: _manifestJson('test.embebido'),
      ),
    ]);
    final report = await service.apply(plan, plan.candidates);
    expect(requested, isEmpty);
    expect(report.items.single.outcome, MigrationOutcome.installed);
    expect(repo.addons.single.manifest.id, 'test.embebido');
  });

  test('sin manifest embebido lo baja', () async {
    final plan = pasted(['a.example.com']);
    await service.apply(plan, plan.candidates);
    expect(requested, ['a.example.com']);
  });

  test(
    'si el disco falla en un addon lo reporta y sigue con el resto',
    () async {
      // Una carpeta en el lugar del temporal hace fallar la escritura.
      final blocker = Directory('${dir.path}/otro.json.tmp');
      final failing = await AddonRepository.open(
        client: AddonClient(
          MockClient((req) async {
            if (req.url.host == 'a.example.com') {
              blocker.createSync();
            } else if (blocker.existsSync()) {
              blocker.deleteSync();
            }
            return _json(
              _manifestJson('test.${req.url.host.split('.').first}'),
            );
          }),
        ),
        filePath: '${dir.path}/otro.json',
      );
      final svc = MigrationService(failing);
      final plan = pasted(['a.example.com', 'b.example.com']);

      final report = await svc.apply(plan, plan.candidates);
      await failing.dispose();

      expect(report.items.first.outcome, MigrationOutcome.failed);
      expect(report.items.first.message, 'No se pudo guardar en disco.');
      expect(report.items.last.outcome, MigrationOutcome.installed);
      expect(failing.addons.map((a) => a.manifest.id), ['test.b']);
    },
  );

  test('sigue ante fallas y cuenta cada resultado', () async {
    final plan = pasted([
      'a.example.com',
      'caido.example.com',
      'lento.example.com',
      'roto.example.com',
      'b.example.com',
    ]);
    final report = await service.apply(plan, plan.candidates);
    expect(report.items.map((i) => i.outcome), [
      MigrationOutcome.installed,
      MigrationOutcome.failed,
      MigrationOutcome.failed,
      MigrationOutcome.failed,
      MigrationOutcome.installed,
    ]);
    expect(report.installedCount, 2);
    expect(report.failedCount, 3);
    expect(report.alreadyInstalledCount, 0);
    expect(repo.addons.map((a) => a.manifest.id), ['test.a', 'test.b']);
  });

  test('los motivos de falla están en español y sin la URL', () async {
    final plan = pasted([
      'caido.example.com',
      'lento.example.com',
      'roto.example.com',
    ]);
    final report = await service.apply(plan, plan.candidates);
    expect(
      report.items[0].message,
      'El addon respondió con un error (HTTP 500).',
    );
    expect(report.items[1].message, 'No se pudo conectar con el addon.');
    expect(report.items[2].message, 'El addon no devolvió un manifest válido.');
    for (final item in report.items) {
      expect(item.message, isNot(contains('fake-user-token')));
      expect(item.message, isNot(contains('example.com')));
    }
  });

  test('un manifest embebido inválido falla con motivo legible', () async {
    final plan = MigrationPlan.fromStremio([
      const StremioAddonEntry(
        transportUrl: 'https://x.example.com/manifest.json',
        manifest: {'foo': 'bar'},
      ),
    ]);
    final report = await service.apply(plan, plan.candidates);
    expect(report.items.single.outcome, MigrationOutcome.failed);
    expect(
      report.items.single.message,
      'El addon no devolvió un manifest válido.',
    );
  });

  test('un addon que ya estaba se informa como ya instalado', () async {
    final first = pasted(['a.example.com']);
    await service.apply(first, first.candidates);
    requested.clear();

    final plan = pasted(['a.example.com', 'b.example.com']);
    final report = await service.apply(plan, plan.candidates);
    expect(report.items[0].outcome, MigrationOutcome.alreadyInstalled);
    expect(report.items[0].message, 'Ya estaba instalado.');
    expect(report.items[1].outcome, MigrationOutcome.installed);
    expect(report.alreadyInstalledCount, 1);
    expect(report.installedCount, 1);
    expect(repo.addons, hasLength(2));
  });

  test('el mismo addon seleccionado dos veces se instala una sola', () async {
    final plan = MigrationPlan.fromNuvio([
      const NuvioAddon(
        url: 'https://a.example.com/manifest.json',
        profileId: 1,
      ),
      const NuvioAddon(
        url: 'https://a.example.com/manifest.json',
        profileId: 2,
      ),
    ]);
    final report = await service.apply(plan, plan.candidates);
    expect(report.items, hasLength(1));
    expect(repo.addons, hasLength(1));
  });

  test('toString del informe no incluye URLs completas', () async {
    final plan = pasted(['a.example.com', 'caido.example.com']);
    final report = await service.apply(plan, plan.candidates);
    expect('$report ${report.items}', isNot(contains('fake-user-token')));
  });
}
