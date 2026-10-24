import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/data/app_data.dart';
import 'package:parcel_desktop/data/app_settings.dart';
import 'package:parcel_desktop/data/providers.dart';

import 'support/test_env.dart';

void main() {
  late Directory dir;

  setUp(() => dir = makeTempDir());
  tearDown(() => dir.deleteSync(recursive: true));

  group('resolveDataDirectory', () {
    final support = Directory('C:/soporte');

    test(
      'en debug, PARCEL_DATA_DIR manda sobre la carpeta de soporte',
      () async {
        final result = await resolveDataDirectory(
          environment: {'PARCEL_DATA_DIR': 'D:/datos-de-prueba'},
          supportDirectory: () async => support,
          debug: true,
        );
        expect(result.path, 'D:/datos-de-prueba');
      },
    );

    test('fuera de debug ignora PARCEL_DATA_DIR', () async {
      final result = await resolveDataDirectory(
        environment: {'PARCEL_DATA_DIR': 'D:/datos-de-prueba'},
        supportDirectory: () async => support,
        debug: false,
      );
      expect(result.path, endsWith('Parcel'));
      expect(result.path, startsWith(support.path));
    });

    test('sin variable usa Parcel dentro de la carpeta de soporte', () async {
      final result = await resolveDataDirectory(
        environment: {'PARCEL_DATA_DIR': '  '},
        supportDirectory: () async => support,
        debug: true,
      );
      expect(result.path, '${support.path}${Platform.pathSeparator}Parcel');
    });
  });

  group('ajustes', () {
    test('guardan el asistente y los idiomas, y se leen al reabrir', () async {
      final path = '${dir.path}/settings.json';
      final store = await SettingsStore.open(path);
      expect(store.value.onboardingCompleted, isFalse);

      await store.save(
        store.value.copyWith(
          onboardingCompleted: true,
          audioLanguage: 'spa',
          subtitleLanguage: 'eng',
        ),
      );
      final reopened = await SettingsStore.open(path);
      expect(reopened.value.onboardingCompleted, isTrue);
      expect(reopened.value.audioLanguage, 'spa');
      expect(reopened.value.subtitleLanguage, 'eng');

      // Quitar la preferencia deja null y no toca lo demás.
      await reopened.save(reopened.value.copyWith(audioLanguage: null));
      final again = await SettingsStore.open(path);
      expect(again.value.audioLanguage, isNull);
      expect(again.value.subtitleLanguage, 'eng');
      expect(again.value.onboardingCompleted, isTrue);
    });

    test('un archivo corrupto arranca por defecto y queda como .bak', () async {
      final path = '${dir.path}/settings.json';
      File(path).writeAsStringSync('{no es json');
      final store = await SettingsStore.open(path);
      expect(store.value, const AppSettings());
      expect(File('$path.bak').existsSync(), isTrue);
    });
  });

  group('addons instalados', () {
    test('quitar y deshacer devuelve el addon a su lugar y persiste', () async {
      final container = await openContainer(dir, mockWorld(defaultRoutes()));
      addTearDown(container.dispose);
      await preinstall(container, [cinemetaUrl, subtitlesUrl, torrentUrl]);
      final notifier = container.read(installedAddonsProvider.notifier);
      final subtitles = container.read(installedAddonsProvider)[1];

      final index = await notifier.remove(subtitles);
      expect(index, 1);
      expect(
        container.read(installedAddonsProvider).map((a) => a.manifest.name),
        ['Cinemeta', 'Torrent'],
      );
      expect(await savedAddonNames(dir), ['Cinemeta', 'Torrent']);

      await notifier.restore(subtitles, index);
      expect(
        container.read(installedAddonsProvider).map((a) => a.manifest.name),
        ['Cinemeta', 'OpenSubtitles v3', 'Torrent'],
      );
      expect(await savedAddonNames(dir), [
        'Cinemeta',
        'OpenSubtitles v3',
        'Torrent',
      ]);
    });

    test('reordenar persiste el nuevo orden', () async {
      final container = await openContainer(dir, mockWorld(defaultRoutes()));
      addTearDown(container.dispose);
      await preinstall(container, [cinemetaUrl, subtitlesUrl, torrentUrl]);

      await container.read(installedAddonsProvider.notifier).move(2, 0);

      expect(
        container.read(installedAddonsProvider).map((a) => a.manifest.name),
        ['Torrent', 'Cinemeta', 'OpenSubtitles v3'],
      );
      expect(await savedAddonNames(dir), [
        'Torrent',
        'Cinemeta',
        'OpenSubtitles v3',
      ]);
    });
  });

  test(
    'borrar todos los datos vacía addons y ajustes en disco y en memoria',
    () async {
      final container = await openContainer(dir, mockWorld(defaultRoutes()));
      addTearDown(container.dispose);
      await preinstall(container, [cinemetaUrl]);
      await container.read(appSettingsProvider.notifier).completeOnboarding();
      expect(File('${dir.path}/addons.json').existsSync(), isTrue);
      expect(File('${dir.path}/settings.json').existsSync(), isTrue);

      await container.read(dataResetProvider).wipe();
      await container.read(appDataProvider.future);

      expect(File('${dir.path}/addons.json').existsSync(), isFalse);
      expect(File('${dir.path}/settings.json').existsSync(), isFalse);
      expect(container.read(addonRepositoryProvider).addons, isEmpty);
      expect(container.read(appSettingsProvider).onboardingCompleted, isFalse);
    },
  );

  test(
    'el agregador y el servicio de migración usan el repositorio abierto',
    () async {
      final container = await openContainer(dir, mockWorld(defaultRoutes()));
      addTearDown(container.dispose);
      final service = container.read(migrationServiceProvider);
      final plan = MigrationPlan.fromPasted([cinemetaUrl]);
      final report = await service.apply(plan, plan.candidates);
      expect(report.installedCount, 1);
      expect(
        container.read(addonAggregatorProvider).addons().single.manifest.name,
        'Cinemeta',
      );
    },
  );
}
